<!-- Branch off `main`. Title: `scope: short imperative summary`. -->

## Summary
<!-- One line: what changed and why. -->
Closes #<!-- issue number — open one first if none exists -->

## Type of change
- [ ] New skill
- [ ] Edit to existing skill
- [ ] Installer (`orion.sh` / `orion.ps1`) change
- [ ] Status line / shared tooling change
- [ ] Documentation only

## Out-of-scope / follow-ups
<!-- Every deferred item MUST carry a linked #N (file the issue first). Unanchored
     deferrals are dropped commitments — a reviewer should reject them. Else write "None." -->
- None.

## Manual verification (no CI / tests exist)
- [ ] Skill ran end-to-end as intended (describe scenario + outcome below)
- [ ] Installer re-copies cleanly (if touched)
**What I ran and what I saw:**

## Docs updated
- [ ] Changelog file added in `docs/changelog/` (plus the skill's own `CHANGELOG.md` if it has one and behaviour changed)
- [ ] Root README updated (skill added / renamed / removed)

## Enforcement checklist
### Distribution safety (check the diff AND this PR title/body)
- [ ] No person/username/email/org identifiers
- [ ] No company/product/codename/private-repo slug
- [ ] No private URLs/hostnames/bucket/table/queue names
- [ ] No absolute user paths (`C:\Users\...`, `/home/...`) — use `~/.claude` / `<placeholder>`
- [ ] No real issue/PR numbers, story IDs, or commit SHAs from a private source project
### Installer (only if install.* touched)
- [ ] `install.ps1` pure-ASCII + PS 5.1-compatible (no `&&`, `??`, `?.`, ternary)
### Commits
- [ ] Every commit ends with the `Co-Authored-By` trailer

/cc <!-- @reviewer — no self-merge -->
