#!/usr/bin/env bash
# tests/run.sh - the full suite of the orion repo: syntax checks, then orion.sh driven end to end against
# throw-away projects. Everything runs in a sandbox (its own HOME, cache and temp folder), never touches
# the network (a fake `git` answers the update check) and leaves nothing behind. One check reads the local
# origin/main ref to compare GLOBAL_CLAUDE.md's clause dates with main's: run `git fetch origin main` first (CI does).
#
# usage: bash tests/run.sh             prints one line per check, exits 1 when any check fails
#        bash tests/run.sh --windows   only the part that differs on Windows (syntax, round trip, every settings
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

# The fake git: `ls-remote` answers $FAKE_LS_SHA when set, `clone` fails when $FAKE_CLONE_FAIL=1 and hangs when
# $FAKE_CLONE_HANG=1; all else is real git. The fake cp: the first copy sleeps $FAKE_CP_SLEEP seconds when set,
# so a copy is slower than the hook's fetch limit without racing a wall clock.
cat > "$SB/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\${1:-}" = ls-remote ] && [ -n "\${FAKE_LS_SHA:-}" ]; then printf '%s\trefs/heads/main\n' "\$FAKE_LS_SHA"; exit 0; fi
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
# The fake npx: installing the status line warms a cost cache through npx, which would reach the network.
printf '#!/usr/bin/env bash\nexit 1\n' > "$SB/bin/npx"; chmod +x "$SB/bin/npx"
FAKEPATH="$SB/bin:$PATH"

N=0
newproj() { N=$((N+1)); mkdir -p "$SB/p$N"; P="$SB/p$N"; }               # sets P
init()    { bash "$ORION" init --project "$P" --no-statusline --update-mode "${1:-ask}" >"$SB/out" 2>&1; }
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
    env PATH="$FAKEPATH" TMPDIR="$SB/tmp" bash "$P/.claude/orion/orion.sh" check --project "$P" "$@" >"$SB/hook" 2>/dev/null
}
consume_marker() { bash "$ORION" verify --project "$P" >/dev/null 2>&1 || true; }   # verify clears the one-shot marker
nothing_left_in_tmp() { [ -z "$(ls -A "$SB/tmp" 2>/dev/null)" ]; }
# A personal rules file whose ORION GLOBAL section has seen every clause, so the personal rules offer stays quiet
# in the checks that expect silence; the personal rules section below uses a HOME of its own.
seen_all_personal_rules() {  # home
    mkdir -p "$1/.claude"; printf '# ORION GLOBAL — last updated 9999-12-31T23:59Z\n<!-- /ORION GLOBAL -->\n' > "$1/.claude/CLAUDE.md"
}
seen_all_personal_rules "$HOME"

echo "syntax"
check "orion.sh parses" bash -n "$ORION"
check "tests/run.sh parses" bash -n "$REPO/tests/run.sh"
check "clear-git-resources scan.sh parses" bash -n "$REPO/skills/clear-git-resources/scripts/scan.sh"
check "issue_map.py compiles" "$PY" -m py_compile "$REPO/skills/issue-map/scripts/issue_map.py"
check "build_docx.py compiles" "$PY" -m py_compile "$REPO/skills/generate-project-writeup/assets/build_docx.py"

echo "round trip (init / update / check / uninstall)"
newproj
check "init" init ask
check "update --force" eval 'bash "$ORION" update --project "$P" --force >"$SB/out" 2>&1'
check "check --force exits 0" run_check --force
check "check answers nothing or one JSON line" hook_out_ok "$SB/hook"
check "uninstall --yes" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1'
check "nothing orion owns is left" eval '[ ! -e "$P/.claude/orion" ] && [ ! -e "$P/.claude/skills" ] && ! grep -qi orion "$P/CLAUDE.md" "$P/.claude/settings.json"'

