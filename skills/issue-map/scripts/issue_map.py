"""Build docs/issue_map/issue_map.html: the live blocked-by graph of every GitHub issue, level by level.

Reads the issues of the repository `origin` points at through `gh` (the GitHub CLI) at the moment it runs and
writes one self-contained HTML file to docs/issue_map/ in the MAIN checkout (never a worktree, so every terminal
writes the same file). The file is a transient snapshot: it is excluded from git locally (`.git/info/exclude`),
never committed, and carries a banner saying who built it and when. Rebuild it with `/issue-map`.

    python .claude/skills/issue-map/scripts/issue_map.py            # rebuild the map, print its path
    python .claude/skills/issue-map/scripts/issue_map.py --open     # rebuild, then open it in the default browser
    python .claude/skills/issue-map/scripts/issue_map.py --silent   # rebuild only (what /dev-next calls)

Needs Python 3.9+ and `gh` signed in. No third-party packages.

Mechanic (the same rules as the work-tracking section of BASE_CLAUDE.md):
- Nodes: every issue, open and closed, of any label. Epics (label `epic`) sit in their own far-left column,
  outside the levels, coloured purple; an epic is tied to its stories by GitHub's native sub-issue link,
  drawn as a dashed purple line and named in the epic tag on each story. Epics and closed issues start hidden.
- Links: the union of GitHub's native blocked-by relation and the `### Blocked by` body section.
  Nothing else is a link. A link to an epic or to an issue that does not exist is dropped and reported in
  the footer; so is a link that closes a cycle.
- Level: 0 when an issue has no link, else 1 + the highest level among its blockers. Closed blockers
  count; labels never change a level. The columns are the levels.
"""

from __future__ import annotations

import datetime
import html
import json
import os
import re
import subprocess
import sys
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
REL_OUT = Path("docs") / "issue_map" / "issue_map.html"


def find_root() -> Path:
    """The main checkout of the repository the current directory belongs to.

    `git rev-parse --git-common-dir` points at the shared `.git` folder even from a worktree, so the map always lands
    in the main checkout. Outside any repository, fall back to the repository this script was installed into
    (scripts/ -> issue-map/ -> skills/ -> .claude/ -> repository root).
    """
    try:
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True,
                                check=True, encoding="utf-8").stdout.strip()
        common_path = Path(common).resolve()
        if common_path.name == ".git":
            return common_path.parent
    except (subprocess.CalledProcessError, FileNotFoundError):
        pass
    return HERE.parents[3]


ROOT = find_root()
OUT = ROOT / REL_OUT


def gh(*args: str) -> str:
    return subprocess.run(["gh", *args], capture_output=True, text=True, check=True, encoding="utf-8",
                          cwd=ROOT).stdout


def ensure_excluded() -> None:
    """Keep the snapshot out of git without touching the project's .gitignore: `.git/info/exclude` is per clone."""
    try:
        ignored = subprocess.run(["git", "check-ignore", "-q", str(REL_OUT.as_posix())], cwd=ROOT,
                                 capture_output=True).returncode == 0
        if ignored:
            return
        common = subprocess.run(["git", "rev-parse", "--git-common-dir"], capture_output=True, text=True,
                                check=True, encoding="utf-8", cwd=ROOT).stdout.strip()
        exclude = (ROOT / common).resolve() / "info" / "exclude"
        exclude.parent.mkdir(parents=True, exist_ok=True)
        existing = exclude.read_text(encoding="utf-8") if exclude.exists() else ""
        line = REL_OUT.as_posix()
        if line not in existing.splitlines():
            with exclude.open("a", encoding="utf-8") as f:
                f.write(("" if existing.endswith("\n") or not existing else "\n")
                        + "# issue map: transient, built locally by /issue-map, never committed\n" + line + "\n")
    except (subprocess.CalledProcessError, FileNotFoundError, OSError):
        pass  # not a git repository, or git missing: nothing to exclude


