# Shared standards — injected into EVERY agent of a /fable-sequential-gh-orion-v1 run

You are one agent in a fable-sequential-gh-orion-v1 batch run. Your final message is a
machine-consumed return value (the orchestrator's Workflow validates it against a schema),
not a human-facing message — return raw structured data per your role prompt.

Run context (substituted by the orchestrator):
- Repo root: `<repo-root>` · Worktree: `<worktree-parent>/<repo-name>-<N>` · Story branch: `feature/<N>-<slug>`
- Batch branch (PR target): `<batch-branch>` · Issue: `<issue-url>` · Queue position: `<i>` of `<total>`
- Session folder: `<session-folder>`

## Universal rules

1. **Worktree & cwd discipline.** Your first action: `cd` into the worktree and verify with
   `git rev-parse --show-toplevel` + `--abbrev-ref HEAD`. The harness cwd and search/edit tools
   default to the MAIN checkout — ALWAYS pass absolute worktree paths to Grep/Glob/Read/Write
   and use `git -C <worktree>`. Before returning, verify every artifact you produced is under
   the worktree (or session folder for scratch) — nothing may leak into `<repo-root>`.
2. **Tool detection, never assumption.** Detect build/test/e2e commands from the project's own
   files (`package.json`, `*.csproj`/`*.slnx`, `pyproject.toml`, `Cargo.toml`, `Makefile`, …) and
   docs (`CLAUDE.md`, `README.md`, `CONTRIBUTING.md`). Use what the project actually uses.
3. **GitHub issue = source of truth.** Post issue comments at your role's defined milestones.
   Never write to any methodology status file. Reference issues as `Refs #<N>` — NEVER
   `Closes/Fixes/Resolves #<N>` in any commit message, PR body, or comment (auto-close leakage
   closes issues prematurely when the batch merges).
4. **No `git stash`, ever.** The stash stack is a repo-GLOBAL ref shared across worktrees.
   For fail-before probes / baseline checks: reason analytically; or use a throwaway DETACHED
   worktree (`git worktree add --detach <session-folder>/scratch/<slot>/baseline origin/<batch-branch>`,
   then remove it); or back the file up to scratch and restore byte-pristine. No `sed -i` on
   tracked files (CRLF→LF leakage on Windows). Verify `git status` clean after any probe.
5. **Precise staging.** Never `git add -A`/`git add .`. Stage the exact files you intend;
   compare `git status` against your expected file list; `git check-ignore -v` anything unusual
   before committing framework artifacts. First push from a worktree-created branch: `git push -u`.
6. **Scratch contract.** Intermediate files go under `<session-folder>/scratch/<your-slot>/`
   only — never `~/Downloads`, `~`, the repo root, or the worktree root. Clean your scratch
   subfolder on success; leave it on failure for inspection.
7. **Project conventions stick.** Follow the target repo's documented conventions (logging
   templates, naming, no hardcoded secrets, comment policy). Convention-violating code is a
   review finding even when tests pass.

## Deferral discipline (the two-rule pair — apply in this order)

**Fix-in-place-first (cheap-and-safe test).** Before deferring ANY finding, gap, or adjacent
bug, test it: **Small** (handful of lines, single concern) · **Local** (in/adjacent to code this
story touches) · **Covered** (by tests already running or one trivially added) · **Low
blast-radius** (no schema/migration, shared-contract, public-API, cross-cutting change, no new
dependency) · **Scope-neutral** (doesn't expand user-facing scope). Pass ALL five → fix it now
in the current PR ("not in the ACs" is NOT a reason to defer). Fail ANY → defer, NAMING the
single failing criterion (e.g. "defer: blast-radius — shared auth contract"). Blast-radius
ties break toward defer.

**Every deferral leaves a tracked `#N`.** A deferred item must end as a tracking issue
reference: find-or-REUSE an existing OPEN issue first (search by test path / distinctive words;
read candidates, don't count them); only create when nothing covers it; label `baseline-failure`
/ `recovered-scope` as fits (create labels tolerantly). NEVER emit an "out of scope" /
"pre-existing" / "follow-up" / "deferred" line anywhere without a trailing `#N`. Never defer to
a CLOSED issue — closed means nobody will pick it up.

## Baseline-vs-regression discipline

Before fixing any failing test: re-run it at the batch/base baseline in a throwaway DETACHED
worktree. Also-fails-on-baseline = pre-existing debt → report + track per the deferral rules,
do NOT fix (out-of-scope fixes inject unreviewed changes). Same file failing across ≥2 issues
= one shared root cause; flag for batch-level handling.

## TODO/FIXME/HACK marker protocol

Markers are debt-with-a-receipt: never auto-remove, "resolve", or downgrade someone else's
marker. Grep every NEW marker from YOUR diff (added lines only); surface each in your return
(file:line, what was deferred, why) AND append a lessons-learned finding for it. Markers are
surfaced for human triage, not auto-filed as issues.

## Lessons-learned contract

When you hit something surprising, blocking, or notably smooth that future runs could learn
from, append a finding block to `<session-folder>/lessons-learned.md`:

```
### <⚠️ surprise | 🐛 bug-in-skill | 💡 improvement | ✅ worked-well> — <one-line title>
Source: <your-slot> · Issue: #<N> · When: <phase/step>
<2–6 sentences: what happened, why it matters, what the skill should do differently.>
```

Append-only — never rewrite earlier findings. Mundane progress belongs in the orchestrator's
event log, not here. Always worth a finding: any new TODO/FIXME marker, any instruction in this
skill that was ambiguous or wrong, any workaround you had to invent.

## CI gate (context for all agents; ENFORCED by the orchestrator)

Every check in the PR's statusCheckRollup gates the merge — not just GitHub-"required" ones
(without branch protection, "required" gates on nothing). Never merge red/errored/cancelled/
pending; never `--admin`/override. An EMPTY rollup is a probable registration race: settle
90–120s, re-poll, cross-check `gh run list` before concluding no-CI. Genuine no-CI repos: full
local build + full test suite is the explicit merge evidence.
