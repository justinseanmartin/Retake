#!/usr/bin/env bash
# Puts the TheInsideJob framework a locally built retake installs into apps where it finds it:
# ~/Library/Caches/retake/insidejob/<version>/TheInsideJob.xcframework, for the release of The
# Button Heist Package.resolved pins, downloaded and checked against the release's checksums. With
# RETAKE_BUTTONHEIST_PATH naming a local clone, it builds the framework from the clone instead, into
# …/insidejob/clone/, recording the clone's path and commit. See README.md, "Building from source".
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CACHE="${RETAKE_INSIDEJOB_CACHE:-$HOME/Library/Caches/retake/insidejob}"
REPOSITORY="https://github.com/TheButtonHeist/TheButtonHeist"

if [[ -n "${RETAKE_BUTTONHEIST_PATH:-}" ]]; then
    CLONE="$(cd "$RETAKE_BUTTONHEIST_PATH" && pwd)"
    COMMIT="$(git -C "$CLONE" rev-parse HEAD)"
    [[ -z "$(git -C "$CLONE" status --porcelain)" ]] || COMMIT="$COMMIT-dirty"
    VERSION="$(sed -n 's/.*let buttonHeistVersion: ButtonHeistVersion = "\(.*\)".*/\1/p' "$CLONE/ButtonHeist/Sources/TheScore/Wire/Messages.swift")"
    [[ -n "$VERSION" ]] || { echo "error: couldn't find the clone's version in TheScore/Wire/Messages.swift" >&2; exit 1; }
    DESTINATION="$CACHE/clone"
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/retake-insidejob.XXXXXX")"
    trap 'rm -rf "$WORK"' EXIT
    echo "Building TheInsideJob $VERSION from $CLONE ($COMMIT)..."
    (cd "$ROOT/InsideJob" && RETAKE_BUTTONHEIST_PATH="$CLONE" xcodebuild build -scheme RetakeInsideJob -configuration Debug \
        -destination 'generic/platform=iOS' -derivedDataPath "$WORK/DerivedData" -skipPackagePluginValidation \
        CODE_SIGNING_ALLOWED=NO > "$WORK/build.log" 2>&1) || { tail -30 "$WORK/build.log" >&2; exit 1; }
    PRODUCTS="$WORK/DerivedData/Build/Products/Debug-iphoneos"
    # The release's layout: the framework named TheInsideJob, its resource bundles inside it.
    FRAMEWORK="$WORK/TheInsideJob.framework"
    cp -R "$PRODUCTS/PackageFrameworks/RetakeInsideJob.framework" "$FRAMEWORK"
    mv "$FRAMEWORK/RetakeInsideJob" "$FRAMEWORK/TheInsideJob"
    install_name_tool -id @rpath/TheInsideJob.framework/TheInsideJob "$FRAMEWORK/TheInsideJob" 2>/dev/null
    /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable TheInsideJob" -c "Set :CFBundleName TheInsideJob" "$FRAMEWORK/Info.plist"
    shopt -s nullglob
    for bundle in "$PRODUCTS"/*.bundle; do cp -R "$bundle" "$FRAMEWORK/"; done
    rm -rf "$DESTINATION"
    mkdir -p "$DESTINATION"
    xcodebuild -create-xcframework -framework "$FRAMEWORK" -output "$DESTINATION/TheInsideJob.xcframework" > /dev/null
    printf '%s\n' "$VERSION" > "$DESTINATION/TheInsideJob.xcframework/VERSION"
    printf '{"path": "%s", "commit": "%s"}\n' "$CLONE" "$COMMIT" > "$DESTINATION/clone.json"
    echo "$DESTINATION/TheInsideJob.xcframework"
    exit 0
fi

VERSION="$(/usr/bin/python3 -I -c '
import json, sys
pins = json.load(open(sys.argv[1]))["pins"]
print(next(pin["state"]["version"] for pin in pins if pin["identity"] == "thebuttonheist"))
' "$ROOT/Package.resolved")"
DESTINATION="$CACHE/$VERSION"
if [[ -f "$DESTINATION/TheInsideJob.xcframework/VERSION" && "$(cat "$DESTINATION/TheInsideJob.xcframework/VERSION")" == "$VERSION" ]]; then
    echo "$DESTINATION/TheInsideJob.xcframework"
    exit 0
fi
WORK="$(mktemp -d "${TMPDIR:-/tmp}/retake-insidejob.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
RELEASE="$REPOSITORY/releases/download/v$VERSION"
echo "Downloading TheInsideJob $VERSION..."
curl -fsSL -o "$WORK/theinsidejob-$VERSION.zip" "$RELEASE/theinsidejob-$VERSION.zip"
curl -fsSL -o "$WORK/checksums.txt" "$RELEASE/checksums.txt"
(cd "$WORK" && awk -v file="theinsidejob-$VERSION.zip" '$2 == file' checksums.txt | shasum -a 256 -c --status) \
    || { echo "error: theinsidejob-$VERSION.zip doesn't match the release's checksum" >&2; exit 1; }
mkdir -p "$WORK/unpacked"
ditto -x -k "$WORK/theinsidejob-$VERSION.zip" "$WORK/unpacked"
[[ "$(cat "$WORK/unpacked/TheInsideJob.xcframework/VERSION")" == "$VERSION" ]] \
    || { echo "error: the release's framework names another version" >&2; exit 1; }
rm -rf "$DESTINATION"
mkdir -p "$DESTINATION"
mv "$WORK/unpacked/TheInsideJob.xcframework" "$DESTINATION/"
echo "$DESTINATION/TheInsideJob.xcframework"
