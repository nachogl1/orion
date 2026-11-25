#!/usr/bin/env bash
# tests/run.sh - the full suite of the orion repo: syntax checks, then orion.sh driven end to end against
# throw-away projects. Everything runs in a sandbox (its own HOME, cache and temp folder), never touches
# the network (a fake `git` answers the update check) and leaves nothing behind. One check reads the local
# origin/main ref and release tags to check GLOBAL_CLAUDE.md's changed clauses: run `git fetch origin main` first (CI
# fetches both).
#
# usage: bash tests/run.sh             prints one line per check, exits 1 when any check fails
#        bash tests/run.sh --windows   only the part that differs on Windows (syntax and guide checks, round trip, every settings
#                                      editor including PowerShell), for the Windows CI job: Git Bash starts
#                                      processes so slowly that the whole suite takes minutes there; fails
#                                      where powershell.exe is missing
#
# Portable bash: runs under Git Bash, macOS bash and Linux. No GNU-only flags.

set -u

WINDOWS_ONLY=0
[ $# -le 1 ] || { echo "usage: bash tests/run.sh [--windows]" >&2; exit 2; }
case "${1:-}" in
    "") ;;
    --windows) WINDOWS_ONLY=1 ;;
    *) echo "usage: bash tests/run.sh [--windows]" >&2; exit 2 ;;
esac

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ORION="$REPO/orion.sh"
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }
summary() { echo "suite: $PASS passed, $FAIL failed"; [ "$FAIL" -eq 0 ]; }

if python3 -c 'import json' >/dev/null 2>&1; then PY=python3; else PY=python; fi
REAL_GIT="$(command -v git)"
SB="$(mktemp -d)"
trap 'rm -rf "$SB"' EXIT
mkdir -p "$SB/home" "$SB/bin"
export HOME="$SB/home" XDG_CACHE_HOME="$SB/cache"
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid

# The fake git: `ls-remote` answers $FAKE_LS_SHA when set, with a release tag v<N> for each number in $FAKE_LS_TAGS,
# `clone` fails when $FAKE_CLONE_FAIL=1 and hangs when $FAKE_CLONE_HANG=1; all else is real git. Every call is logged
# to $FAKE_GIT_LOG when set, one line of arguments each, so a check can prove it reached no network. The fake cp: the
# first copy sleeps $FAKE_CP_SLEEP seconds when set and leaves $SB/cp-slept behind, so a check can tell a copy ran.
cat > "$SB/bin/git" <<EOF
#!/usr/bin/env bash
[ -z "\${FAKE_GIT_LOG:-}" ] || printf '%s\n' "\$*" >> "\$FAKE_GIT_LOG"
if [ "\${1:-}" = ls-remote ] && [ -n "\${FAKE_LS_SHA:-}" ]; then
    printf '%s\t%s\n' "\$FAKE_LS_SHA" "\${3:-refs/heads/main}"
    for t in \${FAKE_LS_TAGS:-}; do printf '%s\trefs/tags/v%s\n' "\$FAKE_LS_SHA" "\$t"; done
    exit 0
fi
if [ "\${1:-}" = clone ] && [ "\${FAKE_CLONE_FAIL:-}" = 1 ]; then exit 1; fi
if [ "\${1:-}" = clone ] && [ "\${FAKE_CLONE_HANG:-}" = 1 ]; then sleep 60; exit 1; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$SB/bin/git"
REAL_CP="$(command -v cp)"
cat > "$SB/bin/cp" <<EOF
#!/usr/bin/env bash
if [ -n "\${FAKE_CP_SLEEP:-}" ] && [ ! -e "$SB/cp-slept" ]; then : > "$SB/cp-slept"; sleep "\$FAKE_CP_SLEEP"; fi
exec "$REAL_CP" "\$@"
EOF
chmod +x "$SB/bin/cp"
# The fake date: `date +%s` answers $FAKE_NOW when set, so a check can run days later without waiting for them.
REAL_DATE="$(command -v date)"
cat > "$SB/bin/date" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = +%s ] && [ -n "\${FAKE_NOW:-}" ]; then printf '%s\n' "\$FAKE_NOW"; exit 0; fi
exec "$REAL_DATE" "\$@"
EOF
chmod +x "$SB/bin/date"
# The fake npx: installing the status line warms a cost cache through npx, which would reach the network.
printf '#!/usr/bin/env bash\nexit 1\n' > "$SB/bin/npx"; chmod +x "$SB/bin/npx"
FAKEPATH="$SB/bin:$PATH"

N=0
newproj() { N=$((N+1)); mkdir -p "$SB/p$N"; P="$SB/p$N"; }               # sets P
init()    { bash "$ORION" init --project "$P" --yes --no-statusline --update-mode "${1:-ask}" >"$SB/out" 2>&1; }
# The timeout of every orion hook in a settings file, one per line; and setting them all (to the old 20 s by default).
hook_timeouts() { "$PY" -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8-sig")); [print(x.get("timeout")) for g in d.get("hooks", {}).get("SessionStart", []) for x in g.get("hooks", []) if "/.claude/orion/orion.sh" in x.get("command", "")]' "$1" 2>/dev/null | tr -d '\r'; }
set_old_hook_timeout() { "$PY" -c 'import json, sys; f = sys.argv[1]; d = json.load(open(f, encoding="utf-8-sig")); [x.update(timeout=json.loads(sys.argv[2])) for g in d["hooks"]["SessionStart"] for x in g["hooks"] if "/.claude/orion/orion.sh" in x.get("command", "")]; open(f, "w", encoding="utf-8").write(json.dumps(d, indent=2))' "$1" "${2:-20}"; }
json_ok() { "$PY" -c 'import json, sys; json.load(open(sys.argv[1], encoding="utf-8-sig"))' "$1" 2>/dev/null; }
# A hook's answer: nothing at all, or exactly one line of valid JSON.
hook_out_ok() {
    [ ! -s "$1" ] && return 0
    [ "$(wc -l < "$1" | tr -d ' ')" = 1 ] && "$PY" -c 'import json, sys; json.loads(open(sys.argv[1]).read())' "$1" 2>/dev/null
}
set_cfg() { sed "s|\"$1\": [^,}]*|\"$1\": $2|" "$P/.claude/orion/config.json" > "$SB/cfg" && mv "$SB/cfg" "$P/.claude/orion/config.json"; }
run_check() {  # extra env assignments go before the call: runs the INSTALLED copy, as the hook does
    mkdir -p "$SB/tmp"; rm -rf "$SB/tmp"/*
    env PATH="$FAKEPATH" TMPDIR="$SB/tmp" bash "$P/.claude/orion/orion.sh" check --project "$P" "$@" >"$SB/hook" 2>"$SB/hook-err"
}
consume_marker() { bash "$ORION" verify --project "$P" >/dev/null 2>&1 || true; }   # verify clears the one-shot marker
# For a check about something else in a git repository: orion's files stay out of its history, so the offer to ship
# orion files left uncommitted stays quiet.
keep_orion_out_of_git() { printf '/.claude/\n/CLAUDE.md\n' >> "$P/.git/info/exclude"; }
nothing_left_in_tmp() { [ -z "$(ls -A "$SB/tmp" 2>/dev/null)" ]; }
# A personal rules file whose ORION GLOBAL section has seen every clause, so the personal rules offer stays quiet
# in the checks that expect silence; the personal rules section below uses a HOME of its own.
seen_all_personal_rules() {  # home
    mkdir -p "$1/.claude"; printf '# ORION GLOBAL — v999999.0.0\n<!-- /ORION GLOBAL -->\n' > "$1/.claude/CLAUDE.md"
}
seen_all_personal_rules "$HOME"

echo "syntax"
check "orion.sh parses" bash -n "$ORION"
check "tests/run.sh parses" bash -n "$REPO/tests/run.sh"
check "tests/wsl.sh parses" bash -n "$REPO/tests/wsl.sh"
check "clear-git-resources scan.sh parses" bash -n "$REPO/skills/clear-git-resources/scripts/scan.sh"
check "issue_map.py compiles" "$PY" -m py_compile "$REPO/skills/issue-map/scripts/issue_map.py"
check "build_docx.py compiles" "$PY" -m py_compile "$REPO/skills/generate-project-writeup/assets/build_docx.py"
check "agent_tokens.py compiles" "$PY" -m py_compile "$REPO/skills/dev-next/scripts/agent_tokens.py"

echo "labels"
# The baseline promises that /dev-next's preflight creates every label of its Labels line; the skill's Labels row must list each one.
dev_next_creates_every_baseline_label() {
    local labels row l
    labels="$(awk '/^- Labels: /{on=1} on{print} on&&/plus the/{exit}' "$REPO/baselines/BASE_CLAUDE.md" | sed 's/plus the.*//' | grep -oE '`[a-z-]+`' | tr -d '`')"
    row="$(grep -E '^\| \*\*Labels\*\* \|' "$REPO/skills/dev-next/SKILL.md")"
    [ -n "$labels" ] && [ -n "$row" ] || return 1
    for l in $labels; do case "$row" in *"\`$l\`"*) ;; *) echo "  dev-next does not create: $l"; return 1 ;; esac; done
}
check "dev-next's preflight creates every label the baseline lists" dev_next_creates_every_baseline_label
# No label makes /dev-next stop at a green pull request for a person: the removed label for that never comes back
# (text files only: a compiled Python cache holds its checkout's path, which may carry the branch name).
check "no rule, skill, PRD or guide names the removed label that made a person merge a story" \
    eval '! grep -rIqiE "owner[- ]merges" "$REPO/skills" "$REPO/baselines" "$REPO/docs/PRDs" "$REPO/docs/guide"'

echo "dev-next sub-agents and the in-flight file"
# Every spawn in dev-next (and the roles dev-quick hands to it) names its sub-agent with the issue number, never a bare role-N:
# a reviewer or ready-check is always a new agent, so it may never appear as a bare role-N; a dev only on a spawn line or roles row.
dev_next_spawns_name_the_issue() {
    local files hits
    files=("$REPO"/skills/dev-next/SKILL.md "$REPO"/skills/dev-next/references/*.md "$REPO"/skills/dev-quick/SKILL.md)
    hits="$( { grep -nHiE 'spawn|^\| `(ready-check|dev|review)-' "${files[@]}" | grep -E '`(ready-check|dev|review)-N([`-]|$)'
              grep -nHE '`(ready-check|review)-N([`-]|$)' "${files[@]}"; } | sort -u)"
    [ -z "$hits" ] || { printf '  bare role-N: %s\n' "$hits"; return 1; }
    grep -qE '^Spawn `dev-<N>`' "$REPO/skills/dev-next/references/dev-agent.md" \
        && grep -qE 'Spawn `review-<N>-r<round>`' "$REPO/skills/dev-next/references/review-agent.md"
}
check "every dev-next spawn names its sub-agent with the issue number" dev_next_spawns_name_the_issue
# The Control Tower mod reads the in-flight file: in-flight.md's example shows every field its reader names, in its shape.
in_flight_shows_what_control_tower_reads() {
    local reader="$REPO/mods/control-tower/hooks/register.tsx" doc="$REPO/skills/dev-next/references/in-flight.md" fields f
    fields="$(awk '/^type InFlight(Entry)? = \{/{on=1} on{print} on&&/\}$/{on=0}' "$reader" | sed 's/^type [A-Za-z]* = //' \
        | grep -oE '[A-Za-z]+\??:' | tr -d '?:' | sort -u)"
    [ -n "$fields" ] || return 1
    for f in $fields; do grep -qF "\"$f\":" "$doc" || { echo "  in-flight.md does not show: $f"; return 1; }; done
    "$PY" - "$doc" <<'PY'
import json, re, sys
example = json.loads(re.search(r"```json\n(.*?)\n```", open(sys.argv[1], encoding="utf-8").read(), re.S).group(1))
entries = example["issues"]
assert any("terminal" in e and "step" in e and e.get("agents") for e in entries), "no entry shows terminal, step and agents"
for e in entries:
    assert isinstance(e.get("terminal", ""), str) and isinstance(e.get("step", ""), str)
    agents = e.get("agents", [])
    assert isinstance(agents, list), "agents is not a list"
    for a in agents:
        assert set(a) == {"name", "status"} and all(isinstance(v, str) for v in a.values()), a
PY
}
check "in-flight.md shows every field the Control Tower mod reads, in its shape" in_flight_shows_what_control_tower_reads
# A sub-agent the Agent tool reports no figure for (an agent-team teammate) is counted from its own transcript: every
# response once (one response may span several entries with one message id), input + output + cache-write, no cache
# reads; found by agent id or by the name its meta file describes, only since the run started, also under a config
# folder whose path holds brackets and in files that start with a byte-order mark; else null with a reason, and the
# script exits 0 every time, wrong arguments and a malformed transcript included.
agent_tokens_counts_the_transcript() {
    local script="$REPO/skills/dev-next/scripts/agent_tokens.py" root="$SB/agent[tokens]" sub out code args
    sub="$root/projects/example-project/example-session/subagents"
    mkdir -p "$sub" "$root/projects/example-project/other-session/subagents"
    # Git Bash leaves a path that holds brackets unconverted for a Windows Python: hand it a Windows path there.
    if command -v cygpath >/dev/null 2>&1; then root="$(cygpath -m "$root")" sub="$(cygpath -m "$sub")"; fi
    { printf '\357\273\277'; cat <<'EOF'
{"type":"assistant","message":{"id":"msg_2","usage":{"input_tokens":3,"output_tokens":40,"cache_read_input_tokens":9100}}}
{"type":"user","message":{"role":"user","content":"made-up brief"}}
{"type":"assistant","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":9000}}}
{"type":"assistant","message":{"id":"msg_1","usage":{"input_tokens":10,"output_tokens":5,"cache_creation_input_tokens":100,"cache_read_input_tokens":9000}}}
not json
{"type":"attachment","message":{"usage":{"input_tokens":999999}}}
EOF
    } > "$sub/agent-a1.jsonl"
    printf '\357\273\277{"description":"dev-31","toolUseId":"toolu_made_up"}\n' > "$sub/agent-a1.meta.json"
    printf '{"type":"user","message":{"role":"user","content":"no usage here"}}\n' > "$root/projects/example-project/other-session/subagents/agent-b2.jsonl"
    printf '{"type":"assistant","message":{"id":["made-up"],"usage":{"input_tokens":[1]}}}\n' > "$root/projects/example-project/other-session/subagents/agent-c3.jsonl"
    out="$("$PY" "$script" "$sub/agent-a1.jsonl")"
    [ "$out" = '{"tokens_total": 158, "tokens_source": "transcript"}' ] || { echo "  by path: $out"; return 1; }
    out="$("$PY" "$script" --root "$root" --agent a1)"
    [ "$out" = '{"tokens_total": 158, "tokens_source": "transcript"}' ] || { echo "  by id: $out"; return 1; }
    out="$("$PY" "$script" --root "$root" --name dev-31 --since 2000-01-01T00:00:00Z)"
    [ "$out" = '{"tokens_total": 158, "tokens_source": "transcript"}' ] || { echo "  by name: $out"; return 1; }
    for args in "--name dev-31 --since 2999-01-01T00:00:00Z" "--name review-31-r1" "--agent b2" "--agent c3" \
                "--bogus" "--name"; do
        # shellcheck disable=SC2086
        out="$("$PY" "$script" --root "$root" $args 2>/dev/null)"; code=$?
        [ "$code" = 0 ] || { echo "  $args: exit $code"; return 1; }
        case "$out" in '{"tokens_total": null, "tokens_source": "none", "tokens_reason": "'?*'"}') ;; *) echo "  $args: $out"; return 1 ;; esac
    done
}
check "a sub-agent with no tool-reported figure is counted from its own transcript, or null with a reason, always exit 0" agent_tokens_counts_the_transcript

echo "planning interview"
# /prd-to-tickets and /wayfinder follow one shared interview file beside new-issue.md; neither skill holds its rules itself.
planning_interview_is_shared() {
    local file="$REPO/skills/dev-next/references/planning-interview.md" s
    [ -f "$file" ] || { echo "  missing: skills/dev-next/references/planning-interview.md"; return 1; }
    for s in prd-to-tickets wayfinder; do
        grep -qF '.claude/skills/dev-next/references/planning-interview.md' "$REPO/skills/$s/SKILL.md" || { echo "  $s does not load it"; return 1; }
        grep -qF '.claude/skills/dev-next/references/planning-interview.md' "$REPO/skills/$s/VERIFY.md" || { echo "  $s's VERIFY.md does not check it"; return 1; }
        ! grep -qF 'Stop when a round produces no new question' "$REPO/skills/$s/SKILL.md" || { echo "  $s still holds the interview rules"; return 1; }
    done
}
check "prd-to-tickets and wayfinder both follow the one shared planning interview" planning_interview_is_shared

echo "prd-to-tickets"
PTT="$REPO/skills/prd-to-tickets/SKILL.md"
# One phase of prd-to-tickets' SKILL.md: from its "## Phase <n>" heading to the next "## " heading.
ptt_phase() { awk -v h="## Phase $1 " 'index($0, h) == 1 {on=1; print; next} on && /^## /{exit} on{print}' "$PTT"; }
# A split with several tiers chains them by blocks: every later-tier story waits for the final stories of the tier
# before, and a story added to a tier later is linked the same way (new-issue.md); no line says the tier orders nothing.
prd_split_chains_tiers() {
    local issue="$REPO/skills/dev-next/references/new-issue.md"
    ! grep -qF 'The tier never changes a blocker or a level' "$PTT" || { echo "  prd-to-tickets still says the tier changes no blocker"; return 1; }
    ! grep -qF 'nothing picks or orders work by it' "$issue" || { echo "  new-issue.md still says nothing orders work by tier"; return 1; }
    ptt_phase 3 | grep -qF 'final stories of the tier before' || { echo "  phase 3 does not block a later tier on the final stories of the tier before"; return 1; }
    ptt_phase 6 | grep -qF 'tier block' || { echo "  phase 6 does not file and read back the tier blocks"; return 1; }
    grep -qF 'final stories of the tier before' "$issue" && grep -qF 'added to a tier later' "$issue" \
        || { echo "  new-issue.md has no rule for a story added to a tier later"; return 1; }
}
check "prd-to-tickets chains the tiers by blocks, and new-issue.md links a story added to a tier later" prd_split_chains_tiers
# The UX prototype gates the cut: a missing screen gets a prototype pull request (with one PRD line pointing at the
# folder) and the run stops; no "UX prototype for <PRD>" story and no block on one; the guide box says the same.
prd_split_stops_at_missing_screens() {
    local p1 box brief="$REPO/skills/prd-to-tickets/references/ux-prototype.md"
    p1="$(ptt_phase 1)"
    printf '%s' "$p1" | grep -qF 'missing screens' || { echo "  phase 1 does not draft only the missing screens"; return 1; }
    printf '%s' "$p1" | grep -qF '**Then stop.**' || { echo "  phase 1 does not stop after the prototype pull request"; return 1; }
    ! grep -qF 'UX prototype for <PRD name>"' "$PTT" || { echo "  prd-to-tickets still files a prototype story"; return 1; }
    ! grep -qiE 'blocked by the prototype story|in parallel with the split' "$PTT" || { echo "  prd-to-tickets still blocks on a prototype story or drafts in parallel"; return 1; }
    grep -qF 'missing screens' "$brief" && grep -qF 'docs/PRDs/' "$brief" || { echo "  the prototype brief neither drafts only the missing screens nor adds the PRD line"; return 1; }
    box="$(awk '/^  tickets:\{/{on=1} on{print} on&&/^  [a-z]+:\{/&&!/tickets:/{exit}' "$REPO/docs/guide/index.html")"
    printf '%s' "$box" | grep -qF 'missing screens' && ! printf '%s' "$box" | grep -qF 'in parallel if' \
        || { echo "  the guide's /prd-to-tickets box does not say the split drafts the missing screens and stops"; return 1; }
}
check "prd-to-tickets stops after opening the prototype pull request when a screen is missing" prd_split_stops_at_missing_screens
check "prd-to-tickets reads the pending ADRs beside the PRD" eval 'ptt_phase 0 | grep -F "docs/ADRs/" | grep -qF "pending"'
# A skill's "## Who merges" section: from its heading to the next "## " heading.
who_merges_section() { awk '/^## Who merges/{on=1; next} on&&/^## /{exit} on{print}' "$1"; }
# Every pull request a skill opens merges on green or is named as one a person merges, by the baseline's own list:
# the skill's "Who merges" section quotes the baseline's rule word for word (a […] marks a cut) and names every path,
# label and skill it names.
quotes_baseline_who_merges() {
    local skill="$1" name rule section t
    name="$(basename "$(dirname "$skill")")"
    rule="$(awk '/^- \*\*Who merges\.\*\*/{on=1; print; next} on&&/^- /{exit} on{print}' "$REPO/baselines/BASE_CLAUDE.md")"
    section="$(who_merges_section "$skill")"
    [ -n "$rule" ] && [ -n "$section" ] || { echo "  no Who merges rule in the baseline, or no Who merges section in $name"; return 1; }
    for t in $(printf '%s' "$rule" | grep -oE '`[^`]+`' | tr -d '`' | sort -u); do
        case "$section" in *"\`$t\`"*) ;; *) echo "  $name's Who merges does not name: $t"; return 1 ;; esac
    done
    "$PY" - "$REPO/baselines/BASE_CLAUDE.md" "$skill" <<'PY'
