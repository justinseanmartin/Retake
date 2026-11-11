#!/usr/bin/env bash
# Publishes the example's showcase, the iPhone's and the iPad's side by side, to GitHub Pages at
# https://<owner>.github.io/Retake/showcase/, which the README links to: GitHub plays no video in a
# README but its own uploads, so the README shows the poster this writes, linking to a page that
# plays the video. Copies Example/Retake/output/share/'s side by side into showcase/ on the gh-pages
# branch, checked out in .pages/ (gitignored), with the poster and the page, commits, and pushes;
# and turns Pages on the first time. Replaces the showcase published before.
#
# Make the side by side first with Example/run.sh, on both devices, or --cut-only once both are
# recorded.
set -euo pipefail

usage() {
    echo "Usage: Scripts/publish-showcase.sh"
}
while (($#)); do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PAGES="$ROOT/.pages"
VIDEO="$ROOT/Example/Retake/output/share/showcase-iphone+showcase-ipad.mp4"
cd "$ROOT"

[[ -f "$VIDEO" ]] || { echo "error: there's no ${VIDEO#"$ROOT/"}; make it with Example/run.sh on both devices, or --cut-only once both are recorded" >&2; exit 1; }

source "$ROOT/Scripts/pages.sh"
open_pages

SHOWCASE="$PAGES/showcase"
mkdir -p "$SHOWCASE"
cp "$VIDEO" "$SHOWCASE/showcase.mp4"
# Its first frame and a half in, once the first caption is in.
swift "$ROOT/Scripts/showcase-poster.swift" "$VIDEO" "$SHOWCASE/poster.jpg" 1.5
cat >"$SHOWCASE/index.html" <<'EOF'
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Retake's showcase</title>
<meta name="description" content="The example's showcase, cut by Retake: touches, cuts, a spotlight, a blur, a drag, a turn, a card and a montage, each captioned.">
<meta property="og:title" content="Retake's showcase">
<meta property="og:image" content="poster.jpg">
<style>
  :root { color-scheme: dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-content: center; gap: 12px; padding: 16px;
         box-sizing: border-box; background: #3A3A3C; color: #F2F2F7;
         font: 15px/1.4 -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; text-align: center; }
  video { display: block; width: min(100%, 1236px); max-height: calc(100vh - 80px); border-radius: 8px; }
  a { color: #64D2FF; }
</style>
</head>
<body>
<video src="showcase.mp4" poster="poster.jpg" controls autoplay muted playsinline
       title="The example's showcase, cut by Retake: touches, cuts, a spotlight, a blur, a drag, a turn, a card and a montage, each captioned"></video>
<p>Made by <a href="https://github.com/justinseanmartin/Retake">Retake</a> from its example app, recorded on an iPhone and an iPad. It has sound: unmute it.</p>
</body>
</html>
EOF

git -C "$PAGES" add -A showcase .nojekyll
if git -C "$PAGES" diff --cached --quiet; then
    echo "The showcase is published already, as it is here."
else
    git -C "$PAGES" commit --quiet -m "Showcase, from $(git rev-parse --short HEAD)"
    git -C "$PAGES" push --quiet -u origin gh-pages
    echo "Published the showcase."
fi

serve_pages "showcase/"
