#!/usr/bin/env bash
# Builds a release of retake into the directory given: retake-<version>-macos-arm64.tar.gz, holding
# bin/retake and share/retake/ with the TheInsideJob framework and the support library it installs
# into apps, and its SHA-256 beside it. `mise use github:justinseanmartin/Retake` installs it. See
# Documentation/records/2026-10-26-v0.0.1-implementation-plan.md, commit 33.
#
# It builds only with the Xcode .xcode-version names, and never against a local clone of The Button
# Heist. With RETAKE_RELEASE_IDENTITY naming a Developer ID Application identity, it signs retake
# with the hardened runtime; with RETAKE_NOTARY_PROFILE naming a `notarytool store-credentials`
# profile as well, it has it notarized. Without them, the build is for trying the layout locally.
#
# Settings that are a person's own, such as their notary profile's name, go in
# Scripts/release.local.env, which git ignores (see Scripts/release.local.env.example); a variable
# already set in the environment wins over the file. With no RETAKE_RELEASE_IDENTITY, the keychain's
# one Developer ID Application identity is used, if it has exactly one.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/Scripts/release.local.env" ]]; then
    GIVEN_IDENTITY="${RETAKE_RELEASE_IDENTITY:-}"
    GIVEN_PROFILE="${RETAKE_NOTARY_PROFILE:-}"
    GIVEN_SCRATCH="${RETAKE_RELEASE_SCRATCH:-}"
    # shellcheck source=/dev/null
    source "$ROOT/Scripts/release.local.env"
    RETAKE_RELEASE_IDENTITY="${GIVEN_IDENTITY:-${RETAKE_RELEASE_IDENTITY:-}}"
    RETAKE_NOTARY_PROFILE="${GIVEN_PROFILE:-${RETAKE_NOTARY_PROFILE:-}}"
    RETAKE_RELEASE_SCRATCH="${GIVEN_SCRATCH:-${RETAKE_RELEASE_SCRATCH:-}}"
fi
if [[ -z "${RETAKE_RELEASE_IDENTITY:-}" ]]; then
    IDENTITIES="$(security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(Developer ID Application: .*\)"$/\1 \2/p')"
    case "$(printf '%s' "$IDENTITIES" | grep -c . || true)" in
        0) ;;
        1) RETAKE_RELEASE_IDENTITY="${IDENTITIES%% *}"; echo "Using ${IDENTITIES#* }" ;;
        *) echo "error: the keychain has several Developer ID Application identities; name one in RETAKE_RELEASE_IDENTITY:" >&2
           printf '%s\n' "$IDENTITIES" >&2; exit 2 ;;
    esac
fi
[[ $# -eq 1 ]] || { echo "usage: Scripts/release.sh <output-dir>" >&2; exit 2; }
OUTPUT="$(mkdir -p "$1" && cd "$1" && pwd)"
SCRATCH="${RETAKE_RELEASE_SCRATCH:-$OUTPUT/.build}"

if [[ -n "${RETAKE_BUTTONHEIST_PATH:-}" ]]; then
    echo "error: RETAKE_BUTTONHEIST_PATH is set; a release is built against The Button Heist's release, never a clone" >&2
    exit 1
fi
WANTED="$(tr -d '[:space:]' < "$ROOT/.xcode-version")"
# The command line tools alone have no xcodebuild to ask, which is no Xcode at all.
XCODE="$(xcodebuild -version 2>/dev/null | sed -n 's/^Xcode //p' || true)"
if [[ "$XCODE" != "$WANTED" ]]; then
    echo "error: a release is built with Xcode $WANTED, as .xcode-version says, but this is ${XCODE:+Xcode }${XCODE:-no Xcode}; select it with xcode-select or DEVELOPER_DIR" >&2
    exit 1
fi

echo "Building retake with Xcode $XCODE..."
swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --arch arm64 --product retake > "$OUTPUT/build.log" 2>&1 \
    || { tail -30 "$OUTPUT/build.log" >&2; exit 1; }
BINARY="$(swift build --package-path "$ROOT" --scratch-path "$SCRATCH" -c release --arch arm64 --product retake --show-bin-path)/retake"
VERSION="$("$BINARY" version --json | /usr/bin/python3 -I -c 'import json, sys; print(json.load(sys.stdin)["version"])')"

FRAMEWORK="$("$ROOT/Scripts/fetch-insidejob.sh" | tail -1)"
SUPPORT="$("$ROOT/Scripts/build-support.sh" | tail -1)"

STAGE="$OUTPUT/retake-$VERSION"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/share/retake"
cp "$BINARY" "$STAGE/bin/retake"
ditto "$FRAMEWORK" "$STAGE/share/retake/TheInsideJob.xcframework"
cp "$SUPPORT" "$STAGE/share/retake/RetakeSupport.dylib"
cp "$ROOT/LICENSE" "$STAGE/share/retake/LICENSE"

if [[ -n "${RETAKE_RELEASE_IDENTITY:-}" ]]; then
    echo "Signing with $RETAKE_RELEASE_IDENTITY..."
    codesign --force --timestamp --options runtime --entitlements "$ROOT/Scripts/retake.entitlements" \
        --sign "$RETAKE_RELEASE_IDENTITY" "$STAGE/bin/retake"
    codesign --verify --strict "$STAGE/bin/retake"
    if [[ -n "${RETAKE_NOTARY_PROFILE:-}" ]]; then
        echo "Notarizing..."
        ditto -c -k "$STAGE/bin/retake" "$OUTPUT/retake-notarize.zip"
        xcrun notarytool submit "$OUTPUT/retake-notarize.zip" --keychain-profile "$RETAKE_NOTARY_PROFILE" --wait
        rm "$OUTPUT/retake-notarize.zip"
    else
        echo "warning: not notarized; give RETAKE_NOTARY_PROFILE to notarize" >&2
    fi
else
    echo "warning: not signed with a Developer ID; give RETAKE_RELEASE_IDENTITY to sign for distribution" >&2
fi

ARCHIVE="retake-$VERSION-macos-arm64.tar.gz"
tar -C "$STAGE" -czf "$OUTPUT/$ARCHIVE" bin share
(cd "$OUTPUT" && shasum -a 256 "$ARCHIVE" > "$ARCHIVE.sha256")
echo "$OUTPUT/$ARCHIVE"
