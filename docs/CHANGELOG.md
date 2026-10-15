# Changelog

Notable changes to this repo, newest first, one short line per change. Headings follow
[Keep a Changelog](https://keepachangelog.com/): **Added / Changed / Removed / Fixed**.
Changes made before this file existed are only in the git history.

## Unreleased

### Added

- `orion.sh` / `orion.ps1` with `init | update | check | status | uninstall`: orion is installed **into a project** (`.claude/skills`, `.claude/orion`, a `CLAUDE.md` import line, a `SessionStart` update-check hook) and committed, so teammates get it by pulling; one-line bootstrap (a throwaway shallow clone).
- `baselines/ORION.md`: the orion-owned rules file, imported by the project `CLAUDE.md` (which wins on conflict) and refreshed on every update.
- `orion` skill (`/orion status | check | update | uninstall`) and `updateMode` (`ask` default / `auto` / `off`) in `.claude/orion/config.json`.
- `docs/CHANGELOG.md` and a `CLAUDE.md` rule that every commit/PR adds one summarised line here.

### Changed

- `baselines/BASE_CLAUDE.md` now starts with the `@.claude/orion/ORION.md` import; the generic communication/git/testing rules moved into `ORION.md`.
- The status line is installed per computer by `orion init --statusline` (same baseline behaviour as before).

### Removed

- User-level installers `install.ps1` / `install.sh` / `uninstall.*`; `init` retires leftover user-level orion skill copies.

### Fixed

- Bootstrap one-liners fetch `orion.sh` / `orion.ps1` straight from the public repo (`curl … | bash`, `irm … | iex`); the shallow-clone form stays documented as an alternative.