import re, sys
flat = lambda t: " ".join(t.split())
base = open(sys.argv[1], encoding="utf-8").read()
rule = flat(re.search(r"^- \*\*Who merges\.\*\* (.*?)(?=^- )", base, re.S | re.M).group(1))
skill = open(sys.argv[2], encoding="utf-8").read()
section = re.search(r"^## Who merges\n(.*?)(?=^## )", skill, re.S | re.M).group(1)
quote = flat(" ".join(l[2:] for l in section.splitlines() if l.startswith("> ")))
if not quote:
    sys.exit("  Who merges quotes no baseline rule")
for piece in quote.split("[…]"):
    if flat(piece) not in rule:
        sys.exit("  the quote differs from the baseline here: " + flat(piece)[:80])
PY
}
prd_split_merges_by_the_baseline_list() {
    local section
    quotes_baseline_who_merges "$PTT" || return 1
    section="$(who_merges_section "$PTT")"
    printf '%s' "$section" | grep -qF 'ux-prototype-<slug>' && printf '%s' "$section" | grep -qF 'prd-update-<slug>' \
        || { echo "  Who merges does not place both pull requests the skill opens"; return 1; }
}
check "every pull request prd-to-tickets opens merges by the baseline's Who merges list" prd_split_merges_by_the_baseline_list

echo "wayfinder"
WF="$REPO/skills/wayfinder/SKILL.md"
# One section of wayfinder's SKILL.md: from the "## <title>" heading to the next "## " heading.
wf_section() { awk -v h="## $1" 'index($0, h) == 1 {on=1; print; next} on && /^## /{exit} on{print}' "$WF"; }
# The destination question offers two endings with no PRD and three once one exists: ADRs only, recommended when the
# map changes no scope, vocabulary or acceptance bar. The description, the words list and the map template follow.
wayfinder_offers_adrs_once_a_prd_exists() {
    local a
    a="$(wf_section 'Mode A')"
    printf '%s' "$a" | grep -qF 'two options' && printf '%s' "$a" | grep -qF 'three options' \
        || { echo "  Mode A does not offer two options with no PRD and three with one"; return 1; }
    printf '%s' "$a" | grep -qF '**ADRS**' && printf '%s' "$a" | grep -qF 'scope, vocabulary or acceptance bar' \
        || { echo "  Mode A does not offer ADRs only with its recommendation rule"; return 1; }
    ! grep -qF 'exactly two options' "$WF" || { echo "  wayfinder still offers exactly two destinations"; return 1; }
    grep -qF '**<PRD | ADRS | TICKETS>**' "$WF" || { echo "  the map template does not name ADRS"; return 1; }
    wf_section 'Words this skill uses' | grep -qF '**ADRS**' || { echo "  the words list does not define ADRS"; return 1; }
    grep -m1 '^description:' "$WF" | grep -qF 'ADRS' || { echo "  the description does not name ADRS"; return 1; }
}
check "wayfinder offers an ADRs-only destination only once a PRD exists" wayfinder_offers_adrs_once_a_prd_exists
# An ADRs-only map ends with each decision written as a pending ADR, in one pull request a person merges, and never
# asks the PRD question.
wayfinder_adrs_ending() {
    local s
    s="$(wf_section 'Writing the ADRs')"
    printf '%s' "$s" | grep -qF 'docs/ADRs/' && printf '%s' "$s" | grep -qF '**Status: pending**' \
        || { echo "  no ending writes each decision as a pending ADR under docs/ADRs/"; return 1; }
    printf '%s' "$s" | grep -qF 'one pull request' || { echo "  the ADRs do not ship in one pull request"; return 1; }
    wf_section 'The PRD question' | grep -qF 'An ADRS map never asks it' || { echo "  an ADRS map still asks the PRD question"; return 1; }
}
check "an ADRs-only map writes pending ADRs and skips the PRD question" wayfinder_adrs_ending
# A PRD map's ending names the order: the person writes the PRD, then /prd-to-tickets drafts any missing prototype
# screens (a pull request a person merges) before it cuts. A TICKETS map keeps its own prototype story (no PRD to gate).
wayfinder_prd_ending_names_the_order() {
    local s
    s="$(wf_section 'Ending a PRD map')"
    printf '%s' "$s" | grep -qF '/prd-to-tickets' && printf '%s' "$s" | grep -qF 'missing screens' \
        || { echo "  a PRD map's ending does not name the prototype step before the cut"; return 1; }
}
check "a PRD map's ending names the order: the PRD, then the missing prototype screens, then the cut" wayfinder_prd_ending_names_the_order
# Every pull request wayfinder opens merges by the baseline's list; nothing says a human merges them all.
wayfinder_merges_by_the_baseline_list() {
    quotes_baseline_who_merges "$WF" || return 1
    ! grep -qiE 'a pull request a \*\*human\*\* merges|never auto-merge|merged by a human\)' "$WF" \
        || { echo "  wayfinder still hands every pull request to a person"; return 1; }
}
check "every pull request wayfinder opens merges by the baseline's Who merges list" wayfinder_merges_by_the_baseline_list
wayfinder_guide_box_offers_adrs() {
    awk '/^  wayfinder:\{/{on=1} on{print} on&&/^  [a-z]+:\{/&&!/wayfinder:/{exit}' "$REPO/docs/guide/index.html" \
        | grep -qF 'ADRs only' || { echo "  the guide's /wayfinder box does not offer ADRs only"; return 1; }
}
check "the guide's /wayfinder box offers ADRs only" wayfinder_guide_box_offers_adrs

echo "reconcile"
RC="$REPO/skills/reconcile/SKILL.md"
# One section of reconcile's SKILL.md: from the "## <title>" heading to the next "## " heading.
rc_section() { awk -v h="## $1" 'index($0, h) == 1 {on=1; print; next} on && /^## /{exit} on{print}' "$RC"; }
# The pending ADRs are product truth beside the PRD: phase 0 reads them by their status line, and a story an ADR
# asks for is no longer "a story the PRD does not ask for".
reconcile_reads_pending_adrs() {
    rc_section 'Phase 0' | grep -F 'docs/ADRs/' | grep -qF '**Status: pending**' || { echo "  phase 0 does not read the pending ADRs by their status line"; return 1; }
    rc_section 'Phase 0' | grep -qF '**An unknown status line**' && ! rc_section 'Phase 0' | grep -qF 'any status line other than' \
        || { echo "  phase 0 still reads an ADR with an unknown status line as pending instead of asking"; return 1; }
    rc_section 'The four lenses' | grep -qF 'a story a pending ADR asks for is **not** a story the PRD does not ask for' \
        || { echo "  a story a pending ADR asks for is still reported as unasked-for"; return 1; }
    grep -qF 'docs/ADRs/' "$REPO/skills/reconcile/VERIFY.md" || { echo "  VERIFY.md does not cover the ADRs it reads"; return 1; }
}
check "reconcile reads the pending ADRs beside the PRD" reconcile_reads_pending_adrs
# Both new findings sit in the lens list, each with its plain-words explanation: a pending ADR not yet folded, and a
# later-tier story that is free while an earlier tier is still open (the tier chain of new-issue.md).
reconcile_lists_both_new_findings() {
    local l
    l="$(rc_section 'The four lenses')"
    printf '%s' "$l" | grep -qF '**every pending ADR not yet folded into the PRD**' \
        && printf '%s' "$l" | grep -qF '**A decision waiting to be folded into the PRD**' \
        || { echo "  the lens list has no pending-ADR finding with its explanation"; return 1; }
    printf '%s' "$l" | grep -qF '**a later-tier story that is free while a story of an earlier tier is still open**' \
        && printf '%s' "$l" | grep -qF '**A later-tier story that can be started too early**' \
        && printf '%s' "$l" | grep -qF 'final stories of the tier before it' \
        || { echo "  the lens list has no free later-tier finding with its explanation and the tier chain"; return 1; }
    [ "$(printf '%s' "$l" | grep -cF '*In plain words:*')" -ge 2 ] || { echo "  a new finding has no plain-words explanation"; return 1; }
}
check "reconcile lists the pending-ADR and the free later-tier findings, in plain words" reconcile_lists_both_new_findings
# Folding a pending ADR changes its status line in the same pull request, the docs(prd) one.
reconcile_fold_changes_the_status_line() {
    local p3
    p3="$(rc_section 'Phase 3')"
    printf '%s' "$p3" | grep -qF '**Fold into the PRD**' && printf '%s' "$p3" | grep -qF '**Status: folded into the PRD on <yyyy-mm-dd>**' \
        && printf '%s' "$p3" | grep -qF 'same pull request' || { echo "  phase 3 does not fold an ADR and change its status line in the same pull request"; return 1; }
    printf '%s' "$p3" | grep -qF 'the PRD changed or an ADR was folded' \
        || { echo "  a fold does not go in the docs(prd) pull request"; return 1; }
    printf '%s' "$p3" | grep -qF 'Any other status line an older ADR carries is **replaced**'         || { echo "  a fold does not replace an older ADR's other status line"; return 1; }
}
check "reconcile's fold changes the ADR's status line in the same pull request" reconcile_fold_changes_the_status_line
# An ADR's status line is one of three, spelled the same in the baseline and in every skill that reads ADRs; each
# reading skill stops and asks about an unknown line instead of guessing, and orion-verify changes one only on a yes.
adr_status_lines_agree() {
    local f line
    for f in baselines/BASE_CLAUDE.md skills/reconcile/SKILL.md skills/prd-to-tickets/SKILL.md \
             skills/wayfinder/SKILL.md skills/orion-verify/SKILL.md; do
        for line in '`**Status: pending**`' '`**Status: folded into the PRD on <yyyy-mm-dd>**`' \
                    '`**Status: replaced by <newer ADR> on <yyyy-mm-dd>**`'; do
            grep -qF "$line" "$REPO/$f" || { echo "  $f does not name the status line $line"; return 1; }
        done
    done
    for f in baselines/BASE_CLAUDE.md skills/reconcile/SKILL.md skills/prd-to-tickets/SKILL.md skills/wayfinder/SKILL.md; do
        tr '\n' ' ' <"$REPO/$f" | tr -s ' ' | grep -qF 'is never read as pending and never skipped silently' \
            || { echo "  $f does not say an unknown status line is never read as pending nor skipped"; return 1; }
    done
    for f in skills/reconcile/SKILL.md skills/prd-to-tickets/SKILL.md skills/wayfinder/SKILL.md; do
        tr '\n' ' ' <"$REPO/$f" | tr -s ' ' | grep -qF 'Stop at that ADR' \
            || tr '\n' ' ' <"$REPO/$f" | tr -s ' ' | grep -qF 'stop at that ADR' \
            || { echo "  $f does not stop at an ADR with an unknown status line and ask"; return 1; }
    done
    ! grep -qF 'is read as pending' "$RC" || { echo "  reconcile still reads an unknown status line as pending"; return 1; }
    tr '\n' ' ' <"$REPO/skills/orion-verify/SKILL.md" | tr -s ' ' | grep -qF "changes only on the person's yes" \
        || { echo "  orion-verify does not change an ADR's status line only on a yes"; return 1; }
}
check "the three ADR status lines read the same everywhere, and an unknown one is asked about" adr_status_lines_agree
# The run's bookmark-only pull request merges on green; the docs(prd) one is the person's, by the baseline's list.
reconcile_merges_by_the_baseline_list() {
    local section
    quotes_baseline_who_merges "$RC" || return 1
    section="$(who_merges_section "$RC")"
    printf '%s' "$section" | grep -F 'chore(reconcile)' | grep -qF 'on green' \
        && printf '%s' "$section" | grep -F 'docs(prd): reconcile' | grep -qF '**a person**' \
        || { echo "  Who merges does not place both kinds of pull request the skill opens"; return 1; }
    ! grep -qiE 'no merge autonomy|a pull request a human merges' "$RC" || { echo "  reconcile still hands every pull request to a person"; return 1; }
}
check "every pull request reconcile opens merges by the baseline's Who merges list" reconcile_merges_by_the_baseline_list
reconcile_guide_box_names_the_findings() {
    local box
    box="$(awk '/^  reconcile:\{/{on=1} on{print} on&&/^  [a-z]+:\{/&&!/reconcile:/{exit}' "$REPO/docs/guide/index.html")"
    printf '%s' "$box" | grep -qF 'pending ADR' && printf '%s' "$box" | grep -qF 'later-tier story' \
        && printf '%s' "$box" | grep -qF 'merges itself on green' \
        || { echo "  the guide's /reconcile box does not name the pending ADRs, the later-tier story and its merges"; return 1; }
}
check "the guide's /reconcile box names the pending ADRs, the later-tier finding and its merges" reconcile_guide_box_names_the_findings
issuemap_guide_box_names_the_options() {
    awk '/^  issuemap:\{/{on=1} on{print} on&&/^  [a-z]+:\{/&&!/issuemap:/{exit}' "$REPO/docs/guide/index.html" \
        | grep -F -- '--search' | grep -qF -- '--repo' \
        || { echo "  the guide's /issue-map box does not name --search and --repo"; return 1; }
}
check "the guide's /issue-map box names the search and repository options" issuemap_guide_box_names_the_options

echo "harvest"
HV="$REPO/skills/harvest/SKILL.md"
# One section of harvest's SKILL.md: from the "## <title>" heading to the next "## " heading.
hv_section() { awk -v h="## $1" 'index($0, h) == 1 {on=1; print; next} on && /^## /{exit} on{print}' "$HV"; }
# Every note is rated by the fixed tests; the agent may only lift one level; the report's severity is a hint only.
harvest_rates_by_fixed_tests() {
    local p1
    p1="$(hv_section 'Phase 1' | tr -s ' \n' ' ')"
    printf '%s' "$p1" | grep -qF 'a user would see it, or it broke or blocked a run, or three or more runs hit it' \
        && printf '%s' "$p1" | grep -qF 'it hit once, and an open story or a later user will meet it' \
        || { echo "  phase 1 does not rate high and medium by the fixed tests"; return 1; }
    printf '%s' "$p1" | grep -qF 'lift an item one level' && printf '%s' "$p1" | grep -qF 'severity is a hint only' \
        || { echo "  phase 1 does not allow a one-level lift and treat the report's severity as a hint"; return 1; }
    printf '%s' "$p1" | grep -qF "highest item's" || { echo "  a group does not take its highest item's rating"; return 1; }
}
check "harvest rates every note high, medium or low by fixed tests" harvest_rates_by_fixed_tests
# Each group is asked in three lines (the long explanation only on request): high groups, then medium, then how many
# tasks in all, then every low note in one closing question with three options. The waves are gone.
harvest_asks_by_importance() {
    local p2 hi tasks low o
    hv_section 'How to explain each item' | grep -qF '**The question: three lines.**' \
        && hv_section 'How to explain each item' | grep -qF '**The long explanation, only when the person asks**' \
        || { echo "  the explanation is not three lines with the long one on request"; return 1; }
    p2="$(hv_section 'Phase 2')"
    hi="$(printf '%s\n' "$p2" | grep -nF '**The high groups, then the medium groups' | cut -d: -f1)"
    tasks="$(printf '%s\n' "$p2" | grep -nF '**Then how many tasks in all**' | cut -d: -f1)"
    low="$(printf '%s\n' "$p2" | grep -nF '**Then every low note, in one question.**' | cut -d: -f1)"
    [ -n "$hi" ] && [ -n "$tasks" ] && [ -n "$low" ] && [ "$hi" -lt "$tasks" ] && [ "$tasks" -lt "$low" ] \
        || { echo "  phase 2 does not ask high and medium groups, then the task count, then the low notes"; return 1; }
    for o in 'fix it now' 'make it a task' 'add it to an existing task' 'throw it away' 'not this time' \
             'throw them all away' 'keep them all for later' 'go through them one by one'; do
        printf '%s' "$p2" | grep -qF "**$o**" || { echo "  phase 2 does not offer: $o"; return 1; }
    done
    ! grep -qiE 'wave [123]|three waves' "$HV" || { echo "  harvest still decides in waves"; return 1; }
}
check "harvest asks one three-line question per group, most important first, and the low notes last" harvest_asks_by_importance
# The harvest pull request merges on green unless it touches the baseline's list; nothing says a human merges it all.
harvest_merges_by_the_baseline_list() {
    quotes_baseline_who_merges "$HV" || return 1
    ! grep -qiE 'no merge autonomy' "$HV" || { echo "  harvest still hands every pull request to a person"; return 1; }
    hv_section 'Phase 3' | grep -qF '**Merge it as *Who merges* says.**' || { echo "  phase 3 does not merge as Who merges says"; return 1; }
}
check "the pull request harvest opens merges by the baseline's Who merges list" harvest_merges_by_the_baseline_list
harvest_guide_box_asks_by_importance() {
    local box
    box="$(awk '/^  harvest:\{/{on=1} on{print} on&&/^  [a-z]+:\{/&&!/harvest:/{exit}' "$REPO/docs/guide/index.html")"
    printf '%s' "$box" | grep -qF 'high, medium or low' && printf '%s' "$box" | grep -qF 'merges itself on green' \
        && ! printf '%s' "$box" | grep -qF 'three waves' \
        || { echo "  the guide's /harvest box does not rate high, medium or low, ask by importance and merge on green"; return 1; }
}
check "the guide's /harvest box rates notes and names its merges" harvest_guide_box_asks_by_importance

echo "harvest-qa"
HQ="$REPO/skills/harvest-qa/SKILL.md"
# The log pull request merges on green by the baseline's list; nothing says a human merges it.
harvest_qa_merges_by_the_baseline_list() {
    quotes_baseline_who_merges "$HQ" || return 1
    ! grep -qiE 'a human merges it|never merges on its own' "$HQ" || { echo "  harvest-qa still hands its log pull request to a person"; return 1; }
    awk '/^## Phase 3/{on=1; next} on&&/^## /{exit} on{print}' "$HQ" | grep -qF '**Merge it as *Who merges* says.**' \
        || { echo "  phase 3 does not merge as Who merges says"; return 1; }
}
check "the log pull request harvest-qa opens merges by the baseline's Who merges list" harvest_qa_merges_by_the_baseline_list
harvest_qa_guide_box_merges_on_green() {
    local box
    box="$(awk '/^  harvestqa:\{/{on=1} on{print} on&&/^  [a-z]+:\{/&&!/harvestqa:/{exit}' "$REPO/docs/guide/index.html")"
    printf '%s' "$box" | grep -qF 'merges itself on green' && ! printf '%s' "$box" | grep -qF 'Merge its log pull request' \
        || { echo "  the guide's /harvest-qa box does not say its log pull request merges itself on green"; return 1; }
}
check "the guide's /harvest-qa box says its log pull request merges on green" harvest_qa_guide_box_merges_on_green
# Run ids order by their time part, then the whole id: the <repo> prefix may differ between runs, so a text
# comparison would put an old run after a new one. Every skill that orders them says so in its own words.
run_ids_order_by_time_part() {
    local f flat
    for f in "$REPO/skills/dev-next/SKILL.md" "$HV" "$HQ"; do
        flat="$(tr -s ' \n' ' ' < "$f")"
        printf '%s' "$flat" | grep -qF '`yyyymmdd-hhmmss` part' && printf '%s' "$flat" | grep -qF 'may differ between runs' \
            || { echo "  ${f#"$REPO"/} does not order run ids by their time part or say the prefix may differ"; return 1; }
        ! printf '%s' "$flat" | grep -qiE 'run ids sort by time|run id sorts after' \
            || { echo "  ${f#"$REPO"/} still orders run ids as text"; return 1; }
    done
    for f in "$HV" "$HQ"; do
        tr -s ' \n' ' ' < "$f" | grep -qF 'the newest run id seen this run, by the time-part rule' \
            || { echo "  ${f#"$REPO"/} does not write its bookmark by the time-part rule"; return 1; }
    done
}
check "dev-next, harvest and harvest-qa order run ids by their time part, never as text" run_ids_order_by_time_part

echo "generate-project-writeup"
WU="$REPO/skills/generate-project-writeup/SKILL.md"
# One step of the write-up's SKILL.md: from the "### Step <N>" heading to the next "### " heading.
wu_step() { awk -v h="### Step $1 " 'index($0, h) == 1 {on=1; print; next} on && /^### /{exit} on{print}' "$WU"; }
# A one-page Executive Summary sits between the cover and the table of contents, drawn with the generator's own blocks,
# and its table repeats Table 1's rows.
writeup_summary_before_contents() {
    local s6 cover summary toc item b
    s6="$(wu_step 6)"
    cover="$(printf '%s\n' "$s6" | grep -nE '^1\. \*\*Title block\*\*' | cut -d: -f1)"
    summary="$(printf '%s\n' "$s6" | grep -nE '^2\. \*\*Executive Summary\*\*' | cut -d: -f1)"
    toc="$(printf '%s\n' "$s6" | grep -nE '^3\. \*\*Table of contents\*\*' | cut -d: -f1)"
    [ -n "$cover" ] && [ -n "$summary" ] && [ -n "$toc" ] && [ "$cover" -lt "$summary" ] && [ "$summary" -lt "$toc" ] \
        || { echo "  step 6 does not put the Executive Summary between the title block and the table of contents"; return 1; }
    item="$(printf '%s\n' "$s6" | sed -n "${summary},$((toc - 1))p" | tr -s ' \n' ' ')"
    for b in heading paragraph table page_break; do
        printf '%s' "$item" | grep -qF "\`$b\`" || { echo "  the Executive Summary does not name the $b block"; return 1; }
    done
    printf '%s' "$item" | grep -qF 'one page' && printf '%s' "$item" | grep -qF 'same headers and rows as Table 1' \
        || { echo "  the Executive Summary is not one page repeating Table 1's rows"; return 1; }
}
check "the write-up puts a one-page Executive Summary between the cover and the contents" writeup_summary_before_contents
# Step 8 checks the rendered file for that order and that table, and the chat report names both.
writeup_checks_its_summary() {
    local s8
    s8="$(wu_step 8 | tr -s ' \n' ' ')"
    printf '%s' "$s8" | grep -qF '**Check the Executive Summary (always).**' \
        && printf '%s' "$s8" | grep -qF 'before the table of contents' && printf '%s' "$s8" | grep -qF 'matches Table 1' \
        || { echo "  step 8 does not check the summary's place and its table"; return 1; }
    printf '%s' "$s8" | grep -qF 'cover, Executive Summary, contents' \
        || { echo "  step 8's report does not name the first pages"; return 1; }
}
check "the write-up checks that its summary comes before the contents and matches Table 1" writeup_checks_its_summary

