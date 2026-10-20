# ADR — one changelog file per pull request instead of one shared file

**Status: approved by the owner on 2026-10-20.**

## Context

The rules made every pull request add its line at the top of `docs/CHANGELOG.md`. With several people and agents
merging at the same time, every pull request edits the same few lines of the same file, so each merge to `main`
puts every other open pull request into a merge conflict. Fixing it by hand is pure busywork, and it holds up
`/dev-next` runs that would otherwise merge on green.

## Decision

1. **Every pull request adds its own file** to `docs/changelog/`, named `<YYYY-MM-DD>-<branch>.md` (the day it is
   written, the branch name with `/` turned into `-`), holding one line: what changed and why it matters. No two
   pull requests touch the same file, so the changelog can no longer conflict, on a computer or on GitHub's buttons.
2. **Newest first is the file names sorted in reverse.** No build step joins them. The order is by the day an entry
   was written, not merged, and entries from one day sort by branch name; the folder's `README.md` is not an entry.
3. **An existing single-file changelog is frozen**, kept as the history before the folder; nobody adds to it or
   edits another pull request's file.
4. **`verify` checks for the folder** (`changelog-missing` when absent) and `/orion-verify` creates it with a
   `README.md` explaining the format. The old warning that offered to move a root `CHANGELOG.md` is gone: the file
   it moved is now history.

## Consequences

- No single page to scroll: a reader lists the folder, newest first.
- Every skill that writes a changelog line (`dev-next`, `harvest`, `harvest-qa`, `prd-to-tickets`,
  `reconcile-issue-map`, `wayfinder`, `orion-verify`) and the review check now name the file instead.
- Two pull requests from branches with the same name on the same day would collide; branches are unique while
  open, so this needs a reused branch name.

## Alternatives

- **Git's union merge on the one file** (`.gitattributes`: keep both sides' lines). One line of setup, but it only
  helps merges run on a computer, GitHub's web buttons still report conflicts, and orion would have to write into
  every project's `.gitattributes`.
- **Generate the changelog from pull request titles at release.** No file to edit, but the "why it matters" sentence
  is lost unless titles carry it, and it needs a new generator script.
