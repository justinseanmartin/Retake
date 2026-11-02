#!/usr/bin/env bash
# Builds Retake's support library, Support/*.m, as one dynamic library for iOS devices, into
# ~/Library/Caches/retake/support/<contract>/RetakeSupport.dylib, where a locally built retake
# finds it; a release carries it in share/retake/ instead. See Support/RetakeSupport.h.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${RETAKE_SUPPORT_CACHE:-$HOME/Library/Caches/retake/support}"
CONTRACT="$(sed -n 's/^#define RETAKE_SUPPORT_CONTRACT \([0-9][0-9]*\)$/\1/p' "$ROOT/Support/RetakeSupport.h")"
[[ -n "$CONTRACT" ]] || { echo "error: no RETAKE_SUPPORT_CONTRACT in Support/RetakeSupport.h" >&2; exit 1; }
DESTINATION="$CACHE/$CONTRACT"
mkdir -p "$DESTINATION"
xcrun -sdk iphoneos clang -arch arm64 -miphoneos-version-min=17.0 -dynamiclib -fobjc-arc -fmodules -O2 -Wall -Werror \
    -framework Foundation -framework UIKit -framework AVFoundation \
    -install_name "@executable_path/Frameworks/RetakeSupport.dylib" \
    -current_version "$CONTRACT" -compatibility_version "$CONTRACT" \
    "$ROOT"/Support/*.m -o "$DESTINATION/RetakeSupport.dylib"
echo "$DESTINATION/RetakeSupport.dylib"