echo "guide page (docs/guide/, published to GitHub Pages)"
GUIDE="$REPO/docs/guide/index.html"
# Every skill has a box on the guide (its title reads "/<name>"), so a new skill cannot ship without one.
guide_names_every_skill() {
    [ -f "$GUIDE" ] || return 1
    local d; for d in "$REPO"/skills/*/; do grep -qF "\"/$(basename "$d")\"" "$GUIDE" || return 1; done
}
check "the guide names every skill" guide_names_every_skill
check "the guide loads no script or stylesheet from elsewhere" eval '[ -f "$GUIDE" ] && ! grep -qiE "<script[^>]*src=|<link[^>]*stylesheet|@import|src=.?https?:|url\(.?https?:|fetch\(" "$GUIDE"'
# The guide and the README explain three choices: why harvest and QA run apart from each pull request, what the
# status line offers and what the personal rules offer.
guide_and_readme_explain_the_choices() {
    local f; for f in "$GUIDE" "$REPO/README.md"; do
        grep -qF 'one long batch session' "$f" && grep -qF 'about 30 minutes on every pull request' "$f" \
            && grep -qF 'unstaged' "$f" && grep -qF 'Risk (open):' "$f" \
            || { echo "  $(basename "$f") does not explain the batch harvest, the status line and the personal rules"; return 1; }
    done
}
check "the guide and the README explain why harvest and QA run apart, the status line and the personal rules" guide_and_readme_explain_the_choices
# The guide's footer credits the owner; Distribution safety allows that name there and nowhere else, so the name is
# read from the footer, never written in this file.
guide_footer_credits_the_owner_alone() {
    local footer name
    footer="$(awk '/<footer class="foot">/{on=1} on{print} /<\/footer>/{exit}' "$GUIDE")"
    name="$(printf '%s' "$footer" | sed -n 's/.*Made by \([^<]*\)<.*/\1/p' | head -1)"
    [ -n "$name" ] || { echo "  the guide's footer has no 'Made by' credit"; return 1; }
    [ "$(grep -rlF --exclude-dir=.git "$name" "$REPO" | grep -cv '/docs/guide/index.html$')" = 0 ] \
        || { echo "  the owner's name appears outside the guide's footer"; return 1; }
    [ "$(grep -cF "$name" "$GUIDE")" = 1 ] || { echo "  the owner's name appears more than once on the guide"; return 1; }
    grep -qF 'Made by <owner' "$REPO/CLAUDE.md" || { echo "  Distribution safety does not allow the footer credit"; return 1; }
}
check "the guide's footer credits the owner, the one place the name appears" guide_footer_credits_the_owner_alone
check "the README shows the guide's graph and links the page" eval '[ -f "$REPO/docs/guide/orion-workflow.svg" ] && grep -qF "docs/guide/orion-workflow.svg" "$REPO/README.md" && grep -qF "github.io/orion" "$REPO/README.md"'

echo "round trip (init / update / check / uninstall)"
newproj
check "init" init ask
check "update --force" eval 'bash "$ORION" update --project "$P" --force >"$SB/out" 2>&1'
check "check --force exits 0" run_check --force
check "check answers nothing or one JSON line" hook_out_ok "$SB/hook"
check "uninstall --yes" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1'
check "nothing orion owns is left" eval '[ ! -e "$P/.claude/orion" ] && [ ! -e "$P/.claude/skills" ] && ! grep -qi orion "$P/CLAUDE.md" "$P/.claude/settings.json"'

echo "init's agent-autonomy notice (--yes, and a shell with no terminal)"
# Whoever installs orion is told up front that its agents claim issues, file tickets and merge their own work.
NOTICE='merge their own pull requests'
DISCLAIMER='orion is an experimental framework'
newproj
check "init --yes shows the experimental disclaimer and the notice and asks nothing" eval 'init ask && grep -qF "$DISCLAIMER" "$SB/out" && grep -qF "$NOTICE" "$SB/out" && ! grep -qF "[y/N]" "$SB/out" && [ -f "$P/.claude/orion/VERSION" ]'
newproj
check "init without --yes in a shell with no terminal refuses, exit 1, and installs nothing" eval '! bash "$ORION" init --project "$P" --no-statusline --update-mode ask >"$SB/out" 2>&1 </dev/null && grep -q "refusing to init without --yes" "$SB/out" && grep -qF "$NOTICE" "$SB/out" && [ -z "$(ls -A "$P")" ]'
# The Windows launcher hands --yes through to orion.sh, so an unattended install from PowerShell works the same way.
if command -v powershell.exe >/dev/null 2>&1; then
    newproj
    check "orion.ps1 init --yes installs with no question" eval 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$REPO/orion.ps1" init --project "$P" --yes --no-statusline --update-mode ask >"$SB/out" 2>&1 </dev/null && grep -qF "$NOTICE" "$SB/out" && [ -f "$P/.claude/orion/VERSION" ]'
    newproj
    check "orion.ps1 init without --yes and no terminal refuses and installs nothing" eval '! powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$REPO/orion.ps1" init --project "$P" --no-statusline --update-mode ask >"$SB/out" 2>&1 </dev/null && grep -q "refusing to init without --yes" "$SB/out" && [ -z "$(ls -A "$P")" ]'
fi

# Every settings editor (jq, python, and PowerShell where it exists) on a settings file that has a
# byte-order mark, a permission rule naming orion's script, and a hook of the project's own; and a
# CLAUDE.md that holds nothing but orion's import line.
IMPORT='Mandatory rules, owned and refreshed by orion (never edit the copy): @.claude/orion/BASE_CLAUDE.md'
tools="$PY"; command -v jq >/dev/null 2>&1 && tools="jq $tools"; command -v powershell.exe >/dev/null 2>&1 && tools="$tools powershell"
[ "$WINDOWS_ONLY" = 1 ] && check "the Windows run has PowerShell to test" eval 'command -v powershell.exe >/dev/null 2>&1'
# Installing Control Tower binds Ctrl+X then P in the person's own keybindings file, through the same editors: a
# computer of its own per editor and a stub `claude` first on the path, so the real plugin command is never run.
mkdir -p "$SB/keys-bin"; printf '#!/usr/bin/env bash\nexit 0\n' > "$SB/keys-bin/claude"; chmod +x "$SB/keys-bin/claude"
KEY_CHORD='ctrl+x p' KEY_ACTION='command:control-tower'
keys_cmd() { HOME="$KBH" PATH="$SB/keys-bin:$FAKEPATH" bash "$P/.claude/orion/orion.sh" mod "$@" control-tower --project "$P" >"$SB/out" 2>&1; }
# How many times a keybindings file binds a key to an action, in any context.
keys_count() {  # file key action
    "$PY" -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8-sig")); print(sum(1 for c in d.get("bindings", []) for k, v in (c.get("bindings") or {}).items() if k == sys.argv[2] and v == sys.argv[3]))' "$@" 2>/dev/null | tr -d '\r'
}
keys_own() {  # file: the person's own bindings, every one in its own context
    [ "$(keys_count "$1" ctrl+e chat:externalEditor)" = 1 ] && [ "$(keys_count "$1" ctrl+k app:toggleTodos)" = 1 ] \
        && "$PY" -c 'import json, sys; d = json.load(open(sys.argv[1], encoding="utf-8-sig")); c = [b["context"] for b in d["bindings"]]; assert c == ["Chat", "Global"], c; assert d["bindings"][0]["bindings"]["ctrl+s"] is None' "$1" 2>/dev/null
}
keybinding_cases() {
    KBH="$SB/home-keys-$tool"; KF="$KBH/.claude/keybindings.json"; mkdir -p "$KBH"
    check "mod install with no keybindings file creates it with Ctrl+X then P" eval 'keys_cmd install && json_ok "$KF" && [ "$(keys_count "$KF" "$KEY_CHORD" "$KEY_ACTION")" = 1 ] && grep -qF "Ctrl+X then P" "$SB/out"'
    rm -rf "$KBH/.claude/orion-mods/control-tower"
    check "a second install binds it once, not twice" eval 'keys_cmd install && [ "$(keys_count "$KF" "$KEY_CHORD" "$KEY_ACTION")" = 1 ] && [ "$(grep -o "\"$KEY_CHORD\"" "$KF" | wc -l | tr -d " ")" = 1 ]'
    check "mod remove takes the binding away, and the file orion made with it" eval 'keys_cmd remove && [ ! -e "$KF" ]'
    printf '\357\273\277{"bindings":[{"context":"Chat","bindings":{"ctrl+e":"chat:externalEditor","ctrl+s":null}},{"context":"Global","bindings":{"ctrl+k":"app:toggleTodos"}}]}\n' > "$KF"
    check "mod install on a file with a BOM and bindings of its own adds it and keeps every one" eval 'keys_cmd install && json_ok "$KF" && [ "$(keys_count "$KF" "$KEY_CHORD" "$KEY_ACTION")" = 1 ] && keys_own "$KF"'
    check "mod remove takes away only that binding" eval 'keys_cmd remove && [ "$(keys_count "$KF" "$KEY_CHORD" "$KEY_ACTION")" = 0 ] && keys_own "$KF"'
    printf '\357\273\277{"bindings":[{"context":"Chat","bindings":{"ctrl+x p":"chat:modelPicker"}}]}\n' > "$KF"; cp "$KF" "$SB/keys-before"
    check "a chord taken by another binding: install keeps the file byte for byte and says so in one line" eval 'keys_cmd install && cmp -s "$SB/keys-before" "$KF" && [ "$(grep -c "chat:modelPicker" "$SB/out")" = 1 ] && grep "chat:modelPicker" "$SB/out" | grep -qF "$KEY_ACTION" && [ -d "$KBH/.claude/orion-mods/control-tower" ]'
    check "and mod remove leaves that binding alone" eval 'keys_cmd remove && cmp -s "$SB/keys-before" "$KF"'
    check "every editor gives the same answer on a malformed file: left byte for byte with one warning, or bound where the shape allows it" keys_malformed
}
# Each shape, then what every editor must do with it: "bad" leaves the file byte for byte and warns in one line,
# "added" binds the key; never a traceback or an error of the editor's own shown to the person.
KEY_SHAPES='bad	not json
bad	[]
bad	{"bindings":{}}
bad	{"bindings":""}
bad	{"bindings":0}
bad	{"bindings":false}
bad	{"bindings":[{"context":"Global","bindings":["keep-me"]}]}
added	{"bindings":null}
added	{"bindings":[{"context":"Global","bindings":null}]}'
keys_malformed() {
    local want shape
    while IFS="$(printf '\t')" read -r want shape; do
        printf '%s\n' "$shape" > "$KF"; cp "$KF" "$SB/keys-before"; rm -rf "$KBH/.claude/orion-mods/control-tower"
        keys_cmd install || { echo "  install failed on: $shape"; return 1; }
        ! grep -qiE "traceback|error|exception" "$SB/out" || { echo "  editor error shown on: $shape"; sed 's/^/    /' "$SB/out"; return 1; }
        case "$want" in
            bad) { cmp -s "$SB/keys-before" "$KF" && [ "$(grep -c "could not be read as a keybindings file" "$SB/out")" = 1 ]; } \
                    || { echo "  not left alone with one warning: $shape"; return 1; } ;;
            added) { json_ok "$KF" && [ "$(keys_count "$KF" "$KEY_CHORD" "$KEY_ACTION")" = 1 ]; } \
                    || { echo "  not bound: $shape"; return 1; } ;;
        esac
    done <<< "$KEY_SHAPES"
}
for tool in $tools; do
    echo "settings edits with $tool"
    newproj; mkdir -p "$P/.claude"
    printf '\357\273\277{"permissions":{"allow":["Bash(bash ${CLAUDE_PROJECT_DIR}/.claude/orion/orion.sh status)"]},"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"echo own"}]}]}}\n' > "$P/.claude/settings.json"
    printf '%s\n' "$IMPORT" > "$P/CLAUDE.md"
    export ORION_JSON_TOOL="$tool"
    check "init with a BOM in settings.json" init ask
    check "the hook is added although a permission rule names the script" eval 'grep -cF "orion.sh\\\" check" "$P/.claude/settings.json" | grep -qx 1'
    check "the new hook gets the 60 s time limit" eval '[ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'
    set_old_hook_timeout "$P/.claude/settings.json"
    check "an update with nothing to do still raises an older 20 s hook to 60 s" eval 'bash "$ORION" update --project "$P" >"$SB/out" 2>&1 && grep -q "nothing to do" "$SB/out" && grep -q "time limit raised to 60 s" "$SB/out" && [ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'
    set_old_hook_timeout "$P/.claude/settings.json"
    check "update --force raises an older 20 s hook to 60 s" eval 'bash "$ORION" update --project "$P" --force >"$SB/out" 2>&1 && grep -q "time limit raised to 60 s" "$SB/out" && [ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'
    set_old_hook_timeout "$P/.claude/settings.json" '"20"'
    check "a timeout that is not a number is left alone" eval 'bash "$ORION" update --project "$P" >"$SB/out" 2>&1 && ! grep -q "time limit raised" "$SB/out" && grep -q '"'"'"timeout": *"20"'"'"' "$P/.claude/settings.json"'
    set_old_hook_timeout "$P/.claude/settings.json" 60
    check "and keeps the rest of settings.json" eval 'json_ok "$P/.claude/settings.json" && grep -qF "echo own" "$P/.claude/settings.json" && grep -qF "orion.sh status" "$P/.claude/settings.json"'
    check "status sees the hook" eval 'bash "$ORION" status --project "$P" | grep -q "update check installed"'
    check "verify passes" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1'
    init ask; check "a second init adds no second hook" eval 'grep -cF "orion.sh\\\" check" "$P/.claude/settings.json" | grep -qx 1'
    keybinding_cases
    check "uninstall with a CLAUDE.md of only the import line" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1'
    check "uninstall removed the hook and kept the rest" eval '! grep -qF "orion.sh\\\" check" "$P/.claude/settings.json" && grep -qF "echo own" "$P/.claude/settings.json" && grep -qF "orion.sh status" "$P/.claude/settings.json" && json_ok "$P/.claude/settings.json"'
    check "uninstall removed the import line" eval '[ -f "$P/CLAUDE.md" ] && ! grep -qF "$IMPORT" "$P/CLAUDE.md" && [ ! -e "$P/.claude/orion" ]'
    unset ORION_JSON_TOOL
done
if [ "$WINDOWS_ONLY" = 1 ]; then summary; exit; fi

echo "tests/wsl.sh (the suite's launcher on a Windows computer)"
# A stand-in wsl.exe whose distro answers wslpath and has nothing else, as Docker Desktop's own distro does, and a
# copy of tests/wsl.sh in a throw-away repository, so the state of the real checkout plays no part.
wsl_without_bash_cannot_start() {
    local r="$SB/wslrepo"
    mkdir -p "$r/tests" "$SB/wslbin"; cp "$REPO/tests/wsl.sh" "$r/tests/wsl.sh"
    "$REAL_GIT" -C "$r" init -q -b main && "$REAL_GIT" -C "$r" -c core.autocrlf=false add . && "$REAL_GIT" -C "$r" commit -qm init || return 1
    printf '%s\n' '#!/usr/bin/env bash' 'case "$*" in *wslpath*) echo /mnt/c/repo; exit 0 ;; esac' 'exit 127' > "$SB/wslbin/wsl.exe"
    printf '%s\n' '#!/usr/bin/env bash' 'echo C:/repo' > "$SB/wslbin/cygpath"
    chmod +x "$SB/wslbin/wsl.exe" "$SB/wslbin/cygpath"
    env PATH="$SB/wslbin:$PATH" bash "$r/tests/wsl.sh" >"$SB/out" 2>&1
    [ $? = 2 ] && grep -q "could not start" "$SB/out" && grep -q "bash" "$SB/out" && ! grep -q "FAILED" "$SB/out" \
        || { sed 's/^/  /' "$SB/out"; return 1; }
}
check "a WSL distro without bash: the suite could not start, never a failed suite" wsl_without_bash_cannot_start

echo "init's agent-autonomy notice at a terminal"
# Runs orion.sh in a pseudo-terminal (a terminal made by the test), as a person typing $1 at its question; prints what
# the terminal showed and exits with orion's code, or 124 after 60 s, so a question nobody answers never hangs the suite.
at_terminal() {  # answer orion-arguments...
    "$PY" -c '
import os, pty, select, signal, sys, time
answer, args = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp("bash", ["bash"] + args)
os.write(fd, (answer + "\n").encode())
out, deadline = b"", time.time() + 60
while True:
    left = deadline - time.time()
    if left <= 0:
        os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); sys.stdout.write(out.decode(errors="replace")); sys.exit(124)
    if not select.select([fd], [], [], left)[0]: continue
    try: chunk = os.read(fd, 4096)
    except OSError: break
    if not chunk: break
    out += chunk
sys.stdout.write(out.decode(errors="replace"))
sys.exit(os.waitstatus_to_exitcode(os.waitpid(pid, 0)[1]))
' "$@"
}
# Python on Windows has no pty module, and nothing else there lets a script type at a terminal (Git Bash's winpty
# refuses a piped stdin), so under Git Bash these four checks cannot run at all: Linux, macOS and CI run them.
if "$PY" -c 'import pty' >/dev/null 2>&1; then
    newproj
    check "an interactive init shows the notice and asks to continue" eval 'at_terminal n "$ORION" init --project "$P" --no-statusline --update-mode ask >"$SB/out" 2>&1; grep -qF "$NOTICE" "$SB/out" && grep -qF "[y/N]" "$SB/out"'
    check "a no at that question installs nothing" eval '[ -z "$(ls -A "$P")" ] && grep -q "aborted" "$SB/out"'
    newproj
    check "a yes at that question installs orion" eval 'at_terminal y "$ORION" init --project "$P" --no-statusline --no-mods --update-mode ask >"$SB/out" 2>&1 && [ -f "$P/.claude/orion/VERSION" ] && [ -f "$P/CLAUDE.md" ]'
    newproj
    check "it then asks about each mod, and a no installs none on this computer" eval 'at_terminal "$(printf "y\nn")" "$ORION" init --project "$P" --no-statusline --update-mode ask >"$SB/out" 2>&1 && grep -qF "Also install the orion mod control-tower" "$SB/out" && [ -f "$P/.claude/orion/VERSION" ] && [ ! -e "$HOME/.claude/orion-mods" ]'
else
    echo "  note  not run here: these four checks need a pseudo-terminal, which this computer's Python cannot make; Linux, macOS and CI run them"
fi

echo "a renamed skill (update swaps orion's old copy, never a project's own folder)"
# An install from before the drift check was renamed: its managed copy still carries the old folder name.
newproj; init ask
mv "$P/.claude/skills/reconcile" "$P/.claude/skills/reconcile-issue-map"
check "an install carrying the old managed folder has the new one and not the old after update" eval 'bash "$ORION" update --project "$P" --force >"$SB/out" 2>&1 && [ -f "$P/.claude/skills/reconcile/SKILL.md" ] && [ ! -e "$P/.claude/skills/reconcile-issue-map" ]'
newproj; init ask
mkdir -p "$P/.claude/skills/reconcile-issue-map"; printf 'own skill\n' > "$P/.claude/skills/reconcile-issue-map/SKILL.md"
check "a project's own folder with the old name is left alone by update" eval 'bash "$ORION" update --project "$P" --force >"$SB/out" 2>&1 && [ "$(cat "$P/.claude/skills/reconcile-issue-map/SKILL.md")" = "own skill" ] && [ ! -e "$P/.claude/skills/reconcile-issue-map/.orion-managed" ]'