# Every settings editor (jq, python, and PowerShell where it exists) on a settings file that has a
# byte-order mark, a permission rule naming orion's script, and a hook of the project's own; and a
# CLAUDE.md that holds nothing but orion's import line.
IMPORT='Mandatory rules, owned and refreshed by orion (never edit the copy): @.claude/orion/BASE_CLAUDE.md'
tools="$PY"; command -v jq >/dev/null 2>&1 && tools="jq $tools"; command -v powershell.exe >/dev/null 2>&1 && tools="$tools powershell"
[ "$WINDOWS_ONLY" = 1 ] && check "the Windows run has PowerShell to test" eval 'command -v powershell.exe >/dev/null 2>&1'
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
    check "uninstall with a CLAUDE.md of only the import line" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1'
    check "uninstall removed the hook and kept the rest" eval '! grep -qF "orion.sh\\\" check" "$P/.claude/settings.json" && grep -qF "echo own" "$P/.claude/settings.json" && grep -qF "orion.sh status" "$P/.claude/settings.json" && json_ok "$P/.claude/settings.json"'
    check "uninstall removed the import line" eval '[ -f "$P/CLAUDE.md" ] && ! grep -qF "$IMPORT" "$P/CLAUDE.md" && [ ! -e "$P/.claude/orion" ]'
    unset ORION_JSON_TOOL
done
if [ "$WINDOWS_ONLY" = 1 ]; then summary; exit; fi

echo "check (the session-start hook: silent unless it has news, always exit 0)"
newproj; init ask
V="$(sed -n 1p "$P/.claude/orion/VERSION")"
check "first check asks for /orion-verify" eval 'run_check && grep -q orion-verify "$SB/hook" && hook_out_ok "$SB/hook"'
check "the post-install question is asked once" eval 'FAKE_LS_SHA="$V" run_check && ! grep -q orion-verify "$SB/hook"'
check "up to date: silent, exit 0" eval 'FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
check "newer orion, ask mode: one JSON line" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check --force && grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'
set_cfg updateMode '"off"'
check "off mode: silent, exit 0" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 run_check --force && [ ! -s "$SB/hook" ]'
set_cfg updateMode '"auto"'
check "failing auto-update: exit 0" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_CLONE_FAIL=1 run_check --force'
check "failing auto-update: says it failed, in one JSON line" eval 'grep -q "failed" "$SB/hook" && hook_out_ok "$SB/hook"'
check "failing auto-update: no temporary clone left behind" nothing_left_in_tmp
if command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1; then
    t0=$(date +%s)
    check "hanging auto-update: exit 0, says it failed" eval 'FAKE_LS_SHA=1111111111111111111111111111111111111111 FAKE_CLONE_HANG=1 run_check --force && grep -q "failed" "$SB/hook" && hook_out_ok "$SB/hook"'
    check "hanging auto-update: ends soon after the 10 s fetch limit" eval '[ $(( $(date +%s) - t0 )) -lt 20 ]'
    check "hanging auto-update: no temporary clone left behind" nothing_left_in_tmp
fi
# a working auto-update, from a local source repository
SRC="$SB/src"; mkdir -p "$SRC"; cp -R "$REPO/orion.sh" "$REPO/skills" "$REPO/baselines" "$SRC/"
"$REAL_GIT" -C "$SRC" init -q -b main && "$REAL_GIT" -C "$SRC" -c core.autocrlf=false add . && "$REAL_GIT" -C "$SRC" commit -qm src
SRC_SHA="$("$REAL_GIT" -C "$SRC" rev-parse HEAD)"
bash "$ORION" init --project "$P" --source "$SRC" --no-statusline >"$SB/out" 2>&1; cp "$SB/out" "$SB/out-reinit"; consume_marker
check "re-init with a new --source changes config.json and says so" eval 'grep -q "source changed" "$SB/out-reinit" && bash "$ORION" status --project "$P" | grep -qF "$SRC"'
# The first copy sleeps 11 s, longer than the 10 s fetch limit: only the fetch may be time-limited, never the copy.
rm -f "$SB/cp-slept"
check "working auto-update with a copy slower than the fetch limit: exit 0 and says so" eval 'FAKE_CP_SLEEP=11 run_check --force && grep -q "updated automatically" "$SB/hook" && hook_out_ok "$SB/hook"'
check "working auto-update: the slow copy really ran" eval '[ -e "$SB/cp-slept" ]'
check "working auto-update: every file of every skill was copied" eval '[ "$(cd "$SRC/skills" && find . -mindepth 2 -type f | grep -v /__pycache__/ | sort)" = "$(cd "$P/.claude/skills" && find . -mindepth 2 -type f ! -name .orion-managed | sort)" ]'
check "working auto-update: the project is now at the source commit" eval '[ "$(sed -n 1p "$P/.claude/orion/VERSION")" = "$SRC_SHA" ]'
check "working auto-update: no temporary clone left behind" nothing_left_in_tmp

