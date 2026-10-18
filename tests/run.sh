#!/usr/bin/env bash
# tests/run.sh - the full suite of the orion repo: syntax checks, then orion.sh driven end to end against
# throw-away projects. Everything runs in a sandbox (its own HOME, cache and temp folder), never touches
# the network (a fake `git` answers the update check) and leaves nothing behind.
#
# usage: bash tests/run.sh          prints one line per check, exits 1 when any check fails
#
# Portable bash: runs under Git Bash, macOS bash and Linux. No GNU-only flags.

set -u

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ORION="$REPO/orion.sh"
PASS=0 FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
check() { local what="$1"; shift; if "$@"; then ok "$what"; else bad "$what"; fi; }

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

echo "branch counter (hook and scanner count the same, two remotes)"
newproj; "$REAL_GIT" -C "$P" init -q -b main; "$REAL_GIT" -C "$P" commit -q --allow-empty -m one
for b in b1 b2 b3; do "$REAL_GIT" -C "$P" branch "$b"; done
"$REAL_GIT" -C "$P" remote add origin https://example.invalid/a.git; "$REAL_GIT" -C "$P" remote add other https://example.invalid/b.git
for r in origin/main origin/f1 other/f2; do "$REAL_GIT" -C "$P" update-ref "refs/remotes/$r" HEAD; done
"$REAL_GIT" -C "$P" symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main
init off; consume_marker; set_cfg branchLimit 7
check "the hook offers the tidy-up at 7 branches" eval 'run_check --force && grep -q "has 7 git branches" "$SB/hook" && hook_out_ok "$SB/hook"'
check "the scanner counts 7 too" eval 'bash "$REPO/skills/clear-git-resources/scripts/scan.sh" --project "$P" --wt-root "$SB/wt" --limit 7 | grep -q "total=7 limit=7 over=yes"'
check "status shows the branch count" eval 'bash "$ORION" status --project "$P" | grep -q "branches now: 7"'
set_cfg branchLimit 8
check "below the limit: silent" eval 'run_check --force && [ ! -s "$SB/hook" ]'

echo "verify"
newproj; init ask
check "verify passes after init" eval 'bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "verify: 0 fail" "$SB/out"'
rm -f "$P/.claude/orion/BASE_CLAUDE.md"
check "verify fails when a core file is missing" eval '! bash "$ORION" verify --project "$P" >"$SB/out" 2>&1 && grep -q "FAIL  core-files" "$SB/out"'

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
SLH="$SB/home-sl"; SLFILE="$SLH/.claude/statusline/statusline.sh"; mkdir -p "$SLH" "$SB/home-none"
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
awk '{ printf "%s
", $0 }' "$SLFILE" > "$SB/crlf" && cat "$SB/crlf" > "$SLFILE"   # saved by a Windows editor: still unedited
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

echo "suite: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