echo "issue map (the generator against fixture issues: a fake gh, no network)"
# Epic #1 holds #2 and #3; #2 -> #3 -> #4 is a chain three levels deep, and #3 is assigned while #2 is still open;
# #4's body section names a blocker GitHub's relation does not, and #6 has a native blocker but no section; #5 is
# blocked by the epic, by an issue that does not exist and by itself; #6 and #7 block each other.
MAPREPO="$SB/maprepo"; mkdir -p "$MAPREPO" "$SB/ghbin"; "$REAL_GIT" init -q "$MAPREPO"
cat > "$SB/issues.json" <<'EOF'
[{"number":1,"title":"Epic one","state":"OPEN","labels":[{"name":"epic","color":"8250df"}],"assignees":[],"author":{"login":"lead-1"},"body":"","url":"https://example.invalid/1"},
 {"number":2,"title":"Lay the base","state":"OPEN","labels":[{"name":"agent-ready","color":"0e8a16"},{"name":"story","color":"cccccc"}],"assignees":[{"login":"dev-1"}],"author":{"login":"lead-1"},"body":"### Blocked by\n(none)\n","url":"https://example.invalid/2"},
 {"number":3,"title":"Build on it","state":"OPEN","labels":[{"name":"agent-ready","color":"0e8a16"}],"assignees":[{"login":"dev-2"}],"author":{"login":" dev-2 "},"body":"### Blocked by\n#2 — Lay the base\n","url":"https://example.invalid/3"},
 {"number":4,"title":"Decide the next step","state":"OPEN","labels":[{"name":"needs-human","color":"d93f0b"}],"assignees":[],"author":{"login":""},"body":"### Blocked by\n#3 — Build on it\n","url":"https://example.invalid/4"},
 {"number":5,"title":"Odd links","state":"OPEN","labels":[],"assignees":[],"author":{"login":"ghost"},"body":"### Blocked by\n#1\n#5\n#99\n","url":"https://example.invalid/5"},
 {"number":6,"title":"Loop a","state":"OPEN","labels":[],"assignees":[],"author":null,"body":"","url":"https://example.invalid/6"},
 {"number":7,"title":"Loop b","state":"CLOSED","labels":[],"assignees":[],"body":"","url":"https://example.invalid/7"}]
EOF
cat > "$SB/links.json" <<'EOF'
{"data":{"repository":{
 "i0":{"number":1,"parent":null,"blockedBy":{"nodes":[]},"subIssues":{"nodes":[{"number":2},{"number":3}]}},
 "i1":{"number":2,"parent":{"number":1},"blockedBy":{"nodes":[]},"subIssues":{"nodes":[]}},
 "i2":{"number":3,"parent":{"number":1},"blockedBy":{"nodes":[{"number":2}]},"subIssues":{"nodes":[]}},
 "i3":{"number":4,"parent":null,"blockedBy":{"nodes":[]},"subIssues":{"nodes":[]}},
 "i4":{"number":5,"parent":null,"blockedBy":{"nodes":[]},"subIssues":{"nodes":[]}},
 "i5":{"number":6,"parent":null,"blockedBy":{"nodes":[{"number":7}]},"subIssues":{"nodes":[]}},
 "i6":{"number":7,"parent":null,"blockedBy":{"nodes":[{"number":6}]},"subIssues":{"nodes":[]}},
 "i7":{"number":8,"parent":null,"blockedBy":{"nodes":[{"number":9},{"number":13}]},"subIssues":{"nodes":[]}}}}}
EOF
# The search answer: only #3, #4, #5 and #8 match. #3 waits on #2 (open, assigned), which the search left out; #5
# names the epic #1 and #99, which does not exist. #8 waits on #9 and #13, left out too and unassigned: #9 waits on
# the open #11 through GitHub's relation, #13 on the open #10 through its body section only. The second GraphQL
# answer is the generator fetching the left-out blockers (that query asks for bodies), the third the state of #10
# (titles but no bodies); the links query asks for neither. Who opened each issue comes in every shape GitHub may
# give: a login (with spaces around it on #3), an empty one, a deleted account ("ghost"), null, a number, none.
cat > "$SB/issues-search.json" <<'EOF'
[{"number":3,"title":"Build on it","state":"OPEN","labels":[{"name":"agent-ready","color":"0e8a16"}],"assignees":[{"login":"dev-2"}],"author":{"login":" dev-2 "},"body":"### Blocked by\n#2 — Lay the base\n","url":"https://example.invalid/3"},
 {"number":4,"title":"Decide the next step","state":"OPEN","labels":[{"name":"needs-human","color":"d93f0b"}],"assignees":[],"author":{"login":""},"body":"### Blocked by\n#3 — Build on it\n","url":"https://example.invalid/4"},
 {"number":5,"title":"Odd links","state":"OPEN","labels":[],"assignees":[],"author":{"login":"ghost"},"body":"### Blocked by\n#1\n#5\n#99\n","url":"https://example.invalid/5"},
 {"number":8,"title":"Wait on the far ones","state":"OPEN","labels":[{"name":"agent-ready","color":"0e8a16"}],"assignees":[],"author":{"login":7},"body":"### Blocked by\n#9\n#13\n","url":"https://example.invalid/8"}]
EOF
cat > "$SB/outside.json" <<'EOF'
{"data":{"repository":{
 "i0":{"number":1,"title":"Epic one","state":"OPEN","url":"https://example.invalid/1","body":"","labels":{"nodes":[{"name":"epic","color":"8250df"}]},"assignees":{"nodes":[]}},
 "i1":{"number":2,"title":"Lay the base","state":"OPEN","url":"https://example.invalid/2","body":"### Blocked by\n(none)\n","labels":{"nodes":[{"name":"agent-ready","color":"0e8a16"},{"name":"story","color":"cccccc"}]},"assignees":{"nodes":[{"login":"dev-1"}]},"author":{"login":"lead-1"},"blockedBy":{"nodes":[]}},
 "i2":{"number":9,"title":"Far one by relation","state":"OPEN","url":"https://example.invalid/9","body":"","labels":{"nodes":[{"name":"agent-ready","color":"0e8a16"}]},"assignees":{"nodes":[]},"author":null,"blockedBy":{"nodes":[{"number":11,"title":"Hidden base","state":"OPEN"}]}},
 "i3":{"number":13,"title":"Far one by section","state":"OPEN","url":"https://example.invalid/13","body":"### Blocked by\n#10\n","labels":{"nodes":[{"name":"agent-ready","color":"0e8a16"}]},"assignees":{"nodes":[]},"author":{"login":"far-dev"},"blockedBy":{"nodes":[]}},
 "i4":null}}}
EOF
cat > "$SB/states.json" <<'EOF'
{"data":{"repository":{"i0":{"number":10,"title":"Other hidden base","state":"OPEN"}}}}
EOF
cat > "$SB/ghbin/gh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$SB/gh.log"
case "\$1 \$2" in
    "issue list") case " \$* " in *" --search "*) cat "$SB/issues-search.json" ;; *) cat "$SB/issues.json" ;; esac ;;
    "repo view") case "\${3:-}" in --json) echo '{"name":"demo","owner":{"login":"owner"}}' ;; *) echo "{\"name\":\"\${3#*/}\",\"owner\":{\"login\":\"\${3%%/*}\"}}" ;; esac ;;
    "api user") echo tester ;;
    "api graphql") case "\$*" in *body*) cat "$SB/outside.json" ;; *title*) cat "$SB/states.json" ;; *) cat "$SB/links.json" ;; esac ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$SB/ghbin/gh"
MAPHTML="$MAPREPO/docs/issue_map/issue_map.html"
# Runs the generator with the given options; its output goes to $SB/out and every gh call it made to $SB/gh.log.
# Python on Windows starts a bare "gh" only as gh.exe, so it never finds the bash fake: there the generator runs
# through a wrapper that hands each gh call to this bash and the fake.
run_map() {
    rm -f "$SB/gh.log" "$MAPHTML"
    if command -v cygpath >/dev/null 2>&1; then
        (cd "$MAPREPO" && "$PY" - "$(cygpath -m "$BASH")" "$(cygpath -m "$SB/ghbin/gh")" \
            "$(cygpath -m "$REPO/skills/issue-map/scripts/issue_map.py")" "$@" >"$SB/out" 2>&1 <<'EOF'
import runpy, subprocess, sys
bash, fake, script = sys.argv[1:4]
real_run = subprocess.run
def run(args, *rest, **kwargs):
    if args and args[0] == "gh":
        args = [bash, fake, *args[1:]]
    return real_run(args, *rest, **kwargs)
subprocess.run = run
sys.argv = [script, *sys.argv[4:]]
runpy.run_path(script, run_name="__main__")
EOF
        )
    else
        (cd "$MAPREPO" && PATH="$SB/ghbin:$PATH" "$PY" "$REPO/skills/issue-map/scripts/issue_map.py" "$@" >"$SB/out" 2>&1)
    fi
}
run_map
check "the map is built from the issues and says how many it holds" eval '[ -f "$MAPHTML" ] && grep -q "6 issues + 1 epics" "$SB/out"'
check "with neither option, every issue is listed and no blocker is fetched apart" eval '! grep -q -- "--search\|--repo" "$SB/gh.log" && ! grep -q "^api graphql.*title" "$SB/gh.log" && ! grep -q "outside" "$SB/out" && ! grep -q "node[a-z -]* outside" "$MAPHTML"'
check "an issue's column is one more than its deepest blocker's" eval 'grep -q ">Level 2 <tspan" "$MAPHTML" && ! grep -q ">Level 3 <tspan" "$MAPHTML"'
check "every dropped link and disagreement is listed in plain words, and in the sentence other skills read" eval 'grep -q "which is an epic: link dropped" "$MAPHTML" && grep -q "which is not on the map: link dropped" "$MAPHTML" && grep -q "which closes a loop: link dropped" "$MAPHTML" && grep -q "sources disagree" "$MAPHTML" && grep -q "they DISAGREE on: #4, #5, #6\." "$SB/out" && grep -q "#5->#1, #5->#99" "$SB/out" && grep -q "close a cycle: #5->#5, #6->#7" "$SB/out"'
map_offers_filters_and_problems() {
    local f; for f in "Who takes it" Progress Assignee Labels; do grep -q "name:.$f." "$MAPHTML" || return 1; done
    grep -q 'id="problems"' "$MAPHTML"
}
check "the page offers the four filter menus and the data problems pane" map_offers_filters_and_problems
check "the issue list asks GitHub who opened each issue" grep -q -- "^issue list .*--json [a-z,]*author" "$SB/gh.log"
# Who opened each issue, as the details card's grey line names it: the login from the issue list (or, for a blocker
# the search left out, from the GraphQL answer), else "unknown" for a missing, empty or non-text login or a deleted
# account (GitHub's "ghost"). Prints what is wrong and fails on any mismatch.
map_opened_by_is() {
    local html="$MAPHTML"; command -v cygpath >/dev/null 2>&1 && html="$(cygpath -m "$MAPHTML")"
    "$PY" - "$html" "$@" <<'PYEOF'
import json, re, sys
page = open(sys.argv[1], encoding="utf-8").read()
meta = json.loads(re.search(r"const META=(.*?);const UP=", page, re.S).group(1))
bad = [f"#{n}: {meta.get(n, {}).get('openedBy')!r}, want {want!r}"
       for n, want in (pair.split("=", 1) for pair in sys.argv[2:]) if meta.get(n, {}).get("openedBy") != want]
print("\n".join("  " + b for b in bad)) if bad else None
sys.exit(1 if bad else 0)
PYEOF
}
check "each card names who opened the issue, or unknown with no usable login or a deleted account" map_opened_by_is 1=lead-1 2=lead-1 3=dev-2 4=unknown 5=unknown 6=unknown 7=unknown
check "the card's grey line says opened by right after the GitHub state, before the assignees" grep -qF "' \\u00b7 GitHub state: '+esc(m.state)+' \\u00b7 opened by '+esc(m.openedBy)+(m.assignees.length?' \\u00b7 assigned to '" "$MAPHTML"
# A click anywhere outside the card unpins it as Esc does, while the clicked control still does its job (the listener
# sits on the document, after every control's own); a box toggles the card itself, and a pan or a press that began
# in the card is no click. The hint and the help text say so, and the old "click again to clear" wording is gone.
map_closes_card_on_outside_click() {
    grep -qF "let pressInTip=false;addEventListener('pointerdown',ev=>{pressInTip=tip.contains(ev.target);moved=false},true);" "$MAPHTML" \
        && grep -qF "document.addEventListener('click',ev=>{const inTip=pressInTip||tip.contains(ev.target);pressInTip=false;if(moved){moved=false;return}" "$MAPHTML" \
        && grep -qF "if(pinned!==null&&!inTip&&!ev.target.closest('.node')){pinned=null;clear()}});" "$MAPHTML" \
        && grep -qF 'Click outside to close \u00b7 double-click opens it on GitHub \u00b7 drag the title to move this card' "$MAPHTML" \
        && grep -qF 'Click an issue to see its chain and its card, click outside to close.' "$MAPHTML" \
        && ! grep -qi 'again to clear' "$MAPHTML"
}
check "a click outside the details card closes it, unless it is a pan or began in the card, and the hint says so" map_closes_card_on_outside_click
check "an assigned issue with a blocker still open shows as blocked, not in progress" grep -q 'class="node blocked k-agent" data-id="3"' "$MAPHTML"
check "the map never shows up as a change in git" eval '[ -z "$(cd "$MAPREPO" && "$REAL_GIT" status --porcelain)" ]'
run_map --search "label:bug"
search_map_holds_matches() {
    grep -q "^issue list .*--search label:bug" "$SB/gh.log" && grep -q "4 issues + 0 epics + 4 outside the search" "$SB/out" \
        && grep -q 'class="node blocked k-human" data-id="4"' "$MAPHTML" && ! grep -q 'data-id="6"' "$MAPHTML" \
        && ! grep -q 'data-id="7"' "$MAPHTML"
}
check "--search hands the search to the issue list and maps only the matching issues" search_map_holds_matches
check "a blocker the search left out is drawn as a faded box" grep -q 'class="node inprog k-agent outside" data-id="2"' "$MAPHTML"
check "and the issue waiting on it still shows as blocked, never free" grep -q 'class="node blocked k-agent" data-id="3"' "$MAPHTML"
check "a left-out blocker whose own blocker is open shows as blocked, never ready, by relation or by body section" eval 'grep -q "class=\"node blocked k-agent outside\" data-id=\"9\"" "$MAPHTML" && grep -q "class=\"node blocked k-agent outside\" data-id=\"13\"" "$MAPHTML"'
check "a left-out blocker that is no issue, or is an epic, is still a dropped link" eval 'grep -q "#5->#1, #5->#99" "$SB/out" && grep -q "which is not on the map: link dropped" "$MAPHTML"'
check "a blocker the search left out names who opened it too, asked for with its other fields" eval 'grep -q "^api graphql.*body.*author { login }" "$SB/gh.log" && map_opened_by_is 2=lead-1 9=unknown 13=far-dev 3=dev-2 8=unknown'
check "the page says it holds only the issues the search matched" grep -q 'Only the issues matching the GitHub search <b>label:bug</b>' "$MAPHTML"
run_map --repo other-owner/other.repo
repo_map_built() {
    grep -q "^issue list .*--repo other-owner/other.repo" "$SB/gh.log" && grep -q "^repo view other-owner/other.repo " "$SB/gh.log" \
        && grep -qF 'repository(owner: "other-owner", name: "other.repo")' "$SB/gh.log" && grep -q "6 issues + 1 epics" "$SB/out" \
        && grep -q "<title>other-owner/other.repo · issue map" "$MAPHTML"
}
check "--repo builds the map for that repository" repo_map_built
bad_repo_refused() {  # repository value: refused before any gh call, nothing rebuilt
    run_map "--repo=$1"
    [ ! -f "$MAPHTML" ] && [ ! -s "$SB/gh.log" ] && grep -q "owner/name" "$SB/out"
}
check "a --repo value that is not owner/name is refused before gh runs" eval 'bad_repo_refused nope && bad_repo_refused "a/b\" x" && bad_repo_refused "a/b/c" && bad_repo_refused "/b" && bad_repo_refused ../.. && bad_repo_refused -b/x'

