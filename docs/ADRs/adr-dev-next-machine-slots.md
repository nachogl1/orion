# ADR: cap heavy work on the machine, not agents, and bring QA back before merge

**Status: proposed, awaiting the owner's approval. No code exists for it yet.**

## Context

Running `/dev-next` with more than two issues, with QA in the loop, ate the machine and stalled. The workaround in
use is to run at most two issues and no QA. That keeps a laptop alive but halves throughput and lets regressions
merge unseen until a later `/harvest-qa`.

A read-only review of the skills, the Claude Code docs and real run records from a .NET plus Angular project (five
developers, two issues per run) found that the agent count is not the cause. What is:

1. **Every issue runs the project's full local gate several times** (a baseline, after the change, after each
   review round). On a typical stack that is a restore, two builds, two test passes and an end to end run whose
   browser workers default to half the cores. Run records say it plainly: "Parallel worktree builds exhausted
   memory".
2. **Nothing caps heavy work across the machine, and nothing stops what a gate started.** `SKILL.md` says "The
   machine has no cap"; only the merge slot is shared. One leftover database container, started by a gate for an
   issue that had closed the day before, was still using two cores and 1.8 GB 22 hours later. Build servers
   lingered for a day.
3. **Fixed ports and reuse of a running server.** Without a per-issue port rule, gates in sibling worktrees bind
   the same ports, and test runners that reuse an existing server test another worktree's code. Records: "concurrent
   runs break each other".
4. **Gates outlive the foreground Bash limit.** On a loaded machine a gate passes ten minutes, Claude Code moves it
   to the background, and the agent goes idle with no deadline. The reviewer's CI wait loops "until it completes".
   Records: "reviewer went idle for ~2h".
5. **The orchestrator never sheds context.** Every report, CI poll and merge-slot re-read (every 60 s, no time
   limit) stays in one session. A skill cannot run `/compact`, and after an automatic compaction only the first
   5,000 tokens of each skill come back, while the run rules sit near the end of a 40 KB `SKILL.md`.

QA collides with gates for the same reason as cause 3: it starts the whole product on the same ports. That is why
`/harvest-qa` already runs one agent at a time.

## Decision

Cap **heavy work** on the machine, keep issues at 1 to 4 per run and agents uncapped, and make every wait end.
Four pull requests, in order:

1. **Machine slots** (`skills/dev-next/scripts/gov.sh`, portable bash). Every install, gate, end to end run and
   product start goes through it. Slots are folders in one per-user directory (`~/.orion-gov`), so the cap holds
   across projects and terminals. `heavySlots` defaults to 1. One separate **product slot** for anything that binds
   fixed ports. Each slot folder holds a lease: holder PID, start time and a heartbeat that the holder refreshes
   every 60 s. Any caller reclaims a slot whose PID is dead, or whose heartbeat is older than 30 minutes, the same
   stale rule the merge slot uses in `in-flight.md`. A crashed or killed holder therefore blocks nobody for long.
   A start waits while available memory (measured per OS) is below `minFreeMemMB` (default 2048). The memory wait
   has a limit of `heavyTimeoutMin`; after that the start fails with a recorded reason. A timeout kills the whole
   process tree. A wait returns within 9 minutes with one status line and a short tail; the full log stays on disk. A
   product run checks its ports are free before and after, and never reuses a server it did not start. The gate's
   baseline runs once per commit. A sweep stops what a finished issue left running, from the project's new
   `Clean-up` row.
2. **Bounded waits and run state on disk.** A CI wait script returns one line per call. The merge-slot wait wakes
   on a file change instead of re-reading every minute. Run state goes to `state.json` at every step, with
   `/dev-next --resume <run id>`. `state.json` carries the orchestrator's PID, host and a heartbeat refreshed at
   every step. Resume takes over only when that PID is dead on this host, or the heartbeat is older than 30 minutes.
   Otherwise it refuses and names the live terminal, so two terminals never work the same issue. `/dev-next #<N>
   #<M>` stays a valid way to resume, and `SKILL.md` changes to list both. A short run-critical rules block moves into the first part of `SKILL.md`, which
   survives compaction. From the second fix round a fresh dev agent reads a handoff file instead of resuming a
   growing transcript. Every wait has a limit.