def main() -> None:
    try:
        issues = json.loads(gh("issue", "list", "--state", "all", "--limit", "1000", "--json",
                               "number,title,state,labels,assignees,body"))
    except FileNotFoundError:
        sys.exit("issue-map: `gh` (the GitHub CLI) is not installed or not on PATH; nothing rebuilt")
    except subprocess.CalledProcessError as e:
        reason = (e.stderr or "").strip().splitlines()
        sys.exit("issue-map: `gh issue list` failed (not signed in, no network, or no GitHub remote)"
                 + (": " + reason[-1] if reason else ""))
    d = {i["number"]: i for i in issues}
    repo = json.loads(gh("repo", "view", "--json", "name,url"))
    repo_name, repo_url = repo["name"], repo["url"] + "/issues/"
    try:
        user = gh("api", "user", "--jq", ".login").strip()
    except subprocess.CalledProcessError:
        user = subprocess.run(["git", "config", "user.name"], capture_output=True, text=True,
                              cwd=ROOT).stdout.strip() or "unknown"
    stamp = datetime.datetime.now().astimezone().strftime("%d %b %Y %H:%M %Z")

    def labels(n: int) -> set[str]:
        return {lab["name"] for lab in d[n]["labels"]} if n in d else set()

    def st(n: int) -> str:
        return d[n]["state"] if n in d else "UNKNOWN"

    def title(n: int) -> str:
        return d[n]["title"] if n in d else "(issue not loaded)"

    def body_blockers(b: str | None) -> list[int]:
        m = re.search(r"### Blocked by\s*\n(.*?)(?=\n#{1,6} |\Z)", b or "", re.S)
        return sorted({int(x) for x in re.findall(r"#(\d+)", m.group(1))}) if m else []

    stories = {n for n in d if "story" in labels(n)}
    epics = sorted(n for n in d if "epic" in labels(n))
    nodes = {n for n in d if "epic" not in labels(n)}
    # epic -> its stories, from the native sub-issue link
    kids: dict[int, list[int]] = {}
    for e in epics:
        kids[e] = sorted(k for k in json.loads(gh("api", f"repos/{{owner}}/{{repo}}/issues/{e}/sub_issues?per_page=100",
                                                  "--jq", "map(.number)") or "[]") if k in nodes)
    parent = {k: e for e in epics for k in kids[e]}
    native: dict[int, list[int]] = {}
    for n in sorted(nodes):
        native[n] = json.loads(gh("api", f"repos/{{owner}}/{{repo}}/issues/{n}/dependencies/blocked_by",
                                  "--jq", "map(.number)") or "[]")
    raw = {n: sorted(set(body_blockers(d[n]["body"])) | set(native[n])) for n in nodes}
    # a link to an epic, or to an issue that is not loaded, is a data problem: dropped and reported
    bad_links = sorted((n, b) for n in nodes for b in raw[n] if b not in nodes)
    blk = {n: [b for b in raw[n] if b in nodes] for n in nodes}
    mism = [n for n in nodes if st(n) == "OPEN" and set(body_blockers(d[n]["body"])) != set(native[n])]

    # Level: 0 with no link, else 1 + the highest level among the blockers. A link that closes a cycle is
    # dropped (and reported) so the recursion ends.
    cyc_links: list[tuple[int, int]] = []
    lvl: dict[int, int] = {}
    visiting: set[int] = set()

    def depth(n: int) -> int:
        if n in lvl:
            return lvl[n]
        visiting.add(n)
        best = 0
        for b in list(blk[n]):
            if b in visiting:
                cyc_links.append((n, b))
                blk[n].remove(b)
                continue
            best = max(best, 1 + depth(b))
        visiting.discard(n)
        lvl[n] = best
        return best

    for n in sorted(nodes):
        depth(n)

    # Axis 1: progress -> icon; a closed issue gets a red cross over the box instead of an icon
    STATUS = {
        "closed": ("", "Closed", "merged and closed, nothing left to do (red cross over the box)"),
        "inprog": ("🔨", "In progress", "somebody has claimed it and is building it now"),
        "ready": ("🟢", "Ready to take", "open, nobody on it, every blocker closed"),
        "blocked": ("🔒", "Blocked", "at least one blocker (a red line coming in) is still open"),
    }
    # Axis 2: who takes it (the readiness label) -> background colour
    KIND = {
        "agent": ("", "agent-ready", "green: nothing left to ask, an agent can claim and build it"),
        "human": ("", "needs-human", "red: a person must act or decide first (reason in the last comment)"),
        "outside": ("", "outside-change", "blue: a repository this team does not own; ends at a pull request for its own reviewer"),
        "decision": ("", "anything else", "yellow: no readiness label (planning, decision, docs)"),
        "epic": ("", "epic", "purple: an epic, far-left column; click it to see its stories"),
    }

    def status(n: int) -> str:
        if st(n) == "CLOSED":
            return "closed"
        if d[n]["assignees"]:
            return "inprog"
        if any(st(b) != "CLOSED" for b in blk.get(n, [])):
            return "blocked"
        return "ready"

    def kind(n: int) -> str:
        lab = labels(n)
        if "epic" in lab:
            return "epic"
        if "outside-change" in lab:
            return "outside"
        if "needs-human" in lab:
            return "human"
        if "agent-ready" in lab:
            return "agent"
        return "decision"

    # Columns: one per level; order inside a column by the barycentre of neighbours to limit crossings.
    cols: dict[int, list[int]] = {}
    for n in nodes:
        cols.setdefault(depth(n), []).append(n)
    pos: dict[int, int] = {}
    for k in sorted(cols):
        cols[k].sort(key=lambda n: (st(n) == "CLOSED", n))  # closed issues always at the bottom
        for i, n in enumerate(cols[k]):
            pos[n] = i
    for _ in range(6):
        for k in sorted(cols):
            if k == 0:
                continue

            def bary(n: int, k: int = k) -> tuple[bool, float, int]:
                bs = [pos[b] for b in blk[n] if depth(b) < k]
                return (st(n) == "CLOSED", sum(bs) / len(bs) if bs else pos[n], n)

            cols[k].sort(key=bary)
            for i, n in enumerate(cols[k]):
                pos[n] = i
        for k in sorted(cols, reverse=True):
            succ = {n: [m for m in nodes if n in blk[m] and depth(m) > k] for n in cols[k]}

            def bary2(n: int) -> tuple[bool, float, int]:
                ss = [pos[m] for m in succ[n]]
                return (st(n) == "CLOSED", sum(ss) / len(ss) if ss else pos[n], n)

            cols[k].sort(key=bary2)
            for i, n in enumerate(cols[k]):
                pos[n] = i

    W, H, GX, GY, PAD, TOP = 220, 60, 70, 14, 30, 70
    maxrows = max((len(c) for c in cols.values()), default=1)
    epics.sort(key=lambda n: (st(n) == "CLOSED", n))  # closed epics at the bottom, like the levels
    column_list = ([("Epics", epics)] if epics else []) + [(f"Level {k}", cols[k]) for k in sorted(cols)]
    maxrows = max(maxrows, len(epics), 1)
    colname: dict[int, str] = {}
    height = TOP + maxrows * (H + GY) + PAD
    xy: dict[int, tuple[float, float]] = {}
    for j, (name, members) in enumerate(column_list):
        cx = float(PAD + j * (W + GX))
        off = (maxrows - len(members)) * (H + GY) / 2
        for i, n in enumerate(members):
            xy[n] = (cx, TOP + off + i * (H + GY))
            colname[n] = name
    width = PAD * 2 + max(len(column_list), 1) * (W + GX) - GX

    # Titles may carry an "E<N> · " / "Epic <N> · " prefix that names the epic; the tag shows it, the box title drops it.
    def short(n: int) -> str:
        t = re.sub(r"^(E|Epic )\d+ · ", "", title(n))
        return t if len(t) <= 31 else t[:30] + "…"

    def epic_tag(e: int) -> str:
        m = re.match(r"^(?:E|Epic )(\d+)", title(e))
        return f"E{m.group(1)}" if m else f"#{e}"

    def epic(n: int) -> str:
        m = re.match(r"^(E\d+)", title(n))
        if m:
            return m.group(1)
        if "epic" in labels(n):
            return epic_tag(n)
        if n in parent:
            return epic_tag(parent[n])
        return "—" if n in stories else "decision"

    def icons(n: int) -> str:
        return STATUS[status(n)][0]

    esc = html.escape
    svg: list[str] = []
    for j, (name, members) in enumerate(column_list):
        bx = PAD + j * (W + GX) - GX / 2
        svg.append(f'<rect class="band b{j % 2}" data-col="{j}" x="{bx}" y="{TOP - 30}" width="{W + GX}" height="{height - TOP + 30}"/>')
        done = sum(1 for n in members if st(n) == "CLOSED")
        svg.append(f'<text class="wl" data-col="{j}" x="{bx + (W + GX) / 2}" y="{TOP - 10}" text-anchor="middle">{esc(name)} '
                   f'<tspan class="wc">{done}/{len(members)} closed</tspan></text>')
    for n in nodes:
        x2, y2 = xy[n]
        for b in blk[n]:
            x1, y1 = xy[b]
            sx, sy = x1 + W, y1 + H / 2
            ex, ey = x2, y2 + H / 2
            c = (ex - sx) / 2
            cls = "e closed" if st(b) == "CLOSED" else "e open"
            svg.append(f'<path class="{cls}" data-from="{b}" data-to="{n}" d="M{sx},{sy} C{sx + c},{sy} {ex - c},{ey} {ex},{ey}"/>')
    for e in epics:
        x1, y1 = xy[e]
        for k in kids[e]:
            x2, y2 = xy[k]
            sx, sy, ex, ey = x1 + W, y1 + H / 2, x2, y2 + H / 2
            c = (ex - sx) / 2
            svg.append(f'<path class="e epl" data-from="{e}" data-to="{k}" d="M{sx},{sy} C{sx + c},{sy} {ex - c},{ey} {ex},{ey}"/>')
    meta: dict[int, dict] = {}
    for n in [*epics, *nodes]:
        x, y = xy[n]
        s = status(n)
        cross = (f'<line class="x" x1="4" y1="4" x2="{W - 4}" y2="{H - 4}"/><line class="x" x1="{W - 4}" y1="4" x2="4" y2="{H - 4}"/>'
                 if s == "closed" else "")
        assignees = [a["login"] for a in d[n]["assignees"]] if n in d else []
        who = ("👤 " + ", ".join(assignees)) if assignees else ""
        if n in kids:
            who = f"{sum(st(k) == 'CLOSED' for k in kids[n])}/{len(kids[n])} stories closed"
        svg.append(
            f'<g class="node {s} k-{kind(n)}" data-id="{n}" transform="translate({x},{y})">'
            f'<rect width="{W}" height="{H}" rx="7"/>{cross}'
            f'<text class="num" x="10" y="18">#{n} <tspan class="ic">{icons(n)}</tspan></text>'
            f'<text class="ep" x="{W - 10}" y="18" text-anchor="end">{esc(epic(n))}</text>'
            f'<text class="tt" x="10" y="36">{esc(short(n))}</text>'
            f'<text class="as" x="10" y="52">{esc(who)}</text></g>')
        meta[n] = {
            "title": title(n), "state": st(n), "status": s, "kind": kind(n), "level": colname[n],
            "assignees": assignees,
            "blockers": [{"n": b, "state": st(b), "title": title(b)} for b in blk.get(n, [])],
            "waiting": sorted(m for m in nodes if n in blk[m]),
            "parent": parent.get(n),
            "kids": [{"n": k, "state": st(k), "title": title(k)} for k in kids.get(n, [])],
        }
    up = {n: blk[n] for n in nodes}
    layout = [members for _, members in column_list]  # the browser re-packs these columns when a filter hides issues
    people = sorted({a for m in meta.values() for a in m["assignees"]}, key=str.lower)

    css = CSS
    js = (JS.replace("UPJSON", json.dumps(up)).replace("METAJSON", json.dumps(meta))
          .replace("STATUSJSON", json.dumps(STATUS)).replace("KINDJSON", json.dumps(KIND)).replace("REPOURL", repo_url)
          .replace("GRAPHW", str(width)).replace("GRAPHH", str(height)).replace("LAYOUTJSON", json.dumps(layout))
          .replace("GEOMJSON", json.dumps({"W": W, "H": H, "GX": GX, "GY": GY, "PAD": PAD, "TOP": TOP})))

    HIDDEN = {"epic", "closed"}  # legend entries that start unticked
    legend = '<b class="ax">Background = who takes it</b>' + "".join(
        f'<label><input type="checkbox"{"" if k in HIDDEN else " checked"} data-ax="kind" value="{k}"><i class="i k-{k}"></i>{esc(name)}<span class="cnt"></span></label>'
        for k, (_, name, _) in KIND.items())
    legend += '<br><b class="ax">Icon = progress</b>' + "".join(
        f'<label><input type="checkbox"{"" if k in HIDDEN else " checked"} data-ax="status" value="{k}"><i class="i {k}"></i>{ic} {esc(name)}<span class="cnt"></span></label>'
        for k, (ic, name, _) in STATUS.items())
    legend += '<br><b class="ax">Assignee</b>' + "".join(
        f'<label><input type="checkbox" checked data-ax="who" value="{esc(p)}">👤 {esc(p)}<span class="cnt"></span></label>' for p in people)
    legend += '<label><input type="checkbox" checked data-ax="who" value="nobody">nobody assigned<span class="cnt"></span></label>'
    legend += '<span id="count"></span> <a href="#" id="all" style="font-size:12px" onclick="return false">show all</a>'
    legend += ('<br><b class="ax">Lines</b>'
               '<span><i style="border:none;border-top:3px solid #8C959F;height:0;border-radius:0;vertical-align:2px"></i>blocker closed</span>'
               '<span><i style="border:none;border-top:3px solid #CF222E;height:0;border-radius:0;vertical-align:2px"></i>blocker still open</span>'
               '<span><i style="border:none;border-top:3px dashed #8250DF;height:0;border-radius:0;vertical-align:2px"></i>epic to its story</span>')
    mism_txt = "they agree on every open issue" if not mism else "they DISAGREE on: " + ", ".join(f"#{n}" for n in mism)
    problems = ""
    if bad_links:
        problems += " Dropped links to an epic or to an issue that does not exist: " + ", ".join(
            f"#{n}→#{b}" for n, b in bad_links) + "."
    if cyc_links:
        problems += " Dropped links that close a cycle: " + ", ".join(f"#{n}→#{b}" for n, b in cyc_links) + "."
    out = f"""<!doctype html><html><head><meta charset="utf-8"><title>{esc(repo_name)} issue map</title><style>{css}</style></head><body>
<header><h1>{esc(repo_name)} · issue map: what is blocked by what, level by level</h1>
<div id="banner">⚠ Transient snapshot, not a source of truth. Generated by <b>{esc(user)}</b> on <b>{stamp}</b> from the GitHub issues as they were at that moment; it goes stale as soon as any issue changes. Rebuild it with <code>/issue-map</code> or ask "show me the issue map". The live state is always the GitHub issues.</div>
<div class="leg">{legend}</div>
<div id="hint"></div></header>
<div id="tip"></div>
<div id="wrap"><div id="zoom"><button id="zin" title="Zoom in">+</button><button id="zout" title="Zoom out">−</button><button id="zfit" title="Fit the whole map">Fit</button><button id="z100" title="Actual size">100%</button><span id="zpct"></span></div><svg id="map"><g id="vp">{"".join(svg)}</g></svg></div>
<footer>Every issue is drawn, open or closed, whatever its label. Epics sit in the far-left column, outside the levels, joined to their stories by dashed purple lines (GitHub's native sub-issue link); each story's top-right tag names its epic. Epics and closed issues start hidden: tick them in the legend. An issue's level is 0 when nothing blocks it, else one more than the highest level among its blockers; closed blockers count, labels never change a level. The columns are the levels; a line always runs left to right, from the blocker to the issue that waits for it. An issue opens the moment every line coming into it is grey, whatever else in its column or earlier columns is still open. Source: the <code>### Blocked by</code> body section plus GitHub's native relation; {mism_txt}.{problems}</footer>
<script>{js}</script></body></html>"""
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(out, encoding="utf-8")
    ensure_excluded()
    print(f"{OUT} - {len(nodes)} issues + {len(epics)} epics - generated by {user} on {stamp}")
    if "--open" in sys.argv[1:]:
        if os.name == "nt":
            os.startfile(OUT)  # type: ignore[attr-defined]
        else:
            webbrowser.open(OUT.as_uri())