echo "check (the session-start hook: silent unless it has news, always exit 0)"
newproj; init ask
V="$(sed -n 1p "$P/.claude/orion/VERSION")"
check "first check asks for /orion-verify" eval 'run_check && grep -q orion-verify "$SB/hook" && hook_out_ok "$SB/hook"'
check "the post-install question is asked once" eval 'FAKE_LS_SHA="$V" run_check && ! grep -q orion-verify "$SB/hook"'
check "up to date: silent, exit 0" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
check "newer orion, ask mode: one JSON line" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check --force && grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'
check "the update is offered at every session start, not once a day" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check && grep -q "newer orion.*update --skip" "$SB/hook" && FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check && grep -q "newer orion" "$SB/hook"'
skip_update() { env PATH="$FAKEPATH" FAKE_LS_SHA="$1" bash "$P/.claude/orion/orion.sh" update --skip --project "$P" >"$SB/out" 2>&1; }
check "declined with update --skip: quiet until a newer orion, which is offered again" eval 'skip_update 1111111111111111111111111111111111111111 && FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check && [ ! -s "$SB/hook" ] && FAKE_LS_SHA=2222222222222222222222222222222222222222 run_check && grep -q "newer orion" "$SB/hook"'
set_cfg updateMode '"off"'
check "off mode: silent, exit 0" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check --force && [ ! -s "$SB/hook" ]'
set_cfg updateMode '"auto"'
# auto never updates the folder the session opens in: it asks the agent to ship the update through its own pull request
project_state() { ( cd "$P" && find . -type f -exec cksum {} + | LC_ALL=C sort ); }
auto_asks_to_ship() { grep -q "newer orion.*updateMode is 'auto'.*through its own pull request" "$SB/hook" && ! grep -q "failed" "$SB/hook" && hook_out_ok "$SB/hook"; }
run_update() {  # the update the agent runs in its own worktree: the installed copy, from a sandboxed temporary folder
    mkdir -p "$SB/tmp"; rm -rf "$SB/tmp"/*
    env PATH="$FAKEPATH" TMPDIR="$SB/tmp" bash "$P/.claude/orion/orion.sh" update --project "$P" "$@" >"$SB/out" 2>&1
}
project_state > "$SB/state-before"; rm -f "$SB/cp-slept"
check "auto mode: exit 0, and asks the agent to ship the update through its own pull request, in one JSON line" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_CLONE_FAIL=1 FAKE_CP_SLEEP=11 run_check --force && auto_asks_to_ship'
check "auto mode writes nothing into the project and copies nothing" eval 'project_state | cmp -s - "$SB/state-before" && [ ! -e "$SB/cp-slept" ]'
check "auto mode: no temporary clone left behind" nothing_left_in_tmp
t0=$(date +%s)
check "auto mode never fetches orion: a clone that would hang does not slow the hook" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_CLONE_HANG=1 run_check --force && auto_asks_to_ship && [ $(( $(date +%s) - t0 )) -lt 10 ]'
check "auto mode asks again at the next session start, until the update ships" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check && auto_asks_to_ship && project_state | cmp -s - "$SB/state-before"'
# a newer orion in a local source repository
SRC="$SB/src"; mkdir -p "$SRC"; cp -R "$REPO/orion.sh" "$REPO/skills" "$REPO/baselines" "$SRC/"
"$REAL_GIT" -C "$SRC" init -q -b main && "$REAL_GIT" -C "$SRC" -c core.autocrlf=false add . && "$REAL_GIT" -C "$SRC" commit -qm src
SRC_SHA="$("$REAL_GIT" -C "$SRC" rev-parse HEAD)"
bash "$ORION" init --project "$P" --yes --source "$SRC" --no-statusline >"$SB/out" 2>&1; cp "$SB/out" "$SB/out-reinit"; consume_marker
check "re-init with a new --source changes config.json and says so" eval 'grep -q "source changed" "$SB/out-reinit" && bash "$ORION" status --project "$P" | grep -qF "$SRC"'
project_state > "$SB/state-before"
check "auto mode with a newer source: asks to ship it and leaves the project as it was" eval 'run_check --force && auto_asks_to_ship && project_state | cmp -s - "$SB/state-before"'
check "the update the agent runs in its worktree: every file of every skill is copied" eval 'run_update && [ "$(cd "$SRC/skills" && find . -mindepth 2 -type f | grep -v /__pycache__/ | sort)" = "$(cd "$P/.claude/skills" && find . -mindepth 2 -type f ! -name .orion-managed | sort)" ]'
check "and the project is then at the source commit" eval '[ "$(sed -n 1p "$P/.claude/orion/VERSION")" = "$SRC_SHA" ]'
check "and no temporary clone is left behind" nothing_left_in_tmp

echo "version number (three parts, from the release tags; an update is offered only when a release raised it)"
# A source of its own whose commit carries an old whole-number tag and a three-part one: the three-part one wins.
VSRC="$SB/vsrc"; mkdir -p "$VSRC"; cp -R "$REPO/orion.sh" "$REPO/skills" "$REPO/baselines" "$VSRC/"
"$REAL_GIT" -C "$VSRC" init -q -b main && "$REAL_GIT" -C "$VSRC" -c core.autocrlf=false add . && "$REAL_GIT" -C "$VSRC" commit -qm vsrc
"$REAL_GIT" -C "$VSRC" tag v38 && "$REAL_GIT" -C "$VSRC" tag v2.3.4
newproj; bash "$VSRC/orion.sh" init --project "$P" --yes --source "$VSRC" --no-statusline --update-mode ask >"$SB/out" 2>&1; consume_marker
check "init records the highest release tag on the source's commit, three parts above an old whole number" eval '[ "$(sed -n 5p "$P/.claude/orion/VERSION")" = 2.3.4 ]'
check "status shows it" eval 'bash "$ORION" status --project "$P" | grep -q "version:    orion 2.3.4,"'
check "a newer commit without a higher release: silent" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="38 39 2.3.4" run_check --force && [ ! -s "$SB/hook" ]'
check "a higher release, compared part by part: the update is offered by version, in one JSON line" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="2.3.4 2.10.0 2.9.0" run_check --force && grep -q "newer orion.*(orion 2.3.4 -> orion 2.10.0)" "$SB/hook" && hook_out_ok "$SB/hook"'
mv "$P/.claude/orion/global" "$SB/global-aside"
check "the newest release installed and a baseline folder missing: no update offer, one JSON line or none" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="2.3.4" run_check --force && ! grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'
check "the same commit and a baseline folder missing: no update offer" eval 'FAKE_LS_SHA="$(sed -n 1p "$P/.claude/orion/VERSION")" run_check --force && ! grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'
mv "$SB/global-aside" "$P/.claude/orion/global"
set_cfg ref '"other"'
check "a ref other than main goes by commit, not by release" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="2.3.4" run_check --force && grep -q "newer orion" "$SB/hook"'
set_cfg ref '"main"'
# An install from before three-part versions: a whole number on line 5.
set_installed_version() { { sed -n '1,4p' "$P/.claude/orion/VERSION"; printf '%s\n' "$1"; } > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"; }
set_installed_version 38
check "an old whole number installed: a three-part release is offered" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="38 39 2.0.0" run_check --force && grep -q "newer orion.*(orion 38 -> orion 2.0.0)" "$SB/hook" && hook_out_ok "$SB/hook"'
check "two whole numbers still compare as numbers" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="9 38" run_check --force && [ ! -s "$SB/hook" ] && FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_LS_TAGS="38 39" run_check --force && grep -q "(orion 38 -> orion 39)" "$SB/hook"'
printf 'x\n' > "$VSRC/next.txt"
"$REAL_GIT" -C "$VSRC" -c core.autocrlf=false add next.txt && "$REAL_GIT" -C "$VSRC" commit -qm next && "$REAL_GIT" -C "$VSRC" tag v2.4.0
check "and its next update writes the three-part version of the newest release" eval 'env PATH="$FAKEPATH" bash "$P/.claude/orion/orion.sh" update --project "$P" >"$SB/out" 2>&1 && [ "$(sed -n 5p "$P/.claude/orion/VERSION")" = 2.4.0 ]'
check "installed right before its release was tagged, on the commit main still points at: no offer" eval 'FAKE_LS_SHA="$(sed -n 1p "$P/.claude/orion/VERSION")" FAKE_LS_TAGS="2.4.0 2.4.1" run_check --force && [ ! -s "$SB/hook" ]'
"$REAL_GIT" -C "$VSRC" tag v2.4.1
check "and update on that commit records the release's version without copying again" eval 'env PATH="$FAKEPATH" bash "$P/.claude/orion/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "already at" "$SB/out" && [ "$(sed -n 5p "$P/.claude/orion/VERSION")" = 2.4.1 ]'
# A ref other than main gets the version of the files it fetched: release tags mark main, so a branch at the first
# release is that release, even though main has newer ones.
"$REAL_GIT" -C "$VSRC" branch old "$("$REAL_GIT" -C "$VSRC" rev-list --max-parents=0 HEAD)"; set_cfg ref '"old"'
check "update from a ref other than main records the release on the fetched commit, not the newest on main" eval 'env PATH="$FAKEPATH" bash "$P/.claude/orion/orion.sh" update --project "$P" --force >"$SB/out" 2>&1 && [ "$(sed -n 5p "$P/.claude/orion/VERSION")" = 2.3.4 ] && bash "$ORION" status --project "$P" | grep -q "version:    orion 2.3.4,"'
set_cfg ref '"main"'

echo "release versions (the release job sizes one version tag from the Conventional Commit types since the last release)"
RV="$REPO/.github/scripts/release-version.sh"
RR="$SB/release"; mkdir -p "$RR"; "$REAL_GIT" -C "$RR" init -q -b main
rel_commit() {  # file subject: a squash-merged pull request that changes <file>
    mkdir -p "$(dirname "$RR/$1")"; printf '%s\n' "$2" >> "$RR/$1"
    "$REAL_GIT" -C "$RR" add -- "$1" && "$REAL_GIT" -C "$RR" commit -qm "$2"
}
next_tags() { ( cd "$RR" && bash "$RV" next ) | tr '\n' ' ' | sed 's/ $//'; }
tag_release() { local t; for t in $(next_tags); do "$REAL_GIT" -C "$RR" tag "$t"; done; }
rel_commit skills/a/SKILL.md "feat(a): a skill"; "$REAL_GIT" -C "$RR" tag v38
rel_commit README.md "feat(readme): a new section"
check "only files projects never receive changed since the last whole-number release: nothing to tag" eval '[ -z "$(next_tags)" ]'
rel_commit orion.sh "fix: a script fix"
check "the first release is v2.0.0 whatever the types, plus one whole-number tag for orion.sh copies from before" eval '[ "$(next_tags)" = "v2.0.0 v39" ]'
tag_release
check "nothing new since the release: nothing to tag" eval '[ -z "$(next_tags)" ]'
rel_commit skills/a/SKILL.md "fix(a): a typo (#12)"
check "fix: the last part, and the next whole-number tag beside it" eval '[ "$(next_tags)" = "v2.0.1 v40" ]'
tag_release
rel_commit baselines/BASE_CLAUDE.md "feat(base): a new rule"
check "feat: the middle part" eval '[ "$(next_tags)" = "v2.1.0 v41" ]'
tag_release
"$REAL_GIT" -C "$RR" checkout -q -b develop
rel_commit orion.sh "fix: one"; rel_commit skills/a/SKILL.md "feat(a): two"; rel_commit docs/x.md "docs: three"
"$REAL_GIT" -C "$RR" checkout -q main && "$REAL_GIT" -C "$RR" merge -q --no-ff --no-edit -m "Merge the develop branch" develop
check "a release carrying a fix and a feat, merged with a merge commit: one version tag, the middle part" eval '[ "$(next_tags)" = "v2.2.0 v42" ]'
tag_release
rel_commit docs/guide.md "feat(guide): a new page"
check "a merge outside skills/, baselines/ and orion.sh tags nothing, even a feat" eval '[ -z "$(next_tags)" ]'
rel_commit skills/a/SKILL.md "fix(a): three"; rel_commit skills/a/SKILL.md "feat(a)!: a breaking change"
check "feat!: the first part" eval '[ "$(next_tags)" = "v3.0.0 v43" ]'
tag_release; "$REAL_GIT" -C "$RR" checkout -q HEAD~1
check "a re-run on an older commit the last release already contains: nothing to tag" eval '[ -z "$(next_tags)" ]'
"$REAL_GIT" -C "$RR" checkout -q main
rel_commit mods/m/README.md "fix(m): a mod fix"
check "a change to a mod is a release too" eval '[ "$(next_tags)" = "v3.0.1 v44" ]'
title_ok() { bash "$RV" title "$1" >/dev/null 2>&1; }
check "the title check passes every valid form" eval 'title_ok "feat: x" && title_ok "fix(scope): x" && title_ok "feat(two-words)!: x" && title_ok "docs!: x" && title_ok "chore(skills): refresh a skill (#7)"'
check "and fails a title with no valid type" eval '! title_ok "Add a thing" && ! title_ok "feat x" && ! title_ok "feet: x" && ! title_ok "Feat: x" && ! title_ok "feat(): x" && ! title_ok "feat:x" && ! title_ok "feat: " && ! title_ok ""'

echo "upgrade from an install whose hook still has the old 20 s limit"
# The older script, as far as this matters: it writes a 20 s hook and never raises it. CI checks out no
# history, so it is made from today's script rather than taken from git.
mkdir -p "$SB/old"; OLD="$SB/old/orion.sh"
awk '/^HOOK_TIMEOUT=60$/ { print "HOOK_TIMEOUT=20"; next }
     /^settings_raise_hook_timeout\(\) \{/ { print "settings_raise_hook_timeout() { :; }"; print "settings_raise_hook_timeout_unused() {"; next }
     { print }' "$ORION" > "$OLD"
newproj
bash "$OLD" init --project "$P" --yes --source "$SRC" --no-statusline --update-mode auto >"$SB/out" 2>&1; consume_marker
check "the older script installs a 20 s hook" eval '[ "$(hook_timeouts "$P/.claude/settings.json")" = 20 ]'
check "an update run by the older script leaves it at 20 s" eval 'bash "$OLD" update --project "$P" --force >"$SB/out" 2>&1 && [ "$(hook_timeouts "$P/.claude/settings.json")" = 20 ]'
{ printf '%s\n' 0000000000000000000000000000000000000000; sed -n '2,$p' "$P/.claude/orion/VERSION"; } > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
check "on that 20 s session, auto mode asks to ship the update and leaves the files as they were" eval 'run_check --force && auto_asks_to_ship && [ "$(sed -n 1p "$P/.claude/orion/VERSION")" = 0000000000000000000000000000000000000000 ]'
check "and that first check by the new script raised the hook to 60 s" eval '[ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'
check "and left no temporary clone behind" nothing_left_in_tmp
check "the update the agent then runs goes to the end" eval 'run_update && [ "$(sed -n 1p "$P/.claude/orion/VERSION")" = "$SRC_SHA" ]'
set_old_hook_timeout "$P/.claude/settings.json"; set_cfg updateMode '"ask"'
check "with nothing new, check heals a 20 s hook and stays silent" eval 'FAKE_LS_SHA="$SRC_SHA" run_check --force && [ ! -s "$SB/hook" ] && [ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'

echo "orion files left uncommitted (offered for shipping every session, local only, never discarded)"
newproj; init off; consume_marker
printf '\nmine\n' >> "$P/.claude/skills/issue-map/scripts/issue_map.py"
check "outside a git repository: silent" eval 'run_check --force && [ ! -s "$SB/hook" ]'
"$REAL_GIT" -C "$P" init -q -b main && "$REAL_GIT" -C "$P" -c core.autocrlf=false add . && "$REAL_GIT" -C "$P" commit -qm init
offered_files() { grep -q "orion's own files in this folder differ from the last commit" "$SB/hook" && hook_out_ok "$SB/hook"; }
local_only() { ! grep -qE '(^| )(ls-remote|fetch|clone|pull|push)( |$)' "$SB/git.log"; }
uc_check() { rm -f "$SB/git.log"; FAKE_GIT_LOG="$SB/git.log" run_check --force; }
restore() { "$REAL_GIT" -C "$P" checkout -q -- . && "$REAL_GIT" -C "$P" clean -qfd; }
check "a folder whose orion files match the last commit: silent, with no network call" eval 'uc_check && [ ! -s "$SB/hook" ] && [ -s "$SB/git.log" ] && local_only'
printf '\nmine too\n' >> "$P/.claude/skills/issue-map/scripts/issue_map.py"
check "a changed file of an orion skill is offered for shipping, in one JSON line, with no network call" eval 'uc_check && offered_files && local_only'
check "and the change is never discarded" eval 'tail -n 1 "$P/.claude/skills/issue-map/scripts/issue_map.py" | grep -qx "mine too"'
restore; printf 'x\n' > "$P/.claude/skills/issue-map/new.txt"
check "a new file in an orion skill is offered" eval 'uc_check && offered_files && [ -f "$P/.claude/skills/issue-map/new.txt" ]'
restore; rm -rf "$P/.claude/skills/issue-map"
check "a whole orion skill removed is offered" eval 'uc_check && offered_files'
restore; rm "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
check "a file the manifest lists, removed, is offered" eval 'uc_check && offered_files'
restore; mkdir -p "$P/.claude/skills/own"; printf 'own\n' > "$P/.claude/skills/own/SKILL.md"
"$REAL_GIT" -C "$P" add .claude/skills/own && "$REAL_GIT" -C "$P" commit -qm own
printf 'more\n' >> "$P/.claude/skills/own/SKILL.md"; set_cfg branchLimit 30
check "files that are the project's own (config.json, a skill without the marker): silent" eval 'uc_check && [ ! -s "$SB/hook" ]'
restore
# odd manifest lines: blank, a Windows line ending, outside the project, absolute, the folder itself, wildcards and
# pathspec magic
printf '\n../../../../outside\n/abs/path\n/\n.\n./\n*\n:(glob)**\norion.sh\r\n.claude\n' > "$P/.claude/orion/.orion-manifest"
"$REAL_GIT" -C "$P" -c core.autocrlf=false commit -qam "odd manifest"
set_cfg branchLimit 30
check "odd manifest lines: no wildcard reaches a file of the project's own, exit 0, silent" eval 'uc_check && [ ! -s "$SB/hook" ]'
printf '# mine\n' >> "$P/.claude/orion/orion.sh"
check "and a line with a Windows line ending still names its file" eval 'uc_check && offered_files'
restore
for shape in empty missing; do
    if [ "$shape" = empty ]; then : > "$P/.claude/orion/.orion-manifest"; else rm "$P/.claude/orion/.orion-manifest"; fi
    "$REAL_GIT" -C "$P" -c core.autocrlf=false commit -qam "$shape manifest"
    printf '\nmine\n' >> "$P/.claude/skills/issue-map/scripts/issue_map.py"
    check "a manifest that is $shape: the skills are still checked, exit 0" eval 'uc_check && offered_files'
    restore
done
"$REAL_GIT" -C "$P" worktree add -q "$SB/uc-wt" -b uc-second 2>/dev/null
printf '\nmine\n' >> "$SB/uc-wt/.claude/skills/issue-map/scripts/issue_map.py"
check "a linked worktree (an agent's own copy), with orion files changed: silent" eval 'P="$SB/uc-wt" uc_check && [ ! -s "$SB/hook" ]'
printf '\nmine\n' >> "$P/.claude/skills/issue-map/scripts/issue_map.py"; set_cfg updateMode '"auto"'
check "with an update to ship too: both are asked for, in one JSON line" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check --force && auto_asks_to_ship && offered_files'

echo "the post-install marker waits for /orion-verify"
newproj; XDG_CACHE_HOME="$SB/cache-marker" init ask; rm -rf "$P/.claude/skills/orion-verify"
check "check without the skill does not ask for it" eval 'XDG_CACHE_HOME="$SB/cache-marker" FAKE_LS_SHA="$V" run_check && [ ! -s "$SB/hook" ]'
check "and leaves the marker in place" eval 'ls "$SB/cache-marker/orion/"*.verify-pending >/dev/null 2>&1'

echo "the rules check (asks for /orion-verify once each time orion's rules change on this computer)"
newproj; init ask; consume_marker
asked_rules() { grep -q "have changed since they were last checked" "$SB/hook"; }
check "after verify: no rules question" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
printf '\n- a new rule\n' >> "$P/.claude/orion/BASE_CLAUDE.md"
check "a changed BASE_CLAUDE.md asks for /orion-verify, in one JSON line" eval 'FAKE_LS_SHA="$V" run_check --force && asked_rules && hook_out_ok "$SB/hook"'
check "and only once" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
printf '\nmore\n' >> "$P/.claude/skills/dev-next/references/new-issue.md"
check "a changed file of an orion skill asks again" eval 'FAKE_LS_SHA="$V" run_check --force && asked_rules'
printf '\nmore\n' >> "$P/.claude/skills/issue-map/scripts/issue_map.py"
check "a changed script does not ask" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
asked_new() { grep -q "orion is new on this computer" "$SB/hook" && ! asked_rules; }
check "a computer that never checked these rules asks once, as new on this computer, not as changed rules" eval 'XDG_CACHE_HOME="$SB/cache-mate" FAKE_LS_SHA="$V" run_check --force && asked_new && hook_out_ok "$SB/hook"'
check "and nothing on the next check" eval 'XDG_CACHE_HOME="$SB/cache-mate" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
# Line endings: the same rules with Windows or Unix line endings are the same rules.
crlf() { local f; for f in "$@"; do awk '{ sub(/\r$/, ""); printf "%s\r\n", $0 }' "$f" > "$SB/crlf" && mv "$SB/crlf" "$f"; done; }
lf() { local f; for f in "$@"; do tr -d '\r' < "$f" > "$SB/lf" && mv "$SB/lf" "$f"; done; }
RULE_FILES=("$P/.claude/orion/BASE_CLAUDE.md" "$P/.claude/skills/dev-next/SKILL.md")
crlf "${RULE_FILES[@]}"
check "rules checked with Windows line endings: silent once they turn to Unix line endings" eval 'XDG_CACHE_HOME="$SB/cache-mate" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ] && lf "${RULE_FILES[@]}" && XDG_CACHE_HOME="$SB/cache-mate" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
# The fingerprint orion took before it ignored line endings: the raw bytes of BASE_CLAUDE.md, then every .md file
# of every orion skill in sorted path order.
raw_rules_sum() {
    local d dirs=()
    for d in "$P"/.claude/skills/*/; do [ -f "${d%/}/.orion-managed" ] && dirs+=("${d%/}"); done
    { cat "$P/.claude/orion/BASE_CLAUDE.md"; find "${dirs[@]}" -type f -name '*.md' | LC_ALL=C sort | while IFS= read -r f; do cat "$f"; done; } | cksum | cut -d' ' -f1
}
crlf "${RULE_FILES[@]}"; mkdir -p "$SB/cache-raw/orion"; raw_rules_sum > "$SB/raw-sum"
for f in "$SB/cache-mate/orion/"*.rules-checked; do cp "$SB/raw-sum" "$SB/cache-raw/orion/${f##*/}"; done
check "a fingerprint stored by the older orion (raw bytes) is silent and rewritten" eval 'XDG_CACHE_HOME="$SB/cache-raw" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ] && ! cmp -s "$SB/raw-sum" "$SB/cache-raw/orion/"*.rules-checked'
check "so the line endings may change after it, still silent" eval 'lf "${RULE_FILES[@]}" && XDG_CACHE_HOME="$SB/cache-raw" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
check "verify records the rules it checked" eval 'XDG_CACHE_HOME="$SB/cache-mate2" bash "$ORION" verify --project "$P" >/dev/null 2>&1; XDG_CACHE_HOME="$SB/cache-mate2" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
rm -rf "$P/.claude/skills/orion-verify"
check "without the /orion-verify skill nothing is asked" eval 'XDG_CACHE_HOME="$SB/cache-mate3" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
newproj; bash "$ORION" init --project "$P" --yes --source "$SRC" --no-statusline >"$SB/out" 2>&1; consume_marker
printf '\n- a newer rule\n' >> "$SRC/baselines/BASE_CLAUDE.md"; "$REAL_GIT" -C "$SRC" -c core.autocrlf=false commit -qam rules
check "an update that changes the rules says to run /orion-verify" eval 'bash "$P/.claude/orion/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "run /orion-verify" "$SB/out"'
consume_marker
printf '\n# a comment\n' >> "$SRC/skills/issue-map/scripts/issue_map.py"; "$REAL_GIT" -C "$SRC" -c core.autocrlf=false commit -qam script
check "an update that leaves the rules alone does not" eval 'bash "$P/.claude/orion/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "orion update" "$SB/out" && ! grep -q "run /orion-verify" "$SB/out"'
printf '\n- the newest rule\n' >> "$SRC/baselines/BASE_CLAUDE.md"; "$REAL_GIT" -C "$SRC" -c core.autocrlf=false commit -qam rules2
set_cfg updateMode '"auto"'
check "auto mode with newer rules: asks to ship them, and the rules question waits until they reach the project" eval 'run_check --force && auto_asks_to_ship && ! asked_rules'
check "once the shipped update reaches the project, the next session asks for /orion-verify, in one JSON line" eval 'run_update && FAKE_LS_SHA="$("$REAL_GIT" -C "$SRC" rev-parse HEAD)" run_check --force && asked_rules && ! grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'

echo "one record per repository (every worktree of one clone shares what this computer recorded)"
# Checked by an older orion first (its records are keyed on the folder), then the folder becomes a git repository.
newproj; init ask; consume_marker; MAIN="$P"
"$REAL_GIT" -C "$MAIN" init -q -b main && "$REAL_GIT" -C "$MAIN" -c core.autocrlf=false add . && "$REAL_GIT" -C "$MAIN" commit -qm init
"$REAL_GIT" -C "$MAIN" worktree add -q "$SB/wt-second" -b second 2>/dev/null
check "the main checkout's folder record is carried over: silent" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
path_key() { printf '%s' "$1" | cksum | cut -d' ' -f1; }
check "and copied, not moved: an older orion.sh still running in the main checkout keeps its own record" eval '[ -f "$XDG_CACHE_HOME/orion/$(path_key "$MAIN").rules-checked" ]'
P="$SB/wt-second"
check "a second worktree of a checked repository: silent" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
check "update --skip given in one worktree holds in another" eval 'skip_update 1111111111111111111111111111111111111111 && P="$MAIN" && FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check && [ ! -s "$SB/hook" ]'
P="$MAIN"
# The main checkout gets newer rules while the worktree keeps the older ones: sessions that switch between the two
# folders are asked once, not every time.
printf '\n- a rule only the main checkout has\n' >> "$MAIN/.claude/orion/BASE_CLAUDE.md"
"$REAL_GIT" -C "$MAIN" -c core.autocrlf=false commit -qam "newer rules"
alternate_asks() {  # main, worktree, main, worktree: prints how many sessions asked about the rules
    local n=0 p
    for p in "$MAIN" "$SB/wt-second" "$MAIN" "$SB/wt-second"; do
        P="$p" FAKE_LS_SHA="$V" run_check --force && grep -q "have changed since they were last checked" "$SB/hook" && n=$((n+1))
    done
    P="$MAIN"; printf '%s' "$n"
}
check "a main checkout and a worktree on different rules, sessions alternating: asked once in all" eval '[ "$(alternate_asks)" = 1 ]'
# A checkout reached through a symbolic link: its worktrees still share its record, and an older orion's record,
# keyed on the path the checkout was opened by, is still carried over.
mkdir -p "$SB/real-repo"; ln -s "$SB/real-repo" "$SB/link-repo"
P="$SB/link-repo"; init ask; consume_marker; LINKED="$P"
"$REAL_GIT" -C "$LINKED" init -q -b main && "$REAL_GIT" -C "$LINKED" -c core.autocrlf=false add . && "$REAL_GIT" -C "$LINKED" commit -qm init
"$REAL_GIT" -C "$LINKED" worktree add -q "$SB/wt-linked" -b second 2>/dev/null
check "a checkout opened through a symbolic link: its older record is carried over, silent" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
check "and its worktree shares the record: silent" eval 'P="$SB/wt-linked" && FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
P="$LINKED"; REPO_KEY="$(path_key "$(cd "$SB/real-repo/.git" && pwd -P)")"
check "uninstall removes the repository's record and the main checkout's older one" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$XDG_CACHE_HOME/orion/$REPO_KEY.rules-checked" ] && [ ! -e "$XDG_CACHE_HOME/orion/$(path_key "$LINKED").rules-checked" ]'
P="$MAIN"

