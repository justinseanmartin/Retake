#!/usr/bin/env bash
# Builds everything a source checkout of Retake needs to run: retake itself, its support library,
# and The Button Heist's TheInsideJob, which it installs into apps. Prints the path of the retake
# it built, last and alone on standard output, so a script can build once and then run it:
#
#   retake="$(Scripts/build.sh)"
#   "$retake" install
#
# Builds into RETAKE_SCRATCH_PATH, or .build unless that's set. Each step is quick when there's
# nothing new to do.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
scratch=()
[[ -n "${RETAKE_SCRATCH_PATH:-}" ]] && scratch=(--scratch-path "$RETAKE_SCRATCH_PATH")

# Progress goes to standard error, so standard output is the path alone.
{
    echo "==> Building retake"
    (cd "$ROOT" && swift build -c release --product retake ${scratch[@]+"${scratch[@]}"})
    echo "==> Building Retake's support library"
    "$ROOT/Scripts/build-support.sh"
    echo "==> Getting TheInsideJob"
    "$ROOT/Scripts/fetch-insidejob.sh"
} >&2

echo "$(cd "$ROOT" && swift build -c release ${scratch[@]+"${scratch[@]}"} --show-bin-path)/retake"
