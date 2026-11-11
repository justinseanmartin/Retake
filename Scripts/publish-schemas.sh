#!/usr/bin/env bash
# Publishes Retake's schemas to GitHub Pages, at
# https://<owner>.github.io/Retake/schemas/<version>/<kind>.schema.json, the URL each schema's $id
# names and a file's "$schema" points an editor at. Copies Documentation/reference/*.schema.json as
# the current branch has them into schemas/<version>/ on the gh-pages branch, which is checked out
# in .pages/ (gitignored), commits, and pushes; and turns Pages on the first time. Other versions'
# folders are left as they are.
#
# Publishes only main, with nothing uncommitted, so what's served is what's merged, and never
# replaces a version's schemas once they're published, since files name them by their URL. --force
# publishes the current branch as it stands, and replaces a version's published schemas.
set -euo pipefail

usage() {
    echo "Usage: Scripts/publish-schemas.sh [--force]"
    echo "  --force  Publish from a branch other than main, or with uncommitted changes, or replace a"
    echo "           version's schemas that are published already."
}
force=false
while (($#)); do
    case "$1" in
        --force) force=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGES="$ROOT/.pages"
cd "$ROOT"

if ! $force; then
    branch="$(git symbolic-ref --quiet --short HEAD || echo "a detached HEAD")"
    [[ "$branch" == main ]] || { echo "error: schemas are published from main, and this is $branch; merge first, or give --force" >&2; exit 1; }
    [[ -z "$(git status --porcelain)" ]] || { echo "error: there are uncommitted changes; commit or stash them, or give --force" >&2; exit 1; }
fi

# The version the schemas name themselves for, which is the folder they're served from.
shopt -s nullglob
SCHEMAS=("$ROOT"/Documentation/reference/*.schema.json)
((${#SCHEMAS[@]})) || { echo "error: there are no schemas in Documentation/reference/; write them with retake schema --output" >&2; exit 1; }
VERSIONS="$(sed -n 's|.*"\$id": *"https://[^"]*/schemas/\([^/"]*\)/[^"]*".*|\1|p' "${SCHEMAS[@]}" | sort -u)"
[[ -n "$VERSIONS" && "$VERSIONS" != *$'\n'* ]] \
    || { echo "error: the schemas' \$ids should all name one version, and name: ${VERSIONS:-none}" >&2; exit 1; }
VERSION="$VERSIONS"

source "$ROOT/Scripts/pages.sh"
open_pages

# Whether this version's schemas are published already, which they then must match.
published=false
if git -C "$PAGES" rev-parse --quiet --verify HEAD >/dev/null && [[ -n "$(git -C "$PAGES" ls-tree -d HEAD "schemas/$VERSION")" ]]; then
    published=true
fi

rm -rf "$PAGES/schemas/$VERSION"
mkdir -p "$PAGES/schemas/$VERSION"
cp "${SCHEMAS[@]}" "$PAGES/schemas/$VERSION/"
git -C "$PAGES" add -A
if $published && ! $force && ! git -C "$PAGES" diff --cached --quiet -- "schemas/$VERSION"; then
    changed="$(git -C "$PAGES" diff --cached --name-status -- "schemas/$VERSION" | sed 's/^/  /')"
    git -C "$PAGES" reset --quiet --hard HEAD
    git -C "$PAGES" clean --quiet -fd
    echo "error: the schemas for $VERSION are published already, and these differ from them:" >&2
    echo "$changed" >&2
    echo "Files name a version's schemas by their URL, so they aren't replaced: give the schemas a new version, or give --force to replace them." >&2
    exit 1
fi
if git -C "$PAGES" diff --cached --quiet; then
    echo "The schemas for $VERSION are published already, as they are here."
else
    git -C "$PAGES" commit --quiet -m "Schemas for $VERSION, from $(git rev-parse --short HEAD)"
    git -C "$PAGES" push --quiet -u origin gh-pages
    echo "Published the schemas for $VERSION."
fi

serve_pages "schemas/$VERSION/"