echo "a cache folder that cannot be written (the hook still answers in one JSON line, with nothing on stderr)"
mkdir -p "$SB/home-ro"
newproj; XDG_CACHE_HOME="$SB/cache-ro" init ask; XDG_CACHE_HOME="$SB/cache-ro" consume_marker
"$REAL_GIT" -C "$P" init -q -b main && "$REAL_GIT" -C "$P" -c core.autocrlf=false add . && "$REAL_GIT" -C "$P" commit -qm init
set_cfg branchLimit 1   # one branch is enough to offer the tidy-up and write its stamp
chmod 555 "$SB/cache-ro/orion"
check "rules, personal rules and branch count records cannot be written: one JSON line, nothing on stderr" eval 'HOME="$SB/home-ro" XDG_CACHE_HOME="$SB/cache-ro" FAKE_LS_SHA="$V" run_check --force && [ -s "$SB/hook" ] && hook_out_ok "$SB/hook" && [ ! -s "$SB/hook-err" ]'
# A hook runner may start the hook with SIGPIPE ignored (an ignored signal stays ignored in every child): a write
# into a pipe whose reader failed then prints "Broken pipe" on stderr instead of ending quietly.
check "and the same with SIGPIPE ignored: one JSON line, nothing on stderr" eval '( trap "" PIPE; HOME="$SB/home-ro" XDG_CACHE_HOME="$SB/cache-ro" FAKE_LS_SHA="$V" run_check --force ) && [ -s "$SB/hook" ] && hook_out_ok "$SB/hook" && [ ! -s "$SB/hook-err" ]'
chmod 755 "$SB/cache-ro/orion"

echo "branch counter (hook and scanner count the same, two remotes)"
newproj; "$REAL_GIT" -C "$P" init -q -b main; "$REAL_GIT" -C "$P" commit -q --allow-empty -m one
for b in b1 b2 b3; do "$REAL_GIT" -C "$P" branch "$b"; done
"$REAL_GIT" -C "$P" remote add origin https://example.invalid/a.git; "$REAL_GIT" -C "$P" remote add other https://example.invalid/b.git
for r in origin/main origin/f1 other/f2; do "$REAL_GIT" -C "$P" update-ref "refs/remotes/$r" HEAD; done
"$REAL_GIT" -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
init off; consume_marker; keep_orion_out_of_git; set_cfg branchLimit 7
check "the hook offers the tidy-up at 7 branches" eval 'run_check --force && grep -q "has 7 git branches" "$SB/hook" && hook_out_ok "$SB/hook"'
check "the scanner counts 7 too" eval 'bash "$REPO/skills/clear-git-resources/scripts/scan.sh" --project "$P" --wt-root "$SB/wt" --limit 7 | grep -q "total=7 limit=7 .*over=yes"'
check "status shows the branch count" eval 'bash "$ORION" status --project "$P" | grep -q "branches now: 7"'
set_cfg branchLimit 8
check "below the limit: silent" eval 'run_check --force && [ ! -s "$SB/hook" ]'

echo "scanner: yours and stale is deleted without asking, someone else's is asked, audit and QA resources are never touched"
mkdir -p "$SB/wt"
"$REAL_GIT" -C "$P" worktree add -q --detach "$SB/wt/audit-dev" && "$REAL_GIT" -C "$SB/wt/audit-dev" checkout -q --orphan audit/dev && "$REAL_GIT" -C "$SB/wt/audit-dev" commit -q --allow-empty -m report
"$REAL_GIT" -C "$P" worktree add -q --detach "$SB/wt/qa-20000101-000000"
"$REAL_GIT" -C "$P" checkout -q -b theirs && GIT_AUTHOR_EMAIL=other@example.invalid "$REAL_GIT" -C "$P" commit -q --allow-empty -m theirs
"$REAL_GIT" -C "$P" checkout -q main && "$REAL_GIT" -C "$P" merge -q --no-ff --no-edit theirs && "$REAL_GIT" -C "$P" update-ref refs/remotes/origin/main main
"$REAL_GIT" -C "$P" checkout -q -b mine-wip && "$REAL_GIT" -C "$P" commit -q --allow-empty -m wip && "$REAL_GIT" -C "$P" checkout -q main
"$REAL_GIT" -C "$P" branch qa/keep && "$REAL_GIT" -C "$P" update-ref refs/remotes/origin/qa/x main
for b in mine-done wt-done-br wt-locked-br; do
    "$REAL_GIT" -C "$P" checkout -q -b "$b" && "$REAL_GIT" -C "$P" commit -q --allow-empty -m "$b" && "$REAL_GIT" -C "$P" checkout -q main && "$REAL_GIT" -C "$P" merge -q --no-ff --no-edit "$b"
done
"$REAL_GIT" -C "$P" update-ref refs/remotes/origin/main main
"$REAL_GIT" -C "$P" worktree add -q -b wt-mine "$SB/wt/wt-mine"
"$REAL_GIT" -C "$P" worktree add -q "$SB/wt/wt-done" wt-done-br
"$REAL_GIT" -C "$P" worktree add -q "$SB/wt/wt-locked" wt-locked-br && "$REAL_GIT" -C "$P" worktree lock "$SB/wt/wt-locked"
"$REAL_GIT" -C "$P" worktree add -q --detach "$SB/wt/wt-lost" && "$REAL_GIT" -C "$SB/wt/wt-lost" commit -q --allow-empty -m "only here"
"$REAL_GIT" -C "$P" worktree add -q --detach "$SB/wt/wt-gone" && rm -rf "$SB/wt/wt-gone"
"$REAL_GIT" -C "$P" worktree add -q --detach "$SB/wt/audit-gone" && rm -rf "$SB/wt/audit-gone"
"$REAL_GIT" -C "$P" worktree add -q --detach "$SB/wt/lost-gone" && "$REAL_GIT" -C "$SB/wt/lost-gone" commit -q --allow-empty -m "only there" && rm -rf "$SB/wt/lost-gone"
mkdir -p "$SB/wt/old-dir" "$SB/wt/old-busy" && : > "$SB/wt/old-busy/fresh.txt" && touch -t 200001010000 "$SB/wt/old-dir" "$SB/wt/old-busy"
bash "$REPO/skills/clear-git-resources/scripts/scan.sh" --project "$P" --wt-root "$SB/wt" > "$SB/scan"
item_is() { awk -F'\t' -v g="$1" -v n="$2" -v a="$3" '$1=="ITEM" && $2==g && $3 ~ n && $4==a { f=1 } END { exit !f }' "$SB/scan"; }
check "your branch already on main is deleted without asking" item_is br-merged '^mine-done$' auto
check "a branch with no commits of its own is asked about, never deleted unasked" item_is br-merged '^b1$' ask
check "someone else's branch already on main is asked about" item_is br-merged '^theirs$' ask
check "your worktree whose branch is on main is deleted without asking" item_is wt-done 'wt-done$' auto
check "a fresh worktree with no commits of its own is asked about" item_is wt-done 'wt-mine$' ask
check "a locked worktree is asked about, never deleted unasked" item_is wt-done 'wt-locked$' ask
check "a worktree on no branch holding commits nothing else has is kept" item_is wt-active 'wt-lost$' keep
check "a worktree entry whose folder is gone is removed alone, not with a global prune" eval 'item_is wt-prunable "wt-gone$" auto && grep "^ITEM	wt-prunable	[^	]*wt-gone" "$SB/scan" | grep -q "worktree remove --force"'
check "an audit worktree entry whose folder is gone is kept" item_is wt-protected 'audit-gone$' keep
check "an entry whose folder is gone, holding commits no branch has, is kept" item_is wt-active 'lost-gone$' keep
check "a leftover folder in the worktree root is asked about" item_is root-orphan 'old-dir$' ask
check "a folder with a recently changed file inside is kept" item_is root-recent 'old-busy$' keep
check "unmerged work is kept, with no command" eval 'item_is br-unmerged "^mine-wip$" keep && ! awk -F"\t" '"'"'$3=="mine-wip" && $6!=""'"'"' "$SB/scan" | grep -q .'
check "the audit worktree is kept, with its reason" eval 'item_is wt-protected "audit-dev$" keep && grep -q "^ITEM	wt-protected	.*audit-dev	.*audit/dev" "$SB/scan"'
check "the QA worktree is kept, never offered" eval 'item_is wt-protected "qa-20000101-000000$" keep && ! grep -q "^ITEM	wt-[a-z]*	[^	]*qa-20000101-000000	[^	]*	[^	]*	." "$SB/scan"'
check "no command in the scan touches an audit or qa branch" eval '! grep -q "branch -D \"audit/" "$SB/scan" && ! awk -F"\t" '"'"'$1=="ITEM" && $3 ~ /(^|\/)qa\// && $6!=""'"'"' "$SB/scan" | grep -q .'
check "the scanner counts worktrees" eval 'grep -q "^COUNT	.*worktrees=9 " "$SB/scan"'
check "the summary counts auto, ask and keep" eval 'grep -q "^SUMMARY	auto=[0-9]* ask=[1-9][0-9]* keep=[1-9][0-9]*$" "$SB/scan"'
set_cfg branchLimit 99; set_cfg worktreeLimit 9
check "the hook offers the tidy-up at 9 worktrees" eval 'run_check --force && grep -q "has 9 git worktrees" "$SB/hook" && hook_out_ok "$SB/hook"'
check "status shows the worktree count" eval 'bash "$ORION" status --project "$P" | grep -q "worktrees now: 9"'
check "verify reads the worktree limit" eval 'bash "$ORION" verify --project "$P" | grep -q "ok    config-worktree-limit"'
set_cfg worktreeLimit 10
check "below both limits: silent" eval 'run_check --force && [ ! -s "$SB/hook" ]'

echo "check pulls the branch the session opens on (fast-forward only, every session)"
R="$SB/remote.git"; "$REAL_GIT" init -q --bare "$R"
"$REAL_GIT" clone -q "$R" "$SB/peer" 2>/dev/null; "$REAL_GIT" -C "$SB/peer" checkout -q -b main
"$REAL_GIT" -C "$SB/peer" commit -q --allow-empty -m one && "$REAL_GIT" -C "$SB/peer" push -q -u origin main 2>/dev/null
newproj; rmdir "$P"; "$REAL_GIT" clone -q -b main "$R" "$P"; init off; consume_marker; keep_orion_out_of_git
"$REAL_GIT" -C "$SB/peer" commit -q --allow-empty -m two && "$REAL_GIT" -C "$SB/peer" push -q 2>/dev/null
check "a new commit on the remote is pulled, silently" eval 'run_check && [ ! -s "$SB/hook" ] && [ "$("$REAL_GIT" -C "$P" rev-parse HEAD)" = "$("$REAL_GIT" -C "$R" rev-parse main)" ]'
"$REAL_GIT" -C "$P" commit -q --allow-empty -m local; LOCAL="$("$REAL_GIT" -C "$P" rev-parse HEAD)"
"$REAL_GIT" -C "$SB/peer" commit -q --allow-empty -m three && "$REAL_GIT" -C "$SB/peer" push -q 2>/dev/null
check "a refused pull: exit 0, says so in one JSON line" eval 'run_check && grep -q "git pull" "$SB/hook" && hook_out_ok "$SB/hook"'
check "and nothing was forced: the local commit is still the tip" eval '[ "$("$REAL_GIT" -C "$P" rev-parse HEAD)" = "$LOCAL" ]'
"$REAL_GIT" -C "$P" reset -q --hard "$("$REAL_GIT" -C "$R" rev-parse main)"; "$REAL_GIT" -C "$P" config merge.autoStash true
printf 'peer
' > "$SB/peer/f.txt" && "$REAL_GIT" -C "$SB/peer" add f.txt && "$REAL_GIT" -C "$SB/peer" commit -q -m f && "$REAL_GIT" -C "$SB/peer" push -q 2>/dev/null
printf 'mine
' > "$P/f.txt"
check "a pull blocked by local changes is refused, never stashed (even with merge.autoStash set)" eval 'run_check && grep -q "git pull" "$SB/hook" && hook_out_ok "$SB/hook" && [ -z "$("$REAL_GIT" -C "$P" stash list)" ] && grep -qx mine "$P/f.txt"'
"$REAL_GIT" -C "$P" checkout -q -b lone
check "a branch with no remote copy: silent" eval 'run_check && [ ! -s "$SB/hook" ]'

echo "verify"
newproj; init ask
check "verify passes after init" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "verify: 0 fail" "$SB/out"'
check "every skill marker ends in a newline (a project lint may require one)" eval 'ls "$P"/.claude/skills/*/.orion-managed >/dev/null && [ -z "$(for m in "$P"/.claude/skills/*/.orion-managed; do [ "$(tail -c1 "$m" | od -An -c | tr -d " ")" = "\n" ] || echo "$m"; done)" ]'
check "init writes no test-copies row: nothing sizes the suite's parallel workers" eval '! grep -qiE "test copies|<copies>" "$P/CLAUDE.md"'
check "the starter's slots are flagged as unfilled" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  claude-md-slots" "$SB/out"'
# The key words verify finds each commands-table row by (COMMAND_ROW_KEYS in orion.sh) against the starter's rows: each
# key word is in exactly one row's label (a note in brackets left out), every row has one, and an optional row
# (the starter marks it "(if ...)") has none.
command_row_keys_match_the_starter() {
    local COMMAND_ROW_KEYS=() label plain key n bad=0
    eval "$(grep -E '^COMMAND_ROW_KEYS=\(' "$ORION")"
    [ "${#COMMAND_ROW_KEYS[@]}" -gt 0 ] || { echo "    no COMMAND_ROW_KEYS in orion.sh"; return 1; }
    while IFS= read -r label; do
        plain="$(printf '%s' "$label" | tr -d '*' | sed 's/([^)]*)//g' | tr '[:upper:]' '[:lower:]')"
        n=0; for key in "${COMMAND_ROW_KEYS[@]}"; do case "$plain" in *"$key"*) n=$((n+1)) ;; esac; done
        case "$label" in *"(if "*) [ "$n" -eq 0 ] || { echo "    optional row '$label' has a key word"; bad=1; } ;;
            *) [ "$n" -eq 1 ] || { echo "    row '$label' has $n key words, not one"; bad=1; } ;; esac
    done <<< "$(sed -n '/^## Build and test commands/,/^## /p' "$P/CLAUDE.md" | grep '^| ' | cut -d'|' -f2 | sed 's/^ *//; s/ *$//' | grep -vx -e Purpose -e '---')"
    for key in "${COMMAND_ROW_KEYS[@]}"; do
        n="$(sed -n '/^## Build and test commands/,/^## /p' "$P/CLAUDE.md" | grep '^| ' | cut -d'|' -f2 | tr -d '*' | sed 's/([^)]*)//g' | tr '[:upper:]' '[:lower:]' | grep -cF -- "$key")"
        [ "$n" -eq 1 ] || { echo "    key word '$key' is in $n starter rows, not one"; bad=1; }
    done
    return "$bad"
}
check "every commands-table key word names exactly one row of the starter, and every required row has one" command_row_keys_match_the_starter
check "a full commands table: no missing-row warning" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && ! grep -q "claude-md-row:" "$SB/out" && grep -q "ok    claude-md-rows" "$SB/out"'
cp "$P/CLAUDE.md" "$SB/full.md"
grep -v '^| Lint' "$SB/full.md" > "$P/CLAUDE.md"
check "a missing lint row: one warning naming orion's row, and verify still exits 0" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && [ "$(grep -c "WARN  claude-md-row:" "$SB/out")" -eq 1 ] && grep -q "WARN  claude-md-row: .*\"Lint\".*word .lint." "$SB/out"'
sed -e 's/^| One file |/| Run a single file |/' -e 's/^| \*\*The full suite\*\* |/| Whole test suite (CI runs it) |/' \
    -e 's/^| Typecheck \/ static analysis |/| Type checks |/' \
    -e 's/^## Build and test commands$/## Commands/' "$SB/full.md" > "$P/CLAUDE.md"
check "reworded row labels and heading still count as present" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && ! grep -q "claude-md-row:" "$SB/out"'
{ printf '```\n# commands to try later\n```\n\n'; grep -v -e '^| Build' -e '^| Lint' "$SB/full.md"; printf '\n## Other notes\n\n| Build | `make` |\n| Lint | `make lint` |\n'; } > "$P/CLAUDE.md"
check "a row outside the commands section or a heading in a code block does not count: a warning per missing row" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && [ "$(grep -c "WARN  claude-md-row:" "$SB/out")" -eq 2 ] && grep -q "\"Build\".*word .build." "$SB/out" && grep -q "\"Lint\".*word .lint." "$SB/out"'
# A header cell holding a key word (| Type | Command |) is no row: the row it names, missing, still warns.
header_is_no_row() {
    local header row key
    for pair in "Type|Typecheck / static analysis|type" "File|One file|file"; do
        header="${pair%%|*}"; row="${pair#*|}"; key="${row#*|}"; row="${row%|*}"
        sed -e "s/^| Purpose | Command |\$/| $header | Command |/" "$SB/full.md" | grep -vF "| $row |" > "$P/CLAUDE.md"
        bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 \
            && [ "$(grep -c "WARN  claude-md-row:" "$SB/out")" -eq 1 ] && grep -q "WARN  claude-md-row: .*word '$key'" "$SB/out" \
            || { echo "    a '$header' header hid the missing '$row' row"; return 1; }
    done
}
check "a header cell holding a key word does not count as the row: the missing row still warns" header_is_no_row
cp "$SB/full.md" "$P/CLAUDE.md"
# orion-verify's half: a missing row is proposed with its source and added only on a yes, a false warning becomes an
# offer to rename the label, and the sentence sections stay a reading check.
orion_verify_proposes_missing_rows() {
    local s; s="$(tr '\n' ' ' <"$REPO/skills/orion-verify/SKILL.md" | tr -s ' ')"
    for want in "every row a \`claude-md-row\` warning says the table lacks" "the file and line it came from" \
        "is added only on a yes" "rename that row's label to orion's wording, keeping the project's command" \
        "never propose a second row" "are judged by reading alone" \
        "never work out or fill its command. Offer once, as **needs a yes**, to delete the row"; do
        case "$s" in *"$want"*) ;; *) echo "    orion-verify lacks: $want"; return 1 ;; esac
    done
}
check "orion-verify proposes a missing row with its source, adds it only on a yes, offers a rename on a false warning and offers to delete a row orion no longer reads" orion_verify_proposes_missing_rows
cp "$P/CLAUDE.md" "$SB/starter.md"; printf '%s\n\n| One test | `dotnet test --filter <test-name>` |\n| Test copies | `-n <copies>` |\n- Branches: `feat/<N>-<slug>`.\n' "$IMPORT" > "$P/CLAUDE.md"
check "a <placeholder> inside a real command is not a slot" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; ! grep -q "claude-md-slots" "$SB/out"'
printf '%s\n\n| One test | `dotnet test` |\n| Test copies (how the full suite takes `<copies>` parallel workers) | `TBD` |\n' "$IMPORT" > "$P/CLAUDE.md"
check "a test-copies row an older starter left unfilled is not a slot: nothing asks for it" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; ! grep -q "claude-md-slots" "$SB/out"'
printf '%s\n\n| One test | `TBD` |\n| Test copies | `TBD` |\n' "$IMPORT" > "$P/CLAUDE.md"
check "beside it, a row still to fill is counted alone" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  claude-md-slots: CLAUDE.md has 1 line" "$SB/out"'
cp "$SB/starter.md" "$P/CLAUDE.md"
check "no changelog folder: verify says to create docs/changelog/" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  changelog-missing: docs/changelog/" "$SB/out"'
rm -f "$P/.claude/orion/BASE_CLAUDE.md"
check "verify fails when a core file is missing" eval '! bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "FAIL  core-files" "$SB/out"'
newproj; init ask; rm -f "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
check "verify fails when the project copy of GLOBAL_CLAUDE.md is missing" eval '! bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "FAIL  core-files.*GLOBAL_CLAUDE.md" "$SB/out"'
newproj; "$REAL_GIT" -C "$P" init -q; printf '.claude/\n' > "$P/.gitignore"
check "init warns when git ignores the files it installed" eval 'init ask && grep -q "ignored by .gitignore" "$SB/out"'
check "verify names them and says an ignored .claude/ must become .claude/*" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  git-ignored: .*\.claude/\*" "$SB/out"'
printf '.claude/*\n!.claude/settings.json\n' > "$P/.gitignore"
check "contents ignored but not the folder: the fix is the missing re-includes, not a rewrite" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  git-ignored" "$SB/out" && ! grep -q "ignored as a whole" "$SB/out"'
printf '.claude/*\n!.claude/orion/\n!.claude/skills/\n!.claude/settings.json\n' > "$P/.gitignore"
check "with .claude/* and the re-includes nothing orion installed is ignored" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "ok    git-tracked" "$SB/out"'
mkdir -p "$P/src/prototypes" && : > "$P/src/prototypes/app.js"
check "a folder sharing only the last name (src/prototypes for docs/ux/prototypes/) is not offered" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; ! grep -q "folder-misplaced: the rules expect docs/ux/prototypes/" "$SB/out"'
mkdir -p "$P/docs/product/PRDs" && : > "$P/docs/product/PRDs/PRD.md"
check "a folder the rules name, kept elsewhere: verify offers the move" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  folder-misplaced: the rules expect docs/PRDs/, but the project keeps it at docs/product/PRDs/" "$SB/out"'
mkdir -p "$P/docs/PRDs"
check "once it is where the rules expect it: no warning" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "ok    folders" "$SB/out"'
: > "$P/docs/CHANGELOG.md"
check "an old single-file changelog: verify asks for docs/changelog/ and names the old file as the history" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "WARN  changelog-missing: docs/changelog/.*docs/CHANGELOG.md stays as the history" "$SB/out"'
mkdir -p "$P/docs/changelog"
check "a changelog folder in docs/: no warning" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1; grep -q "ok    changelog:" "$SB/out"'

