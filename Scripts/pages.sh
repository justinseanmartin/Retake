# Sourced by the scripts that publish to GitHub Pages. Checks out the gh-pages branch in .pages/
# (gitignored), from origin's or begun empty when there's none yet, up to date and with nothing
# uncommitted, and turns Pages on the first time.

# Checks gh-pages out in $PAGES, which the caller sets.
open_pages() {
    if [[ ! -e "$PAGES/.git" ]]; then
        git worktree prune
        if git show-ref --verify --quiet refs/heads/gh-pages; then
            git worktree add "$PAGES" gh-pages
        elif git fetch --quiet origin gh-pages 2>/dev/null; then
            git worktree add -b gh-pages "$PAGES" FETCH_HEAD
            git -C "$PAGES" branch --quiet --set-upstream-to=origin/gh-pages
        else
            git worktree add --orphan -b gh-pages "$PAGES"
        fi
    fi
    [[ "$(git -C "$PAGES" symbolic-ref --quiet --short HEAD)" == gh-pages ]] \
        || { echo "error: .pages/ isn't on gh-pages; remove it with git worktree remove .pages, and run this again" >&2; exit 1; }
    [[ -z "$(git -C "$PAGES" status --porcelain)" ]] \
        || { echo "error: .pages/ has uncommitted changes; commit or discard them there first" >&2; exit 1; }
    if git -C "$PAGES" rev-parse --quiet --verify '@{upstream}' >/dev/null; then
        git -C "$PAGES" pull --quiet --ff-only
    fi
    # Served as they are, not through Jekyll.
    touch "$PAGES/.nojekyll"
}

# Turns Pages on, served from gh-pages's root, if it isn't yet, and prints where $1, a path on
# gh-pages, is served.
serve_pages() {
    if command -v gh >/dev/null && REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null)"; then
        if ! gh api "repos/$REPO/pages" >/dev/null 2>&1; then
            gh api -X POST "repos/$REPO/pages" -f 'source[branch]=gh-pages' -f 'source[path]=/' >/dev/null
            echo "Turned on GitHub Pages for $REPO, from gh-pages."
        fi
        OWNER="${REPO%%/*}"
        echo "Served, in a minute or so, at https://$(tr '[:upper:]' '[:lower:]' <<<"$OWNER").github.io/${REPO#*/}/$1"
    else
        echo "Turn on GitHub Pages for the repository, serving gh-pages from its root, if it isn't on already."
    fi
}