3. **QA before merge, one product at a time.** A fresh `qa-N` agent runs the story's checks after the final
   approval and green CI, before the merge slot, inside the product slot. A code fix that QA triggers gets a fresh
   review. A failed product start is split in two. An **environment failure** (slot timeout, port busy, out of
   memory) is recorded and does not block the merge. A **branch failure** (the product fails to start on the branch
   but starts on `main` in the same slot) blocks the merge and marks the issue `needs-human`. QA covers the branch
   as approved, before the merge slot re-merges `origin/main`. The re-merged result gets a fresh CI run but no
   second QA pass; `/harvest-qa` on `main` catches any gap that the re-merge adds. `/harvest-qa` keeps re-testing on
   `main` later and uses the same product slot.
4. **A hook that keeps sub-agents on the slots.** A `PreToolUse` hook on Bash denies, inside a sub-agent only, a
   command from `heavyCommands` that does not go through `gov.sh`. It detects a sub-agent from the `agent_id` field
   in the hook input, which is present only inside a sub-agent. It fails open on any error, and every fail-open or
   bypass is written to the audit's machine block, so a skipped slot is visible.

New optional keys in `.claude/orion/config.json`: `heavySlots` (default 1; no `auto` until the machine block has data to base it on), `heavyTimeoutMin` (45),
`minFreeMemMB` (2048),
`productPorts` (empty), `qa` (`pre-merge` or `off`), `heavyCommands` (empty).

## Consequences

- With one slot, a run of four issues takes longer in wall time but finishes. The audit gains a machine block
  (slot waits, timeouts, peak load, minimum free memory), so raising `heavySlots` becomes a measured decision.
- QA before merge changes the baseline's "QA, later and on main" rule. Each story gains one product start, and
  maybe one fix round.
- A second settings hook joins the `SessionStart` one. It does nothing until `heavyCommands` is filled in.
- Projects gain three rows in their commands table: which commands start the product, `Shared services` (a fixed
  name start and stop for things like a database container) and `Clean-up`.
- Process groups, tree kills and port checks differ per OS. Each gets its own mechanism (macOS has no `setsid`,
  Git Bash has no `lsof`), tested in both suite modes.

## Machine resources and QA cost

The owner's concern is that QA in the loop overloads the machine: full product starts, often with Docker, on
machines that already stall with three orchestrators of four sub-agents, and an 8 GB laptop that cannot run one.
This ADR does not argue that every machine should run QA before merge:

- `qa` is a setting. `off` keeps today's flow exactly: merge first, `/harvest-qa` later, tested by blast radius.
- With `qa: pre-merge` and the default `heavySlots: 1`, only one heavy job and one product run at a time, whatever
  the agent count. Agents queue for the slot instead of competing for memory, so 15 to 20 sub-agents stay possible.
- The memory floor stops a start before the machine swaps, so an 8 GB laptop queues instead of stalling.
- The slots are the same contract a future QA harness would use. Moving QA off developer machines later changes
  where the slot lives, not the workflow.

The proposal is to test this on an experiment branch before any default changes.

## Alternatives

- **Keep the cap at two issues and drop QA.** Works today, but still lets two full gates collide on ports, leaves
  containers running, and does not stop stalls.
- **Cap live agents with a hook.** Agents are cheap while they think. The load comes from what they run, so an
  agent cap throttles thinking as well and still lets two heavy gates collide.
- **One headless `claude -p` process per issue.** Clean context per issue, but the machine load is the same, and it
  needs a supervisor, separate login handling and a second way to pass results back.

## Open questions for the owner

1. What did the stripped version run as QA, where did it hang, and was the limit the machine or the Claude plan?
2. Accept QA before merge, or keep QA after merge and add only the product slot?
3. Is a second settings hook (`PreToolUse` on Bash, fails open) acceptable?
4. Slots per user (`~/.orion-gov`) or per worktree root?