echo "personal rules (GLOBAL_CLAUDE.md is offered clause by clause; orion never writes the person's own file)"
GLOBAL="$REPO/baselines/global/GLOBAL_CLAUDE.md"
# One line per clause (every bullet or numbered item below the first "## " heading): "<version> <text>", or
# "BAD <line>" for a clause without a valid version marker and for any other text among the clauses.
clauses() {  # file
    tr -d '\r' < "$1" | awk '
        /^## / { s = 1; next }
        !s || /^#/ || NF == 0 { next }
        /^([-*]|[0-9]+\.) / && match($0, / <!-- orion:v[0-9]+(\.[0-9]+\.[0-9]+)?[+]? -->$/) {
            print substr($0, RSTART + 13, RLENGTH - 17) " " substr($0, 1, RSTART - 1); next }
        { print "BAD " $0 }'
}
# The newest of the versions on stdin, one per line, in orion.sh's order: three parts above a whole number, and a
# version ending in "+" just above the version it names.
newest_version() {
    awk '{ v = $0; p = sub(/[+]$/, "", v); n = split(v, a, ".")
           k = n == 3 ? sprintf("2 %012d %012d %012d %d", a[1], a[2], a[3], p) : sprintf("1 %012d 0 0 %d", a[1], p)
           if (k > best) { best = k; out = $0 } }
         END { print out }'
}
check "GLOBAL_CLAUDE.md has clauses, each carrying a valid version marker" eval '[ -n "$(clauses "$GLOBAL")" ] && ! clauses "$GLOBAL" | grep -q "^BAD "'
check "the clause that labels every line has a risk line say open or fixed in its label" eval 'grep -F "**Label every line with what it is**" "$GLOBAL" | grep -F "Risk (open):" | grep -qF "Risk (fixed):"'
# A clause changed or added against origin/main must carry the newest released version plus "+" ("changed after"),
# so everyone who went through that release is offered it; a pull request left open across a release refreshes its
# notes. CI fetches origin/main and the release tags before the suite.
changed_clauses_marked_after_newest_release() {
    local old="$SB/global-main" newest
    "$REAL_GIT" -C "$REPO" rev-parse -q --verify origin/main >/dev/null || { echo "    origin/main not found: fetch it first"; return 1; }
    "$REAL_GIT" -C "$REPO" show origin/main:baselines/global/GLOBAL_CLAUDE.md > "$old" 2>/dev/null || return 0   # new file: every clause is new
    newest="$("$REAL_GIT" -C "$REPO" tag -l 'v*' | sed 's/^v//' | grep -E '^[0-9]+(\.[0-9]+\.[0-9]+)?$' | newest_version)"
    clauses "$old" | cut -d' ' -f2- > "$SB/global-main-texts"
    clauses "$GLOBAL" | while IFS=' ' read -r d text; do
        grep -qxF -- "$text" "$SB/global-main-texts" && continue
        [ -n "$newest" ] || { echo "    no release tag found: fetch the tags first"; exit 1; }
        [ "$d" = "$newest+" ] || { echo "    changed clause not marked v$newest+ (the newest release, then +): $text"; exit 1; }
    done
}
check "every clause changed against origin/main is marked the newest release plus + (changed after it)" changed_clauses_marked_after_newest_release
GH="$SB/home-global"; mkdir -p "$GH"; PERSONAL="$GH/.claude/CLAUDE.md"
NEWEST="$(clauses "$GLOBAL" | cut -d' ' -f1 | newest_version)"
# A clause note newer than any the file can carry.
NEWER=999.0.0
gl_check() { HOME="$GH" run_check "$@"; }
asked_global() { grep -q "GLOBAL_CLAUDE.md" "$SB/hook"; }
section() { mkdir -p "$GH/.claude"; printf '# my own rules\n\n- keep this\n\n# ORION GLOBAL — v%s\n<!-- /ORION GLOBAL -->\n' "$1" > "$PERSONAL"; }
rm -f "$XDG_CACHE_HOME/orion/global-offered" "$XDG_CACHE_HOME/orion/global-offered-version"   # no personal rules offer yet on this computer
newproj; HOME="$GH" init ask
check "right after init, the post-install message also offers the discussion" eval 'gl_check && grep -q orion-verify "$SB/hook" && asked_global && hook_out_ok "$SB/hook"'
check "the first offer on a computer prints nothing on stderr" eval '[ ! -s "$SB/hook-err" ]'
check "the project carries GLOBAL_CLAUDE.md, listed in the manifest" eval '[ -f "$P/.claude/orion/global/GLOBAL_CLAUDE.md" ] && grep -qx "global/GLOBAL_CLAUDE.md" "$P/.claude/orion/.orion-manifest"'
check "no ORION GLOBAL section yet: the discussion is offered, in one JSON line" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && hook_out_ok "$SB/hook"'
check "and the hook wrote no personal rules file" eval '[ ! -e "$PERSONAL" ]'
check "it is offered once: the next check is silent" eval 'FAKE_LS_SHA="$V" gl_check && ! asked_global'
LATER=$(( $(date +%s) + 2 * 86400 )); GP="$P"
newproj; HOME="$GH" init ask; consume_marker; GP2="$P"; P="$GP"
check "two days later still silent, in this project and in another" eval 'FAKE_NOW="$LATER" FAKE_LS_SHA="$V" gl_check && [ ! -s "$SB/hook" ] && P="$GP2" && FAKE_NOW="$LATER" FAKE_LS_SHA="$V" gl_check && [ ! -s "$SB/hook" ]'
P="$GP"; cp "$P/.claude/orion/global/GLOBAL_CLAUDE.md" "$SB/global-copy"
printf -- '- a newer rule <!-- orion:v%s -->\n' "$NEWER" >> "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
check "a clause with a higher version than the one offered is offered once more" eval 'FAKE_LS_SHA="$V" gl_check && asked_global && hook_out_ok "$SB/hook" && FAKE_LS_SHA="$V" gl_check && ! asked_global'
check "check --force still offers" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && hook_out_ok "$SB/hook"'
cp "$SB/global-copy" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
check "the offer no longer says it comes back tomorrow" eval '! grep -q tomorrow "$SB/hook"'
# An older orion.sh on the same computer keeps writing a Unix time to global-offered when it offers (once a day);
# this one keeps the highest version offered in global-offered-version and pins that time in the future once it
# offered, so an older orion.sh never offers again. Where a scenario has the older orion.sh carry every clause on
# offer, the project copy's markers are capped at the last once-a-day release (17) for it alone; a clause above it is
# offered even then, which is checked below.
sed -E 's/<!-- orion:v[0-9.]+[+]? -->$/<!-- orion:v17 -->/' "$SB/global-copy" > "$SB/global-older"
cp "$SB/global-older" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
OFFERED="$XDG_CACHE_HOME/orion/global-offered"; OFFERED_V="$XDG_CACHE_HOME/orion/global-offered-version"
rm -f "$OFFERED_V"; printf '%s' "$(( $(date +%s) - 86401 ))" > "$OFFERED"
check "no version offered yet and the older orion's time stamp a day old: one last offer" eval 'FAKE_LS_SHA="$V" gl_check && asked_global && hook_out_ok "$SB/hook"'
check "and none after it, two days later" eval 'FAKE_NOW="$LATER" FAKE_LS_SHA="$V" gl_check && ! asked_global'
older_offers() {  # [now] one session of an older orion.sh: it offers when its time stamp is a day old or more, and stamps now
    local now last; now="${1:-$(date +%s)}"; last="$(cat "$OFFERED" 2>/dev/null || echo 0)"
    [ $((now - last)) -ge 86400 ] || return 1
    printf '%s' "$now" > "$OFFERED"
}
check "the offer pinned the older orion's time stamp, so an older orion.sh never offers again" eval '! older_offers && ! older_offers "$LATER"'
rm -f "$OFFERED_V"; printf '%s' "$(date +%s)" > "$OFFERED"
check "an older orion.sh offered earlier today: this one counts it as offered, silent today and later" eval 'FAKE_LS_SHA="$V" gl_check && ! asked_global && FAKE_NOW="$LATER" FAKE_LS_SHA="$V" gl_check && ! asked_global'
check "and pinned the time stamp, so that older orion.sh does not offer again the next day" eval '! older_offers "$LATER"'
rm -f "$OFFERED_V"; printf '%s' "$(date +%s)" > "$OFFERED"; FAKE_NOW="$LATER" FAKE_LS_SHA="$V" gl_check
printf -- '- a newer rule <!-- orion:v%s -->\n' "$NEWER" >> "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
check "a pinned time stamp never hides a clause with a higher version" eval 'FAKE_LS_SHA="$V" gl_check && asked_global && FAKE_LS_SHA="$V" gl_check && ! asked_global'
cp "$SB/global-older" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
printf -- '- a rule no once-a-day orion.sh carries <!-- orion:v18 -->\n' >> "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
rm -f "$OFFERED_V"; printf '%s' "$(date +%s)" > "$OFFERED"
check "an older orion.sh offered today, but a rule above any it carries is still offered, once" eval 'FAKE_LS_SHA="$V" gl_check && asked_global && FAKE_LS_SHA="$V" gl_check && ! asked_global'
cp "$SB/global-copy" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
# orion 18 wrote the same real time to both files when it offered: this one pins it on its next check
NOW18="$(date +%s)"; printf '%s %s\n' "$NEWEST" "$NOW18" > "$OFFERED_V"; printf '%s' "$NOW18" > "$OFFERED"
check "a record left by orion 18: silent, and the time stamp is pinned so an older orion.sh stays quiet" eval 'FAKE_LS_SHA="$V" gl_check && ! asked_global && ! older_offers "$LATER"'
cp "$SB/global-older" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
mixed_offers() {  # first-opener (older|newer): six sessions on one day alternating; prints how many offered
    local n=0 i who="$1"
    rm -f "$OFFERED" "$OFFERED_V"
    for i in 1 2 3 4 5 6; do
        if [ "$who" = older ]; then older_offers && n=$((n+1)); who=newer
        else FAKE_LS_SHA="$V" gl_check && asked_global && n=$((n+1)); who=older; fi
    done
    printf '%s' "$n"
}
check "an older orion.sh and this one alternating on one day, the older first: one offer in all" eval '[ "$(mixed_offers older)" = 1 ]'
check "the same with this one first: one offer in all" eval '[ "$(mixed_offers newer)" = 1 ]'
mixed_days() {  # first-opener (older|newer): both open a session each day for five days; prints how many offered
    local n=0 day now
    rm -f "$OFFERED" "$OFFERED_V"
    for day in 0 1 2 3 4; do
        now=$(( $(date +%s) + day * 86400 ))
        [ "$1" = older ] && older_offers "$now" && n=$((n+1))
        FAKE_NOW="$now" FAKE_LS_SHA="$V" gl_check && asked_global && n=$((n+1))
        [ "$1" = newer ] && older_offers "$now" && n=$((n+1))
    done
    printf '%s' "$n"
}
check "an older orion.sh and this one on five days, the older opening first each day: one offer in all" eval '[ "$(mixed_days older)" = 1 ]'
check "the same with this one first each day: one offer in all" eval '[ "$(mixed_days newer)" = 1 ]'
cp "$SB/global-copy" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
section 1
check "a clause above the section's version number is offered" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && hook_out_ok "$SB/hook"'
section "$NEWEST"
check "every clause at the section's version number or below: silent" eval 'FAKE_LS_SHA="$V" gl_check --force && [ ! -s "$SB/hook" ]'
# Every real clause is made older first, so the note below is the newest one whatever the real file carries.
cp "$SB/global-older" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
printf -- '- a rule changed after 2.4.1 <!-- orion:v2.4.1+ -->\n' >> "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
section 999999
check "a section with an old whole number is older than any three-part note: offered" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global'
section 2.4.1
check "a note changed after 2.4.1 is offered to a section at 2.4.1" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global'
section 2.4.1+
check "a section that went through that change: silent" eval 'FAKE_LS_SHA="$V" gl_check --force && [ ! -s "$SB/hook" ]'
section 2.4.2
check "a section at the release after it: silent" eval 'FAKE_LS_SHA="$V" gl_check --force && [ ! -s "$SB/hook" ]'
cp "$SB/global-copy" "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
section 1; set_cfg updateMode '"off"'
check "off mode never offers it" eval 'gl_check --force && [ ! -s "$SB/hook" ]'
newproj; HOME="$GH" init off
check "nor does the post-install message under off" eval 'gl_check && grep -q orion-verify "$SB/hook" && ! asked_global'
set_cfg updateMode '"auto"'; cp "$PERSONAL" "$SB/personal-before"
check "auto mode only offers it and never writes the person's file" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && cmp -s "$SB/personal-before" "$PERSONAL"'
check "uninstall leaves the person's file byte for byte as it was" eval 'HOME="$GH" bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ] && cmp -s "$SB/personal-before" "$PERSONAL"'

echo "config, manifest and copies"
newproj
bash "$ORION" init --project "$P" --yes --source 'C:\some\orion' --no-statusline >"$SB/out" 2>&1
check "a Windows path as --source keeps config.json valid JSON" json_ok "$P/.claude/orion/config.json"
check "and reads back unchanged" eval 'bash "$ORION" status --project "$P" | grep -qF "source:     C:\\some\\orion"'
check "no __pycache__ is copied into the project" eval '[ -z "$(find "$P/.claude/skills" -name __pycache__)" ]'
awk '{printf "%s\r\n", $0}' "$P/.claude/orion/.orion-manifest" > "$SB/m" && mv "$SB/m" "$P/.claude/orion/.orion-manifest"
check "uninstall with Windows line endings in the manifest removes everything" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ]'

