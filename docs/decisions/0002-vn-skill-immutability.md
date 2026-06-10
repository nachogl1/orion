# 2. `-vN` skill immutability

Date: 2026-06-06

## Status

Accepted

## Context

People and automated workflows depend on the current behaviour of the
`sequential-bmad-github-orion-vN` skills. Editing such a skill in place would
silently change behaviour for everyone who already relies on it.

## Decision

For `sequential-bmad-github-orion-vN` skills, prefer creating a **new version**
(copy to a bumped `-vN` suffix) over editing in place. Add a CHANGELOG entry
describing the deltas, leave the prior version as-is, and add the new skill's row
to the root `README.md`. Other skills (e.g. `guided-qa-orion`) and the status line
have no `-vN` convention and are edited in place.

## Consequences

- Existing consumers keep stable behaviour; upgrades are explicit opt-in.
- The repo accumulates older versions by design — historical CHANGELOG entries that
  name an old skill name are left intact as an accurate record.
