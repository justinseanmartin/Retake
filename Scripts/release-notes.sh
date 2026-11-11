#!/usr/bin/env bash
# Prints a version's release notes, its section of RELEASE.md without the heading, for the GitHub
# release, so what a release breaks is said there as it is in RELEASE.md. Fails when RELEASE.md has
# no section for the version.
set -euo pipefail
[[ $# -eq 1 ]] || { echo "usage: Scripts/release-notes.sh <version>" >&2; exit 2; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTES="$(awk -v heading="## $1 " '
    index($0, heading) == 1 { found = 1; next }
    found && /^## / { exit }
    found { print }
' "$ROOT/RELEASE.md" | sed -e '/./,$!d')"
[[ -n "$NOTES" ]] || { echo "error: RELEASE.md has no notes for $1" >&2; exit 1; }
printf '%s\n' "$NOTES"