echo "status line drawing (the script fed a fake stdin JSON, colours stripped)"
# A HOME of its own keeps the script's caches in the sandbox; the fake npx keeps its cost refresh off the network.
ESC="$(printf '\033')"
sl_second_line() {  # json: the status line's second line for that stdin
    printf '%s' "$1" | HOME="$SB/home-draw" PATH="$FAKEPATH" bash "$REPO/baselines/statusline/statusline.sh" 2>/dev/null | sed "s/$ESC\[[0-9;]*m//g" | tail -n 1
}
second_lines_are() {  # json want [json want ...]
    local got
    while [ $# -ge 2 ]; do
        got="$(sl_second_line "$1")"
        [ "$got" = "$2" ] || { printf '        for %s: got [%s], want [%s]\n' "$1" "$got" "$2"; return 1; }
        shift 2
    done
}
check "the second line shows wkt:<name> from either worktree field, nothing without one, the name verbatim" second_lines_are \
    '{"cwd":"/work/proj","workspace":{"git_worktree":"feat-x"}}'                     '/work/proj  |  wkt:feat-x' \
    '{"cwd":"/work/proj","worktree":{"name":"wt-only"}}'                             '/work/proj  |  wkt:wt-only' \
    '{"cwd":"/work/proj","workspace":{"git_worktree":"first"},"worktree":{"name":"second"}}' '/work/proj  |  wkt:first' \
    '{"cwd":"/work/proj"}'                                                           '/work/proj' \
    '{"cwd":"/work/proj","workspace":{"git_worktree":"50%_a\\b100%s\\n"}}'           '/work/proj  |  wkt:50%_a\b100%s\n'
# Throw-away folders, one per case (the git cache is keyed on the folder); the ceiling keeps git from finding a repository above the sandbox.
sl_first_line() {  # dir: the status line's first line for a session in that folder, the cost segments cut off
    printf '{"cwd":"%s"}' "$1" | HOME="$SB/home-draw" PATH="$FAKEPATH" GIT_CEILING_DIRECTORIES="$SB" \
        bash "$REPO/baselines/statusline/statusline.sh" 2>/dev/null | sed "s/$ESC\[[0-9;]*m//g" | head -n 1 | sed 's/  |  \$.*$//'
}
first_lines_are() {  # dir want [dir want ...]
    local got
    while [ $# -ge 2 ]; do
        got="$(sl_first_line "$1")"
        [ "$got" = "$2" ] || { printf '        for %s: got [%s], want [%s]\n' "$1" "$got" "$2"; return 1; }
        shift 2
    done
}
mkdir -p "$SB/draw-outside"
for d in draw-branch draw-detached; do
    "$REAL_GIT" -C "$SB" init -q -b main "$d" && "$REAL_GIT" -C "$SB/$d" commit -q --allow-empty -m first
done
"$REAL_GIT" -C "$SB/draw-detached" checkout -q --detach; : > "$SB/draw-detached/new.txt"
DETACHED_ID="$("$REAL_GIT" -C "$SB/draw-detached" rev-parse --short HEAD)"
check "the git segment names the commit on a detached HEAD, the branch on a branch, and is absent outside git" first_lines_are \
    "$SB/draw-detached" "ctx: --  |  [detached:$DETACHED_ID]  | stashed:0 untracked:1 modified:0 unstaged:0 unpushed:0" \
    "$SB/draw-branch"   'ctx: --  |  [main]  | stashed:0 untracked:0 modified:0 unstaged:0 unpushed:0' \
    "$SB/draw-outside"  'ctx: --'
# One folder per working-tree state: modified counts staged and unstaged changes, unstaged only the ones not staged yet.
for d in draw-staged draw-unstaged draw-both draw-mixed; do
    "$REAL_GIT" -C "$SB" init -q -b main "$d"
    for f in a b moved gone dropped twice; do printf 'one\n' > "$SB/$d/$f.txt"; done
    "$REAL_GIT" -C "$SB/$d" -c core.autocrlf=false add . && "$REAL_GIT" -C "$SB/$d" commit -q -m first
done
( cd "$SB/draw-staged" && printf 'two\n' >> a.txt && "$REAL_GIT" -c core.autocrlf=false add a.txt )
( cd "$SB/draw-unstaged" && printf 'two\n' >> a.txt )
( cd "$SB/draw-both" && printf 'two\n' >> a.txt && "$REAL_GIT" -c core.autocrlf=false add a.txt && printf 'two\n' >> b.txt )
( cd "$SB/draw-mixed" && "$REAL_GIT" mv moved.txt renamed.txt && rm gone.txt && "$REAL_GIT" rm -q dropped.txt \
    && printf 'two\n' >> twice.txt && "$REAL_GIT" -c core.autocrlf=false add twice.txt && printf 'three\n' >> twice.txt )
check "modified counts staged and unstaged changes; unstaged counts the unstaged ones, a file staged then edited again in both" first_lines_are \
    "$SB/draw-staged"   'ctx: --  |  [main]  | stashed:0 untracked:0 modified:1 unstaged:0 unpushed:0' \
    "$SB/draw-unstaged" 'ctx: --  |  [main]  | stashed:0 untracked:0 modified:1 unstaged:1 unpushed:0' \
    "$SB/draw-both"     'ctx: --  |  [main]  | stashed:0 untracked:0 modified:2 unstaged:1 unpushed:0' \
    "$SB/draw-mixed"    'ctx: --  |  [main]  | stashed:0 untracked:0 modified:4 unstaged:2 unpushed:0'

echo "status line (the project carries orion's copy; the computer's copy takes the newest only on the person's word)"
# A computer of its own (HOME) and a source repository of its own, each commit of which is a release: release <n> is
# tagged v2.<n>.0, so release 10 also proves the versions compare part by part, never as text.
SLH="$SB/home-sl"; SLFILE="$SLH/.claude/statusline/statusline.sh"; mkdir -p "$SLH" "$SB/home-none"; seen_all_personal_rules "$SLH"
SLSRC="$SB/sl-src"; mkdir -p "$SLSRC"; cp -R "$REPO/orion.sh" "$REPO/skills" "$REPO/baselines" "$SLSRC/"
sl_commit() { SL_VER="2.$1.0"; ( cd "$SLSRC" && "$REAL_GIT" -c core.autocrlf=false add . && "$REAL_GIT" commit -q --allow-empty -m "v$SL_VER" && "$REAL_GIT" tag "v$SL_VER" ); }
sl_release() {  # number line text: orion release <number>, whose status line gains <text> after line <line>
    local f="$SLSRC/baselines/statusline/statusline.sh"
    awk -v n="$2" -v t="$3" '{ print } NR == n { print t }' "$f" > "$SB/sl" && cat "$SB/sl" > "$f"; sl_commit "$1"
}
sl_put() {  # dir number: the project's copy as a teammate's git pull brings it
    rm -rf "$P/.claude/orion/statusline"; cp -R "$1" "$P/.claude/orion/statusline"
    { sed -n '1,4p' "$P/.claude/orion/VERSION"; printf '%s\n' "$2"; } > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
}
sl_pull() { sl_put "$SLSRC/baselines/statusline" "$SL_VER"; }
sl_check() { HOME="$SLH" run_check "$@"; }
sl_cmd() { HOME="$SLH" bash "$P/.claude/orion/orion.sh" statusline "$1" --project "$P" >"$SB/out" 2>&1; }
"$REAL_GIT" -C "$SLSRC" init -q -b main; sl_commit 1
newproj
check "init --statusline seeds the computer's copy and its merge base" eval 'HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" init --project "$P" --yes --statusline --update-mode off >"$SB/out" 2>&1 && [ -f "$SLFILE" ] && [ -f "$SLH/.claude/statusline/.orion-base/statusline.sh" ]'
consume_marker
check "the project carries orion's status line, listed in the manifest" eval '[ -f "$P/.claude/orion/statusline/statusline.sh" ] && grep -qx "statusline/statusline.sh" "$P/.claude/orion/.orion-manifest"'
check "VERSION records the source's version number" eval '[ "$(sed -n 5p "$P/.claude/orion/VERSION")" = "$SL_VER" ]'
check "same baseline: check is silent" eval 'sl_check --force && [ ! -s "$SB/hook" ]'
cp -R "$P/.claude/orion/statusline" "$SB/sl-v1"; T1="$(sed -n 5p "$P/.claude/orion/VERSION")"
sl_release 2 2 '# orion v2'; sl_pull
awk '{ printf "%s\r\n", $0 }' "$P/.claude/orion/statusline/statusline.sh" > "$SB/crlf" && mv "$SB/crlf" "$P/.claude/orion/statusline/statusline.sh"
check "a newer baseline is offered to an unedited copy in one JSON line, never taken on its own" eval 'sl_check --force && grep -q "Take it" "$SB/hook" && hook_out_ok "$SB/hook" && ! grep -q "^# orion v2" "$SLFILE"'
set_cfg updateMode '"auto"'
check "auto mode still only offers it" eval 'FAKE_LS_SHA="$(sed -n 1p "$P/.claude/orion/VERSION")" sl_check --force && grep -q "Take it" "$SB/hook" && ! grep -q "^# orion v2" "$SLFILE"'
set_cfg updateMode '"off"'
awk '{ printf "%s\r\n", $0 }' "$SLFILE" > "$SB/crlf" && cat "$SB/crlf" > "$SLFILE"   # saved by a Windows editor: still unedited
check "statusline merge takes it for an unedited copy, Windows line endings and all" eval 'sl_cmd merge && grep -q "^# orion v2" "$SLFILE" && ! grep -q "<<<<<<<" "$SLFILE" && sl_check --force && [ ! -s "$SB/hook" ]'
check "without Windows line endings, so bash can still run it" eval '! grep -q "$(printf "\r")" "$SLFILE"'
sl_put "$SB/sl-v1" "$T1"
check "an older project never steps the computer's copy back" eval 'sl_check --force && [ ! -s "$SB/hook" ] && grep -q "^# orion v2" "$SLFILE"'
printf '# mine\n' >> "$SLFILE"
sl_release 3 2 '# orion v3'; sl_pull
check "an edited copy is not replaced: check offers the merge in one JSON line" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && hook_out_ok "$SB/hook" && ! grep -q "^# orion v3" "$SLFILE"'
check "statusline merge keeps the edits and takes orion's changes" eval 'sl_cmd merge && grep -q "^# orion v3" "$SLFILE" && grep -q "^# mine" "$SLFILE" && ! grep -q "<<<<<<<" "$SLFILE"'
check "after the merge, check is silent" eval 'sl_check --force && [ ! -s "$SB/hook" ]'
sl_release 4 2 '# orion v4'; sl_pull
check "statusline skip keeps the copy as it is" eval 'sl_cmd skip && ! grep -q "^# orion v4" "$SLFILE" && grep -q "^# mine" "$SLFILE"'
check "and that baseline is not offered again" eval 'sl_check --force && [ ! -s "$SB/hook" ]'
check "merge from a project no newer than the computer's copy changes nothing" eval 'cp "$SLFILE" "$SB/before" && sl_cmd merge && grep -q "nothing to" "$SB/out" && cmp -s "$SB/before" "$SLFILE"'
sl_put "$SB/sl-v1" "$T1"
check "skip from an older project never steps the stamp back" eval 'sl_cmd skip; sl_pull && sl_check --force && [ ! -s "$SB/hook" ]'
printf 'x\n' > "$SLSRC/unrelated.txt"; sl_commit 5; sl_pull
check "a release that leaves the status line alone does not offer a merge" eval 'sl_check --force && [ ! -s "$SB/hook" ] && [ "$(sed -n 1p "$SLH/.claude/statusline/.orion-baseline")" = "$(sed -n 5p "$P/.claude/orion/VERSION")" ]'
printf '# mine at the end\n' >> "$SLFILE"
sl_release 6 "$(wc -l < "$SLSRC/baselines/statusline/statusline.sh" | tr -d ' ')" '# orion v5 at the end'; sl_pull
check "a clashing edit: merge names the file to fix and exits 1" eval '! sl_cmd merge && grep -q "statusline.sh" "$SB/out" && grep -q "<<<<<<<" "$SLFILE"'
# A copy installed before orion kept a merge base: no .orion-base, and a stamp reading "orion".
rm -rf "$SLH/.claude/statusline/.orion-base"; printf 'orion' > "$SLH/.claude/statusline/.orion-baseline"
check "an older install that differs is offered the merge too" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && hook_out_ok "$SB/hook"'
check "and its merge saves the old copy to statusline.bak, then takes orion's" eval 'sl_cmd merge && grep -q "<<<<<<<" "$SLH/.claude/statusline.bak/statusline.sh" && [ "$(tr -d "\r" < "$P/.claude/orion/statusline/statusline.sh")" = "$(cat "$SLFILE")" ]'
rm -rf "$SLH/.claude/statusline/.orion-base"; printf 'orion' > "$SLH/.claude/statusline/.orion-baseline"
check "an older install that matches is adopted silently" eval 'sl_check --force && [ ! -s "$SB/hook" ] && [ -f "$SLH/.claude/statusline/.orion-base/statusline.sh" ]'
printf 'k=v\n' > "$SLH/.claude/statusline/.mine"
sl_release 7 2 '# orion v5b'; sl_pull
check "a dot file of the person's own counts as an edit and is never deleted" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && [ -f "$SLH/.claude/statusline/.mine" ]'
check "a merge takes orion's changes and keeps that dot file" eval 'sl_cmd merge && grep -q "^# orion v5b" "$SLFILE" && [ -f "$SLH/.claude/statusline/.mine" ]'
rm -f "$SLH/.claude/statusline/.mine"
printf 'old\n' > "$SLSRC/baselines/statusline/dropped.txt"; sl_commit 8; sl_pull; sl_cmd merge
rm -f "$SLSRC/baselines/statusline/dropped.txt"; sl_release 9 2 '# orion v5c'; sl_pull
check "a merge removes an unchanged file orion dropped" eval '[ -f "$SLH/.claude/statusline/dropped.txt" ] && sl_cmd merge && [ ! -e "$SLH/.claude/statusline/dropped.txt" ] && grep -q "^# orion v5c" "$SLFILE"'
# An install made by an older orion.sh: no status line copy in the project and no version number in VERSION.
HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1
rm -rf "$P/.claude/orion/statusline"; sed -n '1,3p' "$P/.claude/orion/VERSION" > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
check "update at the same commit still adds what an older orion.sh did not copy" eval 'HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1 && [ -f "$P/.claude/orion/statusline/statusline.sh" ] && [ -n "$(sed -n 5p "$P/.claude/orion/VERSION")" ]'
rm -rf "$P/.claude/orion/statusline"; set_cfg updateMode '"ask"'
check "check offers no update to a project an older orion.sh updated, at the same commit (the next update copies what is missing)" eval 'FAKE_LS_SHA="$(sed -n 1p "$P/.claude/orion/VERSION")" sl_check --force && ! grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'
set_cfg updateMode '"off"'; HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1
: > "$SLH/.claude/statusline/.DS_Store"
sl_release 10 2 '# orion v5d'; sl_pull
check "a file the system drops in the folder (.DS_Store) is not an edit" eval 'sl_check --force && grep -q "Take it" "$SB/hook" && sl_cmd merge && grep -q "^# orion v5d" "$SLFILE"'
mv "$SLH/.claude/statusline" "$SLH/.claude/statusline.old"
sl_release 11 2 '# orion v5e'; sl_pull
check "a replace cut short half-way is restored, then offered the new one" eval 'sl_check --force && [ ! -e "$SLH/.claude/statusline.old" ] && [ -f "$SLFILE" ] && grep -q "Take it" "$SB/hook" && sl_cmd merge && grep -q "^# orion v5e" "$SLFILE"'
rm -f "$SLH/.claude/statusline/README.md"
sl_release 12 2 '# orion v5f'; sl_pull
check "a file the person deleted and orion left alone stays deleted on merge" eval 'sl_cmd merge && [ ! -e "$SLH/.claude/statusline/README.md" ] && grep -q "^# orion v5f" "$SLFILE"'
cp "$SLH/.claude/statusline/.orion-base/README.md" "$SLH/.claude/statusline/README.md"   # unedited again for the tests below
# a baseline with a sub-folder, so uninstall below must remove more than flat files
mkdir -p "$SLSRC/baselines/statusline/sub"; printf 'x\n' > "$SLSRC/baselines/statusline/sub/f.txt"; sl_commit 13
sl_release 14 2 '# orion v6'
check "update says a newer status line waits and leaves an unedited copy alone" eval 'HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "statusline merge" "$SB/out" && ! grep -q "^# orion v6" "$SLFILE"'
# A copy an orion before version numbers stamped: line 1 holds a commit time, not a version number.
{ printf '1792417094\n'; sed -n 2p "$SLH/.claude/statusline/.orion-baseline"; } > "$SB/stamp" && mv "$SB/stamp" "$SLH/.claude/statusline/.orion-baseline"
printf '# mine\n' >> "$SLFILE"
check "a copy stamped with a commit time before version numbers is offered the newer one, and merge takes it and keeps the edits" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && sl_cmd merge && grep -q "^# orion v6" "$SLFILE" && grep -q "^# mine" "$SLFILE" && [ "$(sed -n 1p "$SLH/.claude/statusline/.orion-baseline")" = "$(sed -n 5p "$P/.claude/orion/VERSION")" ]'
check "a computer without orion's status line gets none from check" eval 'HOME="$SB/home-none" run_check --force && [ ! -e "$SB/home-none/.claude/statusline" ]'
check "uninstall removes the project's copy and leaves the computer's" eval 'HOME="$SLH" bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ] && [ -f "$SLFILE" ]'

echo "mods (the project carries orion's copy of each mod; a computer installs one only on the person's word)"
# A computer of its own (HOME) and a stub `claude` that records every call, first on the path: the real plugin
# command is never run, and nothing reaches the network.
MDH="$SB/home-mods"; MKT="$MDH/.claude/orion-mods"; MOD=control-tower; CALLS="$SB/claude-calls"
mkdir -p "$MDH" "$SB/claude-bin"; seen_all_personal_rules "$MDH"
cat > "$SB/claude-bin/claude" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$CALLS"
EOF
chmod +x "$SB/claude-bin/claude"
MODPATH="$SB/claude-bin:$FAKEPATH"
# The same path with every folder holding a real claude left out, for the run where Claude Code is missing.
NOCLAUDE_PATH="$(printf '%s' "$FAKEPATH" | tr ':' '\n' | while IFS= read -r d; do [ -e "$d/claude" ] || [ -e "$d/claude.exe" ] || printf '%s:' "$d"; done)"
mod_cmd() { HOME="$MDH" PATH="$MODPATH" bash "$P/.claude/orion/orion.sh" mod "$@" --project "$P" >"$SB/out" 2>&1; }
mod_check() { HOME="$MDH" run_check "$@"; }
mod_calls() { if [ -f "$CALLS" ]; then wc -l < "$CALLS" | tr -d ' '; else printf 0; fi; }
mod_bump() {  # version [line]: the project at orion <version>, as a teammate's pull brings it; its mod gains <line>
    local a="$P/.claude/orion/mods/$MOD.tar"
    { sed -n '1,4p' "$P/.claude/orion/VERSION"; printf '%s\n' "$1"; } > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
    [ -n "${2:-}" ] || return 0
    rm -rf "$SB/modx"; mkdir -p "$SB/modx" && tar -xf "$a" -C "$SB/modx" && printf '%s\n' "$2" >> "$SB/modx/README.md" \
        && ( cd "$SB/modx" && tar -cf - . ) > "$a"
}
# Every mod in the repository sits in the project as one archive, listed in the manifest, holding every one of its files.
mods_copied_and_listed() {
    local d name f a n=0
    for d in "$REPO"/mods/*/; do
        name="$(basename "$d")"; a="$P/.claude/orion/mods/$name.tar"; n=$((n+1))
        { [ -f "$a" ] && grep -qxF "mods/$name.tar" "$P/.claude/orion/.orion-manifest"; } || { echo "  missing: mods/$name.tar"; return 1; }
        while IFS= read -r f; do
            tar -tf "$a" | grep -qxF "./$f" || { echo "  not in mods/$name.tar: $f"; return 1; }
        done <<< "$(cd "$d" && find . -type f | sed 's|^\./||')"
    done
    [ "$n" -gt 0 ]
}
newproj
( cd "$MDH" && find . | LC_ALL=C sort ) > "$SB/home-before"
HOME="$MDH" PATH="$MODPATH" bash "$ORION" init --project "$P" --yes --no-statusline --update-mode off >"$SB/out" 2>&1; consume_marker
check "init copies every mod into the project, listed in the manifest" mods_copied_and_listed
check "and keeps no loose file a test runner, linter or TypeScript would collect: only one archive per mod" eval '[ -z "$(find "$P/.claude/orion/mods" -type f ! -name "*.tar")" ] && [ -z "$(find "$P/.claude/orion/mods" -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.json")" ]'
check "and changes nothing outside the project: no copy on this computer, no plugin command" eval '[ ! -e "$MKT" ] && [ ! -e "$CALLS" ] && [ "$( cd "$MDH" && find . | LC_ALL=C sort )" = "$(cat "$SB/home-before")" ]'
check "the test path really has no claude" eval '! env PATH="$NOCLAUDE_PATH" bash -c "command -v claude" >/dev/null 2>&1'
check "without Claude Code's command, mod install says so in one line, exits 1 and changes nothing" eval '! HOME="$MDH" PATH="$NOCLAUDE_PATH" bash "$P/.claude/orion/orion.sh" mod install "$MOD" --project "$P" >"$SB/out" 2>&1 && [ "$(wc -l < "$SB/out" | tr -d " ")" = 1 ] && grep -q claude "$SB/out" && [ ! -e "$MKT" ] && [ ! -e "$CALLS" ]'
check "mod install of a mod the project does not carry fails, says to run update, and changes nothing" eval '! mod_cmd install no-such-mod && grep -qF "(run: orion.sh update)" "$SB/out" && [ ! -e "$MKT" ] && [ ! -e "$CALLS" ]'
mod_bump 2.1.0
check "mod install copies the mod into this computer's marketplace folder" eval 'mod_cmd install "$MOD" && [ -f "$MKT/$MOD/.claude-plugin/plugin.json" ] && json_ok "$MKT/.claude-plugin/marketplace.json" && grep -qF "\"./$MOD\"" "$MKT/.claude-plugin/marketplace.json"'
check "and installs it from there with the plugin command, at user scope" eval '[ "$(cat "$CALLS")" = "plugin install $MOD --marketplace $MKT --scope user" ]'
check "and records the orion version it took" eval '[ "$(sed -n 1p "$MKT/$MOD.orion-baseline")" = 2.1.0 ]'
check "the copies match: check prints nothing" eval 'mod_check --force && [ ! -s "$SB/hook" ]'
mod_bump 2.2.0 '# orion v2'; n="$(mod_calls)"
check "a newer mod is offered once, in one JSON line, even under updateMode off" eval 'mod_check --force && hook_out_ok "$SB/hook" && [ "$(grep -o "mod install $MOD" "$SB/hook" | wc -l | tr -d " ")" = 1 ] && grep -qF "mod skip $MOD" "$SB/hook"'
check "and never taken on its own" eval '! grep -q "# orion v2" "$MKT/$MOD/README.md" && [ "$(mod_calls)" = "$n" ]'
check "mod skip declines that version: check prints nothing" eval 'mod_cmd skip "$MOD" && mod_check --force && [ ! -s "$SB/hook" ] && [ "$(mod_calls)" = "$n" ]'
mod_bump 2.3.0
check "a newer orion whose mod did not change offers nothing, and the record moves forward" eval 'mod_check --force && [ ! -s "$SB/hook" ] && [ "$(sed -n 1p "$MKT/$MOD.orion-baseline")" = 2.3.0 ]'
mod_bump 2.2.5 '# older'
check "a lower version is never offered, even when its mod differs" eval 'mod_check --force && [ ! -s "$SB/hook" ]'
mod_bump 2.4.0 '# orion v4'
check "mod install replaces the computer's copy and reinstalls the plugin" eval 'mod_check --force && grep -qF "mod install $MOD" "$SB/hook" && : > "$CALLS" && mod_cmd install "$MOD" && grep -q "# orion v4" "$MKT/$MOD/README.md" && [ "$(sed -n 1p "$CALLS")" = "plugin uninstall $MOD@orion-mods --scope user" ] && [ "$(tail -n 1 "$CALLS")" = "plugin install $MOD --marketplace $MKT --scope user" ]'
check "after the reinstall, check prints nothing" eval 'mod_check --force && [ ! -s "$SB/hook" ]'
rm -rf "$MKT/$MOD"
check "a copy deleted by hand counts as not installed: mod install puts it back" eval ': > "$CALLS" && mod_cmd install "$MOD" && [ -f "$MKT/$MOD/.claude-plugin/plugin.json" ] && [ "$(tail -n 1 "$CALLS")" = "plugin install $MOD --marketplace $MKT --scope user" ]'
n="$(mod_calls)"
check "orion uninstall leaves the computer's copy and calls no plugin command" eval 'HOME="$MDH" PATH="$MODPATH" bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ] && [ -f "$MKT/$MOD/.claude-plugin/plugin.json" ] && [ "$(mod_calls)" = "$n" ]'
check "mod remove uninstalls the plugin and deletes the computer's copy" eval ': > "$CALLS" && HOME="$MDH" PATH="$MODPATH" bash "$ORION" mod remove "$MOD" >"$SB/out" 2>&1 && grep -qxF "plugin uninstall $MOD@orion-mods --scope user" "$CALLS" && grep -qxF "plugin marketplace remove orion-mods" "$CALLS" && [ ! -e "$MKT" ]'
MDH="$SB/home-mods2"; MKT="$MDH/.claude/orion-mods"; mkdir -p "$MDH"; seen_all_personal_rules "$MDH"; rm -f "$CALLS"
newproj
check "init --mods installs every mod on this computer" eval 'HOME="$MDH" PATH="$MODPATH" bash "$ORION" init --project "$P" --yes --no-statusline --mods --update-mode off >"$SB/out" 2>&1 && [ "$(grep -c "^plugin install " "$CALLS")" = "$(ls -d "$REPO"/mods/*/ | wc -l | tr -d " ")" ] && [ -f "$MKT/$MOD.orion-baseline" ]'
cp "$P/.claude/orion/mods/$MOD.tar" "$SB/mod-before.tar"
check "an update that leaves a mod alone leaves its archive byte for byte" eval 'HOME="$MDH" PATH="$MODPATH" bash "$ORION" update --project "$P" --force >"$SB/out" 2>&1 && cmp -s "$SB/mod-before.tar" "$P/.claude/orion/mods/$MOD.tar"'
rm -rf "$P/.claude/orion/mods"
check "update at the same commit brings back the mods an older orion.sh did not copy, listed in the manifest" eval 'HOME="$MDH" PATH="$MODPATH" bash "$ORION" update --project "$P" >"$SB/out" 2>&1 && mods_copied_and_listed'
rm -rf "$MKT/$MOD"
check "mod remove takes a record whose copy was deleted by hand" eval ': > "$CALLS" && HOME="$MDH" PATH="$MODPATH" bash "$ORION" mod remove "$MOD" >"$SB/out" 2>&1 && grep -qxF "plugin uninstall $MOD@orion-mods --scope user" "$CALLS" && [ ! -e "$MKT" ]'
check "the guide page says how mods are installed, offered, skipped and removed, and the shortcut Control Tower binds" eval 'grep -qF -- "--mods" "$GUIDE" && grep -qF "mod install" "$GUIDE" && grep -qF "mod skip" "$GUIDE" && grep -qF "mod remove" "$GUIDE" && grep -qF "~/.claude/orion-mods" "$GUIDE" && grep -qF "/control-tower" "$GUIDE" && grep -qF "Ctrl+X then P to your own <code>~/.claude/keybindings.json</code>" "$GUIDE"'

summary