CSS = """:root{--accent:#0969DA;--ink:#1F2328;--ink-muted:#59636E;--mist:#8C959F;--mist-light:#D1D9E0;--sky:#DDF4FF;--success-wash:#DAFBE1;--warning:#9A6700;--warning-wash:#FFF8C5;--error:#CF222E;--error-wash:#FFEBE9;--purple:#8250DF;--purple-wash:#FBEFFF;--border:#D1D9E0;--shadow-md:0 0 20px rgba(31,35,40,.13)}
html,body{height:100%}body{display:flex;flex-direction:column;overflow:hidden;margin:0;font:14px/1.45 system-ui,-apple-system,'Segoe UI',Roboto,'Helvetica Neue',Arial,sans-serif;font-weight:500;background:#fff;color:var(--ink)}
header{padding:12px 24px;background:#fff;border-bottom:1px solid var(--border);flex:none;z-index:2}
h1{font-size:19px;font-weight:500;margin:0 0 6px;color:var(--ink)}
#banner{background:var(--warning-wash);color:var(--warning);border:1px solid #D4A72C;border-radius:10px;padding:6px 12px;margin:0 0 8px;font-size:13px}
.leg{font-size:13px}.leg span{display:inline-block;margin-right:14px;margin-bottom:3px}
.leg i{display:inline-block;width:18px;height:18px;border-radius:5px;vertical-align:-3px;margin-right:4px;border:3px solid var(--mist-light);font-style:normal;background:#fff}
.leg b.ax{display:inline-block;width:160px;color:var(--ink-muted);font-weight:700}
#wrap{flex:1;min-height:0;position:relative;overflow:hidden;cursor:grab;touch-action:none}#wrap.drag{cursor:grabbing}#map{width:100%;height:100%;display:block;user-select:none}
#zoom{position:absolute;right:16px;top:12px;z-index:3;display:flex;gap:6px;align-items:center;background:#fff;border:1px solid var(--mist-light);border-radius:10px;padding:5px 8px;box-shadow:var(--shadow-md)}#zoom button{font:inherit;font-weight:700;min-width:32px;height:30px;border:1px solid var(--mist-light);border-radius:7px;background:#fff;color:var(--ink);cursor:pointer}#zoom button:hover{background:var(--sky)}#zpct{color:var(--ink-muted);font-size:12px;min-width:40px;text-align:right}
.band.b0{fill:#F6F8FA}.band.b1{fill:#EAEEF2}.wl{font-size:15px;font-weight:700;fill:var(--ink)}.wc{font-weight:500;fill:var(--ink-muted);font-size:12px}
.e{fill:none;stroke-width:1.6;opacity:.6}.e.closed{stroke:var(--mist)}.e.open{stroke:var(--error);stroke-width:2}.e.epl{stroke:var(--purple);stroke-dasharray:5 4;opacity:.45}
.node rect{stroke-width:4;fill:#fff;cursor:pointer}.node text,.node line{pointer-events:none}.num{font-weight:700;font-size:13px;fill:var(--ink)}.ic{font-size:12px;font-family:"Segoe UI Emoji",system-ui}.ep{font-size:11px;fill:var(--ink-muted)}.tt{font-size:12px;fill:var(--ink)}.as{font-size:11px;fill:var(--ink-muted);font-weight:700}
.node.off,.e.off,.band.off,.wl.off{display:none}
.leg label{display:inline-block;margin-right:12px;margin-bottom:3px;cursor:pointer;user-select:none;padding:1px 8px;border-radius:999px}.leg label:hover{background:var(--sky)}.leg label.unchecked{opacity:.4;text-decoration:line-through}.leg input{display:none}.leg .cnt{color:var(--ink-muted);font-size:12px;margin-left:3px}
#count{font-weight:700;color:var(--ink);margin-left:8px}a{color:var(--accent)}
.node.closed text{fill:var(--ink-muted)}.node .x{stroke:var(--error);stroke-width:2;opacity:.55}
.node rect{stroke:var(--mist-light)}
.node.k-agent rect{fill:var(--success-wash)}.node.k-human rect{fill:var(--error-wash)}.node.k-outside rect{fill:var(--sky)}.node.k-decision rect{fill:var(--warning-wash)}.node.k-epic rect{fill:var(--purple-wash)}
svg.focus .node,svg.focus .e{opacity:.12}svg.focus .node.hl,svg.focus .e.hl{opacity:1}svg.focus .e.hl{stroke-width:3}svg.focus .node.sel rect{stroke-width:7}
.i.closed{background:#fff linear-gradient(45deg,transparent 42%,var(--error) 42%,var(--error) 58%,transparent 58%),linear-gradient(-45deg,transparent 42%,var(--error) 42%,var(--error) 58%,transparent 58%)}.i.inprog,.i.ready,.i.blocked{background:#fff}
.i.k-agent{background:var(--success-wash)}.i.k-human{background:var(--error-wash)}.i.k-outside{background:var(--sky)}.i.k-decision{background:var(--warning-wash)}.i.k-epic{background:var(--purple-wash)}
#hint{color:var(--ink-muted);font-size:13px;margin-top:4px}
#tip{position:fixed;z-index:9;display:none;max-width:480px;background:#fff;border:1px solid var(--mist-light);border-radius:10px;box-shadow:var(--shadow-md);padding:10px 14px;font-size:13px;pointer-events:none;color:var(--ink)}
#tip h3{margin:0 0 4px;font-size:14px;font-weight:700}#tip .st{display:inline-block;padding:1px 9px;border-radius:999px;border:3px solid var(--mist-light);font-weight:700;margin:2px 0}#tip .row{margin:3px 0}#tip ul{margin:4px 0 0;padding-left:18px}#tip .m{color:var(--ink-muted)}#tip .c{text-decoration:line-through;color:var(--mist)}#tip .o{color:var(--error);font-weight:700}#tip .pin{color:var(--ink-muted);font-size:12px;margin-top:6px}
footer{flex:none;max-height:4.5em;overflow:auto;border-top:1px solid var(--border);padding:6px 24px;font-size:12px;color:var(--ink-muted);max-width:1000px}"""