echo "upgrade from an install whose hook still has the old 20 s limit"
# The older script, as far as this matters: it writes a 20 s hook and never raises it. CI checks out no
# history, so it is made from today's script rather than taken from git.
mkdir -p "$SB/old"; OLD="$SB/old/orion.sh"
awk '/^HOOK_TIMEOUT=60$/ { print "HOOK_TIMEOUT=20"; next }
     /^settings_raise_hook_timeout\(\) \{/ { print "settings_raise_hook_timeout() { :; }"; print "settings_raise_hook_timeout_unused() {"; next }
     { print }' "$ORION" > "$OLD"
newproj
bash "$OLD" init --project "$P" --source "$SRC" --no-statusline --update-mode auto >"$SB/out" 2>&1; consume_marker
check "the older script installs a 20 s hook" eval '[ "$(hook_timeouts "$P/.claude/settings.json")" = 20 ]'
check "an update run by the older script leaves it at 20 s" eval 'bash "$OLD" update --project "$P" --force >"$SB/out" 2>&1 && [ "$(hook_timeouts "$P/.claude/settings.json")" = 20 ]'
{ printf '%s\n' 0000000000000000000000000000000000000000; sed -n '2,$p' "$P/.claude/orion/VERSION"; } > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
rm -f "$SB/cp-slept"
check "on that 20 s session the whole auto-update stays capped at 10 s: exit 0, says it failed" eval 'FAKE_CP_SLEEP=11 run_check --force && grep -q "failed" "$SB/hook" && hook_out_ok "$SB/hook"'
check "and that first check by the new script raised the hook to 60 s" eval '[ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'
check "and left no temporary clone behind" nothing_left_in_tmp
check "the next session's auto-update runs to the end" eval 'run_check --force && grep -q "updated automatically" "$SB/hook" && [ "$(sed -n 1p "$P/.claude/orion/VERSION")" = "$SRC_SHA" ]'
set_old_hook_timeout "$P/.claude/settings.json"; set_cfg updateMode '"ask"'
check "with nothing new, check heals a 20 s hook and stays silent" eval 'FAKE_LS_SHA="$SRC_SHA" run_check --force && [ ! -s "$SB/hook" ] && [ "$(hook_timeouts "$P/.claude/settings.json")" = 60 ]'

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
check "a computer that never checked these rules asks (a teammate after a pull)" eval 'XDG_CACHE_HOME="$SB/cache-mate" FAKE_LS_SHA="$V" run_check --force && asked_rules'
check "verify records the rules it checked" eval 'XDG_CACHE_HOME="$SB/cache-mate2" bash "$ORION" verify --project "$P" >/dev/null 2>&1; XDG_CACHE_HOME="$SB/cache-mate2" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
rm -rf "$P/.claude/skills/orion-verify"
check "without the /orion-verify skill nothing is asked" eval 'XDG_CACHE_HOME="$SB/cache-mate3" FAKE_LS_SHA="$V" run_check --force && [ ! -s "$SB/hook" ]'
newproj; bash "$ORION" init --project "$P" --source "$SRC" --no-statusline >"$SB/out" 2>&1; consume_marker
printf '\n- a newer rule\n' >> "$SRC/baselines/BASE_CLAUDE.md"; "$REAL_GIT" -C "$SRC" -c core.autocrlf=false commit -qam rules
check "an update that changes the rules says to run /orion-verify" eval 'bash "$P/.claude/orion/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "run /orion-verify" "$SB/out"'
consume_marker
printf '\n# a comment\n' >> "$SRC/skills/issue-map/scripts/issue_map.py"; "$REAL_GIT" -C "$SRC" -c core.autocrlf=false commit -qam script
check "an update that leaves the rules alone does not" eval 'bash "$P/.claude/orion/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "orion update" "$SB/out" && ! grep -q "run /orion-verify" "$SB/out"'
printf '\n- the newest rule\n' >> "$SRC/baselines/BASE_CLAUDE.md"; "$REAL_GIT" -C "$SRC" -c core.autocrlf=false commit -qam rules2
set_cfg updateMode '"auto"'
check "an auto-update that changes the rules asks for /orion-verify in the same session, one JSON line" eval 'run_check --force && grep -q "updated automatically" "$SB/hook" && asked_rules && hook_out_ok "$SB/hook"'

echo "branch counter (hook and scanner count the same, two remotes)"
newproj; "$REAL_GIT" -C "$P" init -q -b main; "$REAL_GIT" -C "$P" commit -q --allow-empty -m one
for b in b1 b2 b3; do "$REAL_GIT" -C "$P" branch "$b"; done
"$REAL_GIT" -C "$P" remote add origin https://example.invalid/a.git; "$REAL_GIT" -C "$P" remote add other https://example.invalid/b.git
for r in origin/main origin/f1 other/f2; do "$REAL_GIT" -C "$P" update-ref "refs/remotes/$r" HEAD; done
"$REAL_GIT" -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
init off; consume_marker; set_cfg branchLimit 7
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
newproj; rmdir "$P"; "$REAL_GIT" clone -q -b main "$R" "$P"; init off; consume_marker
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
rm -f "$P/.claude/orion/BASE_CLAUDE.md"
check "verify fails when a core file is missing" eval '! bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "FAIL  core-files" "$SB/out"'
newproj; init ask; rm -f "$P/.claude/orion/global/GLOBAL_CLAUDE.md"
check "verify fails when the project copy of GLOBAL_CLAUDE.md is missing" eval '! bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "FAIL  core-files.*GLOBAL_CLAUDE.md" "$SB/out"'

echo "personal rules (GLOBAL_CLAUDE.md is offered clause by clause; orion never writes the person's own file)"
GLOBAL="$REPO/baselines/global/GLOBAL_CLAUDE.md"
STAMP_RE='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]Z'
# One line per clause (every bullet or numbered item below the first "## " heading): "<date> <text>", or "BAD <line>"
# for a clause without a valid date marker and for any other text among the clauses.
clauses() {  # file
    tr -d '\r' < "$1" | awk '
        /^## / { s = 1; next }
        !s || /^#/ || NF == 0 { next }
        /^([-*]|[0-9]+\.) / && match($0, / <!-- orion:[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]Z -->$/) {
            print substr($0, RSTART + 12, 17) " " substr($0, 1, RSTART - 1); next }
        { print "BAD " $0 }'
}
check "GLOBAL_CLAUDE.md has clauses, each carrying a valid date marker" eval '[ -n "$(clauses "$GLOBAL")" ] && ! clauses "$GLOBAL" | grep -q "^BAD "'
check "no clause is dated in the future (it would be offered again every day)" eval '[ -z "$(clauses "$GLOBAL" | awk -v now="$(date -u +%Y-%m-%dT%H:%MZ)" '"'"'$1 > now'"'"')" ]'
# A clause changed or added against origin/main must carry a date newer than every clause there, or a person who
# went through the old file would never be offered it. CI fetches origin/main before the suite.
changed_clauses_are_newer() {
    local old="$SB/global-main" newest
    "$REAL_GIT" -C "$REPO" rev-parse -q --verify origin/main >/dev/null || { echo "    origin/main not found: fetch it first"; return 1; }
    "$REAL_GIT" -C "$REPO" show origin/main:baselines/global/GLOBAL_CLAUDE.md > "$old" 2>/dev/null || return 0   # new file: every clause is new
    newest="$(clauses "$old" | cut -d' ' -f1 | grep -x "$STAMP_RE" | LC_ALL=C sort | tail -n1)"
    clauses "$old" | cut -d' ' -f2- > "$SB/global-main-texts"
    clauses "$GLOBAL" | while IFS=' ' read -r d text; do
        grep -qxF -- "$text" "$SB/global-main-texts" && continue
        [[ "$d" > "$newest" ]] || { echo "    changed clause not dated after $newest: $text"; exit 1; }
    done
}
check "every clause changed against origin/main is dated after every clause there" changed_clauses_are_newer
GH="$SB/home-global"; mkdir -p "$GH"; PERSONAL="$GH/.claude/CLAUDE.md"
NEWEST="$(clauses "$GLOBAL" | cut -d' ' -f1 | LC_ALL=C sort | tail -n1)"
gl_check() { HOME="$GH" run_check "$@"; }
asked_global() { grep -q "GLOBAL_CLAUDE.md" "$SB/hook"; }
section() { mkdir -p "$GH/.claude"; printf '# my own rules\n\n- keep this\n\n# ORION GLOBAL — last updated %s\n<!-- /ORION GLOBAL -->\n' "$1" > "$PERSONAL"; }
newproj; HOME="$GH" init ask
check "right after init, the post-install message also offers the discussion" eval 'gl_check && grep -q orion-verify "$SB/hook" && asked_global && hook_out_ok "$SB/hook"'
check "the project carries GLOBAL_CLAUDE.md, listed in the manifest" eval '[ -f "$P/.claude/orion/global/GLOBAL_CLAUDE.md" ] && grep -qx "global/GLOBAL_CLAUDE.md" "$P/.claude/orion/.orion-manifest"'
check "no ORION GLOBAL section yet: the discussion is offered, in one JSON line" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && hook_out_ok "$SB/hook"'
check "and the hook wrote no personal rules file" eval '[ ! -e "$PERSONAL" ]'
check "it is offered once a day per computer" eval 'FAKE_LS_SHA="$V" gl_check && ! asked_global'
printf '%s' "$(( $(date +%s) - 86401 ))" > "$XDG_CACHE_HOME/orion/global-offered"
check "and offered again once that day has passed" eval 'FAKE_LS_SHA="$V" gl_check && asked_global && hook_out_ok "$SB/hook"'
section 2000-01-01T00:00Z
check "a clause newer than the section's timestamp is offered" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && hook_out_ok "$SB/hook"'
section "$NEWEST"
check "every clause as old as the timestamp or older: silent" eval 'FAKE_LS_SHA="$V" gl_check --force && [ ! -s "$SB/hook" ]'
section 2000-01-01T00:00Z; set_cfg updateMode '"off"'
check "off mode never offers it" eval 'gl_check --force && [ ! -s "$SB/hook" ]'
newproj; HOME="$GH" init off
check "nor does the post-install message under off" eval 'gl_check && grep -q orion-verify "$SB/hook" && ! asked_global'
set_cfg updateMode '"auto"'; cp "$PERSONAL" "$SB/personal-before"
check "auto mode only offers it and never writes the person's file" eval 'FAKE_LS_SHA="$V" gl_check --force && asked_global && cmp -s "$SB/personal-before" "$PERSONAL"'
check "uninstall leaves the person's file byte for byte as it was" eval 'HOME="$GH" bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ] && cmp -s "$SB/personal-before" "$PERSONAL"'

echo "config, manifest and copies"
newproj
bash "$ORION" init --project "$P" --source 'C:\some\orion' --no-statusline >"$SB/out" 2>&1
check "a Windows path as --source keeps config.json valid JSON" json_ok "$P/.claude/orion/config.json"
check "and reads back unchanged" eval 'bash "$ORION" status --project "$P" | grep -qF "source:     C:\\some\\orion"'
check "no __pycache__ is copied into the project" eval '[ -z "$(find "$P/.claude/skills" -name __pycache__)" ]'
awk '{printf "%s\r\n", $0}' "$P/.claude/orion/.orion-manifest" > "$SB/m" && mv "$SB/m" "$P/.claude/orion/.orion-manifest"
check "uninstall with Windows line endings in the manifest removes everything" eval 'bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ]'

echo "status line (the project carries orion's copy; the computer's copy takes the newest only on the person's word)"
# A computer of its own (HOME) and a source repository of its own, with commit times set by hand so "newer" is certain.
SLH="$SB/home-sl"; SLFILE="$SLH/.claude/statusline/statusline.sh"; mkdir -p "$SLH" "$SB/home-none"; seen_all_personal_rules "$SLH"
SLSRC="$SB/sl-src"; mkdir -p "$SLSRC"; cp -R "$REPO/orion.sh" "$REPO/skills" "$REPO/baselines" "$SLSRC/"
sl_commit() { ( cd "$SLSRC" && "$REAL_GIT" -c core.autocrlf=false add . && GIT_COMMITTER_DATE="$1" GIT_AUTHOR_DATE="$1" "$REAL_GIT" commit -qm "$1" ); }
sl_release() {  # date line text: a new orion release whose status line gains <text> after line <line>
    local f="$SLSRC/baselines/statusline/statusline.sh"
    awk -v n="$2" -v t="$3" '{ print } NR == n { print t }' "$f" > "$SB/sl" && cat "$SB/sl" > "$f"; sl_commit "$1"
}
sl_put() {  # dir time: the project's copy as a teammate's git pull brings it
    rm -rf "$P/.claude/orion/statusline"; cp -R "$1" "$P/.claude/orion/statusline"
    { sed -n '1,3p' "$P/.claude/orion/VERSION"; printf '%s\n' "$2"; } > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
}
sl_pull() { sl_put "$SLSRC/baselines/statusline" "$("$REAL_GIT" -C "$SLSRC" log -1 --format=%ct)"; }
sl_check() { HOME="$SLH" run_check "$@"; }
sl_cmd() { HOME="$SLH" bash "$P/.claude/orion/orion.sh" statusline "$1" --project "$P" >"$SB/out" 2>&1; }
"$REAL_GIT" -C "$SLSRC" init -q -b main; sl_commit 2026-01-01T00:00:00Z
newproj
check "init --statusline seeds the computer's copy and its merge base" eval 'HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" init --project "$P" --statusline --update-mode off >"$SB/out" 2>&1 && [ -f "$SLFILE" ] && [ -f "$SLH/.claude/statusline/.orion-base/statusline.sh" ]'
consume_marker
check "the project carries orion's status line, listed in the manifest" eval '[ -f "$P/.claude/orion/statusline/statusline.sh" ] && grep -qx "statusline/statusline.sh" "$P/.claude/orion/.orion-manifest"'
check "VERSION records the source's commit time" eval '[ "$(sed -n 4p "$P/.claude/orion/VERSION")" = "$("$REAL_GIT" -C "$SLSRC" log -1 --format=%ct)" ]'
check "same baseline: check is silent" eval 'sl_check --force && [ ! -s "$SB/hook" ]'
cp -R "$P/.claude/orion/statusline" "$SB/sl-v1"; T1="$(sed -n 4p "$P/.claude/orion/VERSION")"
sl_release 2026-02-01T00:00:00Z 2 '# orion v2'; sl_pull
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
sl_release 2026-03-01T00:00:00Z 2 '# orion v3'; sl_pull
check "an edited copy is not replaced: check offers the merge in one JSON line" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && hook_out_ok "$SB/hook" && ! grep -q "^# orion v3" "$SLFILE"'
check "statusline merge keeps the edits and takes orion's changes" eval 'sl_cmd merge && grep -q "^# orion v3" "$SLFILE" && grep -q "^# mine" "$SLFILE" && ! grep -q "<<<<<<<" "$SLFILE"'
check "after the merge, check is silent" eval 'sl_check --force && [ ! -s "$SB/hook" ]'
sl_release 2026-04-01T00:00:00Z 2 '# orion v4'; sl_pull
check "statusline skip keeps the copy as it is" eval 'sl_cmd skip && ! grep -q "^# orion v4" "$SLFILE" && grep -q "^# mine" "$SLFILE"'
check "and that baseline is not offered again" eval 'sl_check --force && [ ! -s "$SB/hook" ]'
check "merge from a project no newer than the computer's copy changes nothing" eval 'cp "$SLFILE" "$SB/before" && sl_cmd merge && grep -q "nothing to" "$SB/out" && cmp -s "$SB/before" "$SLFILE"'
sl_put "$SB/sl-v1" "$T1"
check "skip from an older project never steps the stamp back" eval 'sl_cmd skip; sl_pull && sl_check --force && [ ! -s "$SB/hook" ]'
printf 'x\n' > "$SLSRC/unrelated.txt"; sl_commit 2026-04-15T00:00:00Z; sl_pull
check "a release that leaves the status line alone does not offer a merge" eval 'sl_check --force && [ ! -s "$SB/hook" ] && [ "$(sed -n 1p "$SLH/.claude/statusline/.orion-baseline")" = "$(sed -n 4p "$P/.claude/orion/VERSION")" ]'
printf '# mine at the end\n' >> "$SLFILE"
sl_release 2026-05-01T00:00:00Z "$(wc -l < "$SLSRC/baselines/statusline/statusline.sh" | tr -d ' ')" '# orion v5 at the end'; sl_pull
check "a clashing edit: merge names the file to fix and exits 1" eval '! sl_cmd merge && grep -q "statusline.sh" "$SB/out" && grep -q "<<<<<<<" "$SLFILE"'
# A copy installed before orion kept a merge base: no .orion-base, and a stamp reading "orion".
rm -rf "$SLH/.claude/statusline/.orion-base"; printf 'orion' > "$SLH/.claude/statusline/.orion-baseline"
check "an older install that differs is offered the merge too" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && hook_out_ok "$SB/hook"'
check "and its merge saves the old copy to statusline.bak, then takes orion's" eval 'sl_cmd merge && grep -q "<<<<<<<" "$SLH/.claude/statusline.bak/statusline.sh" && [ "$(tr -d "\r" < "$P/.claude/orion/statusline/statusline.sh")" = "$(cat "$SLFILE")" ]'
rm -rf "$SLH/.claude/statusline/.orion-base"; printf 'orion' > "$SLH/.claude/statusline/.orion-baseline"
check "an older install that matches is adopted silently" eval 'sl_check --force && [ ! -s "$SB/hook" ] && [ -f "$SLH/.claude/statusline/.orion-base/statusline.sh" ]'
printf 'k=v\n' > "$SLH/.claude/statusline/.mine"
sl_release 2026-05-15T00:00:00Z 2 '# orion v5b'; sl_pull
check "a dot file of the person's own counts as an edit and is never deleted" eval 'sl_check --force && grep -q "statusline merge" "$SB/hook" && [ -f "$SLH/.claude/statusline/.mine" ]'
check "a merge takes orion's changes and keeps that dot file" eval 'sl_cmd merge && grep -q "^# orion v5b" "$SLFILE" && [ -f "$SLH/.claude/statusline/.mine" ]'
rm -f "$SLH/.claude/statusline/.mine"
printf 'old\n' > "$SLSRC/baselines/statusline/dropped.txt"; sl_commit 2026-05-20T00:00:00Z; sl_pull; sl_cmd merge
rm -f "$SLSRC/baselines/statusline/dropped.txt"; sl_release 2026-05-25T00:00:00Z 2 '# orion v5c'; sl_pull
check "a merge removes an unchanged file orion dropped" eval '[ -f "$SLH/.claude/statusline/dropped.txt" ] && sl_cmd merge && [ ! -e "$SLH/.claude/statusline/dropped.txt" ] && grep -q "^# orion v5c" "$SLFILE"'
# An install made by an older orion.sh: no status line copy in the project and no commit time in VERSION.
HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1
rm -rf "$P/.claude/orion/statusline"; sed -n '1,3p' "$P/.claude/orion/VERSION" > "$SB/v" && mv "$SB/v" "$P/.claude/orion/VERSION"
check "update at the same commit still adds what an older orion.sh did not copy" eval 'HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1 && [ -f "$P/.claude/orion/statusline/statusline.sh" ] && [ -n "$(sed -n 4p "$P/.claude/orion/VERSION")" ]'
rm -rf "$P/.claude/orion/statusline"; set_cfg updateMode '"ask"'
check "check offers the update to a project an older orion.sh updated, though the commit is the same" eval 'FAKE_LS_SHA="$(sed -n 1p "$P/.claude/orion/VERSION")" sl_check --force && grep -q "newer orion" "$SB/hook" && hook_out_ok "$SB/hook"'
set_cfg updateMode '"off"'; HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1
: > "$SLH/.claude/statusline/.DS_Store"
sl_release 2026-05-26T00:00:00Z 2 '# orion v5d'; sl_pull
check "a file the system drops in the folder (.DS_Store) is not an edit" eval 'sl_check --force && grep -q "Take it" "$SB/hook" && sl_cmd merge && grep -q "^# orion v5d" "$SLFILE"'
mv "$SLH/.claude/statusline" "$SLH/.claude/statusline.old"
sl_release 2026-05-27T00:00:00Z 2 '# orion v5e'; sl_pull
check "a replace cut short half-way is restored, then offered the new one" eval 'sl_check --force && [ ! -e "$SLH/.claude/statusline.old" ] && [ -f "$SLFILE" ] && grep -q "Take it" "$SB/hook" && sl_cmd merge && grep -q "^# orion v5e" "$SLFILE"'
rm -f "$SLH/.claude/statusline/README.md"
sl_release 2026-05-28T00:00:00Z 2 '# orion v5f'; sl_pull
check "a file the person deleted and orion left alone stays deleted on merge" eval 'sl_cmd merge && [ ! -e "$SLH/.claude/statusline/README.md" ] && grep -q "^# orion v5f" "$SLFILE"'
cp "$SLH/.claude/statusline/.orion-base/README.md" "$SLH/.claude/statusline/README.md"   # unedited again for the tests below
# a baseline with a sub-folder, so uninstall below must remove more than flat files
mkdir -p "$SLSRC/baselines/statusline/sub"; printf 'x\n' > "$SLSRC/baselines/statusline/sub/f.txt"; sl_commit 2026-05-30T00:00:00Z
sl_release 2026-06-01T00:00:00Z 2 '# orion v6'
check "update says a newer status line waits and leaves an unedited copy alone" eval 'HOME="$SLH" PATH="$FAKEPATH" bash "$SLSRC/orion.sh" update --project "$P" >"$SB/out" 2>&1 && grep -q "statusline merge" "$SB/out" && ! grep -q "^# orion v6" "$SLFILE"'
check "a computer without orion's status line gets none from check" eval 'HOME="$SB/home-none" run_check --force && [ ! -e "$SB/home-none/.claude/statusline" ]'
check "uninstall removes the project's copy and leaves the computer's" eval 'HOME="$SLH" bash "$ORION" uninstall --project "$P" --yes >"$SB/out" 2>&1 && [ ! -e "$P/.claude/orion" ] && [ -f "$SLFILE" ]'

summary
