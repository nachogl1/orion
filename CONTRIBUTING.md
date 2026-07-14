# Contributing

See [CLAUDE.md](CLAUDE.md) for the full working rules. Key points:

- Branch off `main`: `feat/<short-desc>` or `fix/<short-desc>`.
- Commit subject: [Conventional Commits](https://www.conventionalcommits.org/) — `type(scope): imperative summary`, where `type` is one of `feat` / `fix` / `docs` / `chore` / `refactor` / `test` and `scope` names the skill or area (e.g. `feat(assess-infra): add ADR check`, `fix(installer): guard junction delete`). Existing history is not rewritten; the convention applies to new commits.
- End every commit with the required `Co-Authored-By` trailer.
- Before a PR: search open issues AND the code; never point at a *closed* issue to skip work.
- Self-check your diff AND PR title/body for any person/org/product/path specifics.

## Doc checks (CI runs these on every PR)

CI (`.github/workflows/docs-ci.yml`) lints the markdown corpus and checks internal (relative) links strictly; external links are checked non-blocking. Run locally before pushing (needs node):

```sh
npx -y markdownlint-cli2                                             # structural markdown errors
git ls-files '*.md' | while read -r f; do
  npx -y markdown-link-check -q -c .markdown-link-check.json "$f" || exit 1
done                                                                 # internal links
```
