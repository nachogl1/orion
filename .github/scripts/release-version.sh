#!/usr/bin/env bash
# .github/scripts/release-version.sh - orion's version rules, for the release job and the pull request title check.
# orion's version has three parts, major.minor.patch, from 2.0.0 on, and lives only in the v<major.minor.patch>
# release tags: nobody sets it by hand.
#
# usage: bash .github/scripts/release-version.sh next             in a clone of main with its history and tags:
#                                                                  prints the tags the release job pushes, one per
#                                                                  line, or nothing when there is nothing to release
#        bash .github/scripts/release-version.sh title "<title>"  exits 1 when the title does not start with a
#                                                                  valid Conventional Commit type
#
# Portable bash: no GNU-only flags.

set -eu

# What a project receives: a release changes at least one of these.
SHIPPED="skills baselines orion.sh"
FIRST_VERSION=2.0.0
TYPES="build|chore|ci|docs|feat|fix|perf|refactor|revert|style|test"
# type(scope)!: summary, the scope and the ! optional
TITLE_PATTERN="^($TYPES)(\([^()]+\))?!?: [^ ]"
BREAKING_PATTERN='^[a-z]+(\([^()]*\))?!:'
FEATURE_PATTERN='^feat(\([^()]*\))?:'

usage() { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# The highest release tag of each kind, without its v: three parts, and the whole numbers orion used before them.
highest_three_part() { git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's/^v//' | sort -t. -k1,1n -k2,2n -k3,3n | tail -n1; }
highest_whole() { git tag -l 'v*' | grep -E '^v[0-9]+$' | sed 's/^v//' | sort -n | tail -n1; }

# One version tag, sized by the biggest change among the pull requests since the last release (each one a squash
# commit whose subject is its title; a release's own merge commit is left out): any ! raises the first part, else any
# feat the middle part, else the last part; the first release is FIRST_VERSION whatever the types. Every release
# also gets one more whole-number tag, the only kind an orion.sh from before three-part versions reads, so such an
# install is offered every release, even after declining one (update --skip records the tag it declined).
cmd_next() {
    local last whole since subjects major minor patch
    last="$(highest_three_part)"; whole="$(highest_whole)"
    since="${last:-$whole}"
    if [ -n "$since" ] && git diff --quiet "v$since" HEAD -- $SHIPPED; then return 0; fi
    # a re-run on an older commit that a later release already contains: that release shipped it
    if [ -n "$since" ] && git merge-base --is-ancestor HEAD "v$since"; then return 0; fi
    if [ -z "$last" ]; then
        printf 'v%s\n' "$FIRST_VERSION"
    else
        subjects="$(git log --no-merges --format=%s "v$last..HEAD")"
        major="${last%%.*}"; minor="${last#*.}"; patch="${minor#*.}"; minor="${minor%.*}"
        if printf '%s\n' "$subjects" | grep -qE "$BREAKING_PATTERN"; then printf 'v%s.0.0\n' "$((major + 1))"
        elif printf '%s\n' "$subjects" | grep -qE "$FEATURE_PATTERN"; then printf 'v%s.%s.0\n' "$major" "$((minor + 1))"
        else printf 'v%s.%s.%s\n' "$major" "$minor" "$((patch + 1))"; fi
    fi
    [ -z "$whole" ] || printf 'v%s\n' "$((whole + 1))"
}

# The title is never echoed back: a pull request title is untrusted text, and the log reads workflow commands.
cmd_title() {
    [[ "$1" =~ $TITLE_PATTERN ]] && return 0
    echo "The pull request title must start with a Conventional Commit type: type(scope)!: summary, where type is one of ${TYPES//|/, } and the scope and the ! are optional." >&2
    exit 1
}

case "${1:-}" in
    next) [ $# -eq 1 ] || usage; cmd_next ;;
    title) [ $# -eq 2 ] || usage; cmd_title "$2" ;;
    *) usage ;;
esac