JS = """let GW=GRAPHW,GH=GRAPHH;const up=UPJSON;const META=METAJSON;const STATUS=STATUSJSON;const KIND=KINDJSON;const REPO='REPOURL';
const down={};for(const n in up){for(const b of up[n]){(down[b]=down[b]||[]).push(+n)}}
const svg=document.querySelector('svg');const tip=document.getElementById('tip');let pinned=null;
function walk(start,adj){const s=new Set();const q=[start];while(q.length){const n=q.pop();for(const m of (adj[n]||[])){if(!s.has(m)){s.add(m);q.push(m)}}}return s}
function esc(s){return String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]))}
function tipHtml(id){const m=META[id];const [ic,name,mean]=STATUS[m.status];const [,kname,kmean]=KIND[m.kind];
let h='<h3>#'+id+' '+esc(m.title)+'</h3>';
h+='<div class="row"><b>Progress</b> <span class="st i '+m.status+'">'+ic+' '+name+'</span> <span class="m">'+esc(mean)+'</span></div>';
h+='<div class="row"><b>Who takes it</b> <span class="st i k-'+m.kind+'">'+kname+'</span> <span class="m">'+esc(kmean)+'</span></div>';
h+='<span class="m">'+esc(m.level)+' · GitHub state: '+m.state+(m.assignees.length?' · assigned to '+esc(m.assignees.join(', ')):' · nobody assigned')+'</span>';
if(m.kind==='epic'){h+='<div style="margin-top:6px"><b>Stories:</b> '+(m.kids.length?'':'none linked as sub-issues')+'</div>';
if(m.kids.length){h+='<ul>'+m.kids.map(b=>'<li class="'+(b.state==='CLOSED'?'c':'')+'">#'+b.n+' '+esc(b.title)+' ('+b.state.toLowerCase()+')</li>').join('')+'</ul>'}
h+='<div class="pin">'+(pinned===id?'Click the box again to clear · double-click opens it on GitHub':'Double-click opens it on GitHub')+'</div>';return h}
if(m.parent){h+='<div class="row"><b>Epic</b> #'+m.parent+' '+esc(META[m.parent].title)+'</div>'}
h+='<div style="margin-top:6px"><b>Blocked by:</b> '+(m.blockers.length?'':'nothing')+'</div>';
if(m.blockers.length){h+='<ul>'+m.blockers.map(b=>'<li class="'+(b.state==='CLOSED'?'c':'o')+'">#'+b.n+' '+esc(b.title)+' ('+b.state.toLowerCase()+')</li>').join('')+'</ul>'}
h+='<div style="margin-top:6px"><b>Waiting on it:</b> '+(m.waiting.length?m.waiting.map(w=>'#'+w).join(', '):'nothing')+'</div>';
h+='<div class="pin">'+(pinned===id?'Click the box again to clear · double-click opens it on GitHub':'Double-click opens it on GitHub')+'</div>';return h}
function showTip(id,ev){tip.innerHTML=tipHtml(id);tip.style.display='block';moveTip(ev)}
function moveTip(ev){if(!ev)return;const r=tip.getBoundingClientRect();let x=ev.clientX+16,y=ev.clientY+16;if(x+r.width>innerWidth-8)x=ev.clientX-r.width-16;if(y+r.height>innerHeight-8)y=ev.clientY-r.height-16;tip.style.left=x+'px';tip.style.top=y+'px'}
function focus(id,ev){svg.classList.add('focus');const m=META[id];const u=walk(id,up),dn=walk(id,down);const all=new Set([...u,...dn,id,...m.kids.map(k=>k.n)]);if(m.parent)all.add(m.parent);
document.querySelectorAll('.node').forEach(g=>{const n=+g.dataset.id;g.classList.toggle('hl',all.has(n));g.classList.toggle('sel',n===id)});
document.querySelectorAll('.e').forEach(e=>{const f=+e.dataset.from,t=+e.dataset.to;e.classList.toggle('hl',all.has(f)&&all.has(t))});
document.getElementById('hint').textContent=m.kind==='epic'?'#'+id+': '+m.kids.length+' stories in this epic, lit up across the levels.':'#'+id+': '+u.size+' issue(s) upstream must close first (left), '+dn.size+' wait on it (right).';showTip(id,ev)}
function clear(){svg.classList.remove('focus');document.querySelectorAll('.hl,.sel').forEach(e=>e.classList.remove('hl','sel'));document.getElementById('hint').textContent=HINT;tip.style.display='none'}
const HINT='Drag to move around, scroll the wheel to zoom (or use the buttons). Click an issue to see its chain and a tooltip, click it again to clear. Double-click opens it on GitHub. Click a legend entry to hide or show that type (hidden issues leave the map and the rest close up); each shows shown/total.';document.getElementById('hint').textContent=HINT;
document.querySelectorAll('.node').forEach(g=>{const id=+g.dataset.id;
g.addEventListener('click',ev=>{if(pinned===id){pinned=null;clear()}else{pinned=id;focus(id,ev)}});
g.addEventListener('dblclick',()=>window.open(REPO+id,'_blank'))});
const ALL=Object.keys(META).map(Number);
function matches(n,ax,v){const m=META[n];if(ax==='who'){return v==='nobody'?m.assignees.length===0:m.assignees.includes(v)}return m[ax]===v}
function on(ax){return new Set([...document.querySelectorAll('input[data-ax='+ax+']:checked')].map(i=>i.value))}
function applyFilter(){const onS=on('status'),onK=on('kind'),onW=on('who');
const vis=new Set(ALL.filter(n=>onS.has(META[n].status)&&onK.has(META[n].kind)&&(META[n].assignees.length?META[n].assignees.some(a=>onW.has(a)):onW.has('nobody'))));
document.querySelectorAll('.node').forEach(g=>g.classList.toggle('off',!vis.has(+g.dataset.id)));
document.querySelectorAll('.e').forEach(e=>e.classList.toggle('off',!(vis.has(+e.dataset.from)&&vis.has(+e.dataset.to))));
document.querySelectorAll('.leg label').forEach(l=>{const i=l.querySelector('input');l.classList.toggle('unchecked',!i.checked);const ax=i.dataset.ax,v=i.value;const tot=ALL.filter(n=>matches(n,ax,v)).length;const shown=ALL.filter(n=>vis.has(n)&&matches(n,ax,v)).length;l.querySelector('.cnt').textContent=shown+'/'+tot});
document.getElementById('count').textContent='Showing '+vis.size+' of '+ALL.length+' issues';relayout(vis);}
const LAYOUT=LAYOUTJSON,G=GEOMJSON;
function relayout(vis){const cols=LAYOUT.map((m,j)=>({j,m:m.filter(n=>vis.has(n))})).filter(c=>c.m.length);const rows=Math.max(1,...cols.map(c=>c.m.length));
const xy={};GH=G.TOP+rows*(G.H+G.GY)+G.PAD;GW=G.PAD*2+Math.max(1,cols.length)*(G.W+G.GX)-G.GX;
document.querySelectorAll('.band,.wl').forEach(e=>e.classList.add('off'));
cols.forEach((c,k)=>{const cx=G.PAD+k*(G.W+G.GX),bx=cx-G.GX/2,off=(rows-c.m.length)*(G.H+G.GY)/2;
const band=document.querySelector('.band[data-col="'+c.j+'"]'),wl=document.querySelector('.wl[data-col="'+c.j+'"]');
band.classList.remove('off','b0','b1');band.classList.add('b'+(k%2));band.setAttribute('x',bx);band.setAttribute('height',GH-G.TOP+30);
wl.classList.remove('off');wl.setAttribute('x',bx+(G.W+G.GX)/2);
c.m.forEach((n,i)=>{xy[n]=[cx,G.TOP+off+i*(G.H+G.GY)];document.querySelector('.node[data-id="'+n+'"]').setAttribute('transform','translate('+xy[n][0]+','+xy[n][1]+')')})});
document.querySelectorAll('.e').forEach(e=>{const a=xy[e.dataset.from],b=xy[e.dataset.to];if(!a||!b)return;const sx=a[0]+G.W,sy=a[1]+G.H/2,ex=b[0],ey=b[1]+G.H/2,c=(ex-sx)/2;
e.setAttribute('d','M'+sx+','+sy+' C'+(sx+c)+','+sy+' '+(ex-c)+','+ey+' '+ex+','+ey)});
if(window.ZOOMREADY)fit(false)}
document.querySelectorAll('.leg input').forEach(i=>i.addEventListener('change',applyFilter));
document.getElementById('all').addEventListener('click',()=>{document.querySelectorAll('.leg input').forEach(i=>i.checked=true);applyFilter()});
applyFilter();
const wrap=document.getElementById('wrap'),vp=document.getElementById('vp');let z=1,tx=0,ty=0;
function paint(){vp.setAttribute('transform','translate('+tx+','+ty+') scale('+z+')');document.getElementById('zpct').textContent=Math.round(z*100)+'%'}
function zoomAt(f,cx,cy){const nz=Math.min(3,Math.max(0.05,z*f));tx=cx-(cx-tx)*nz/z;ty=cy-(cy-ty)*nz/z;z=nz;paint()}
function fit(all){const w=wrap.clientWidth,h=wrap.clientHeight;z=Math.min(1,(w-20)/GW,all?(h-20)/GH:9);tx=(w-GW*z)/2;ty=all?(h-GH*z)/2:10;paint()}
wrap.addEventListener('wheel',ev=>{ev.preventDefault();const r=wrap.getBoundingClientRect();zoomAt(Math.exp(-ev.deltaY*0.0015),ev.clientX-r.left,ev.clientY-r.top)},{passive:false});
let drag=null,moved=false;
wrap.addEventListener('pointerdown',ev=>{if(ev.button!==0||ev.target.closest('#zoom'))return;drag={x:ev.clientX,y:ev.clientY,tx,ty};moved=false});
addEventListener('pointermove',ev=>{if(!drag)return;const dx=ev.clientX-drag.x,dy=ev.clientY-drag.y;if(!moved&&Math.hypot(dx,dy)<4)return;moved=true;wrap.classList.add('drag');tip.style.display='none';tx=drag.tx+dx;ty=drag.ty+dy;paint()});
addEventListener('pointerup',()=>{drag=null;wrap.classList.remove('drag')});
wrap.addEventListener('click',ev=>{if(moved){ev.stopPropagation();moved=false}},true);
const mid=()=>[wrap.clientWidth/2,wrap.clientHeight/2];
document.getElementById('zin').onclick=()=>zoomAt(1.25,...mid());document.getElementById('zout').onclick=()=>zoomAt(0.8,...mid());
document.getElementById('zfit').onclick=()=>fit(true);document.getElementById('z100').onclick=()=>{const [cx,cy]=mid();zoomAt(1/z,cx,cy)};
window.ZOOMREADY=true;fit(false);"""


if __name__ == "__main__":
    main()
