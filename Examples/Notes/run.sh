#!/usr/bin/env bash
# Runs the Notes example from a fresh clone of Retake: builds retake and what it installs, signs
# Notes with your team, installs it on the connected device, records its scenes, cuts its video,
# and makes a small copy of the video, to share or check in. See Examples/README.md.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: Examples/Notes/run.sh [--team <id>] [--device <device>] [--setup | --cut-only] [--readme]

  --team <id>        The development team to sign Notes with. Without it: the one already in
                     Config/Signing.local.xcconfig, then RETAKE_SIGNING_IDENTITY's, then the only
                     team with an Apple Development identity in the keychain (it asks when several do).
  --device <device>  The device to use, by alias, UDID or name; the only one connected otherwise.
  --setup            Stop once retake is built and Notes can be signed, and say what to run next.
  --cut-only         Cut from the takes already recorded, with no device: after changing an edit.
                     Give --device or set RETAKE_DEVICE_TYPE (iphone or ipad) to say whose.
  --readme           Write the iPhone's and iPad's showcases, side by side, to Documentation/media/,
                     which the README shows: both devices' cuts are needed.

It cuts edits/showcase.json, every feature in one video, for the device's type. A small copy, an
MP4 with sound, is written to Retake/output/share/, and once both an iPhone's and an iPad's are
cut, the two side by side too.
EOF
}

team="" device="" setup=false cut_only=false readme=false
while (($#)); do
    case "$1" in
        --team) team="${2:?--team needs a team ID}"; shift 2 ;;
        --device) device="${2:?--device needs a device}"; shift 2 ;;
        --setup) setup=true; shift ;;
        --cut-only) cut_only=true; shift ;;
        --readme) readme=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 2 ;;
    esac
done

EXAMPLE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$EXAMPLE/../.." && pwd)"
LOCAL="$EXAMPLE/Config/Signing.local.xcconfig"
step() { printf '\n==> %s\n' "$*"; }
fail() { echo "error: $*" >&2; exit 1; }

# The team ID is the organizational unit of a signing identity's certificate.
team_of() { security find-certificate -c "$1" -p 2>/dev/null | openssl x509 -noout -subject -nameopt multiline | sed -n 's/^ *organizationalUnitName *= *//p'; }
organization_of() { security find-certificate -c "$1" -p 2>/dev/null | openssl x509 -noout -subject -nameopt multiline | sed -n 's/^ *organizationName *= *//p'; }
# Each valid development identity in the keychain, as "<SHA-1> <name>".
identities() { security find-identity -v -p codesigning | sed -n 's/^ *[0-9]*) \([0-9A-F]\{40\}\) "\(Apple Development: .*\)"$/\1 \2/p'; }

choose_team() {
    if [[ -n "${RETAKE_SIGNING_IDENTITY:-}" ]]; then
        local name="$RETAKE_SIGNING_IDENTITY"
        if [[ "$name" =~ ^[0-9A-Fa-f]{40}$ ]]; then
            name="$(identities | awk -v sha="$(tr '[:lower:]' '[:upper:]' <<<"$name")" '$1 == sha { $1 = ""; sub(/^ /, ""); print }')"
        fi
        local found; found="$(team_of "$name")"
        [[ -n "$found" ]] || fail "RETAKE_SIGNING_IDENTITY ($RETAKE_SIGNING_IDENTITY) isn't a development identity in the keychain."
        echo "Using RETAKE_SIGNING_IDENTITY's team, $found." >&2
        echo "$found"
        return
    fi
    local teams=() organizations=() line
    while read -r line; do
        local name="${line#* }" id; id="$(team_of "$name")"
        [[ -n "$id" && " ${teams[*]:-} " != *" $id "* ]] || continue
        teams+=("$id"); organizations+=("$(organization_of "$name")")
    done < <(identities)
    case ${#teams[@]} in
        0) fail "there's no Apple Development identity in the keychain. Sign in to your Apple account in Xcode's Settings > Accounts, then run this again." ;;
        1) echo "Using the only team with a development identity, ${teams[0]} (${organizations[0]})." >&2; echo "${teams[0]}" ;;
        *)
            [[ -t 0 ]] || fail "several teams have development identities; give one with --team: $(printf '%s ' "${teams[@]}")"
            echo "Several teams have development identities in the keychain:" >&2
            local i
            for i in "${!teams[@]}"; do echo "  $((i + 1))) ${teams[$i]} (${organizations[$i]})" >&2; done
            read -r -p "Which should Notes be signed with? " i
            [[ "$i" =~ ^[0-9]+$ ]] && ((i >= 1 && i <= ${#teams[@]})) || fail "no team $i."
            echo "${teams[$((i - 1))]}"
            ;;
    esac
}

# The tools.
command -v xcrun >/dev/null || fail "Xcode isn't installed, or isn't selected: run xcode-select -s /Applications/Xcode.app."

step "Building Retake"
retake="$("$ROOT/Scripts/build.sh")"

# Signing: Config/Signing.local.xcconfig, which isn't checked in.
step "Signing Notes"
current="$( [[ -f "$LOCAL" ]] && sed -n 's/^ *DEVELOPMENT_TEAM *= *\([A-Z0-9]*\).*/\1/p' "$LOCAL" | tail -n1 || true)"
if [[ -n "$team" || -z "$current" ]]; then
    [[ -n "$team" ]] || team="$(choose_team)"
    [[ "$team" =~ ^[A-Z0-9]{10}$ ]] || fail "\"$team\" isn't a team ID, which is ten letters and digits."
    if [[ -f "$LOCAL" ]] && grep -q '^ *DEVELOPMENT_TEAM' "$LOCAL"; then
        sed -i '' "s/^ *DEVELOPMENT_TEAM *=.*/DEVELOPMENT_TEAM = $team/" "$LOCAL"
    else
        printf '// Written by run.sh; not checked in.\nDEVELOPMENT_TEAM = %s\n' "$team" >>"$LOCAL"
    fi
    echo "Wrote the team to Config/Signing.local.xcconfig."
else
    team="$current"
    echo "Signing with $team, from Config/Signing.local.xcconfig."
fi

cd "$EXAMPLE"
if $setup; then
    cat <<EOF

Set up. From Examples/Notes, with a device connected by USB:

  alias retake="$retake"
  retake devices add ipad          # or iphone; names the connected device
  retake install
  retake record                    # every scene for the device's type
  retake cut showcase --open
EOF
    exit 0
fi

# The device, and so which edit to cut.
[[ -n "$device" ]] && export RETAKE_DEVICE="$device"
type="${RETAKE_DEVICE_TYPE:-}"
if [[ -z "$type" ]] || ! $cut_only; then
    devices="$("$retake" devices --json)"
    type="$(python3 -I -c '
import json, sys
listing = json.load(sys.stdin)
uses = (listing.get("uses") or {}).get("device")
if uses is None:
    sys.exit("several devices are connected, or none: give --device")
for entry in listing["devices"] + listing["aliases"]:
    if uses in (entry.get("udid"), entry.get("alias"), entry.get("name")):
        print(entry["type"]); break
else:
    sys.exit("the device chosen, " + uses + ", isn\x27t an iPhone or iPad")
' <<<"$devices")" || fail "couldn't choose a device; see retake devices."
fi
[[ "$type" == iphone || "$type" == ipad ]] || fail "RETAKE_DEVICE_TYPE is iphone or ipad, not \"$type\"."
edit=showcase

if ! $cut_only; then
    step "Installing Notes"
    "$retake" install
    # --force, so running this again records the app as it is now.
    step "Recording the scenes"
    "$retake" record --force
fi

step "Cutting $edit"
"$retake" cut "$edit" --type "$type"

# Small enough to check in, and still sharp: 720 points wide.
step "Making a small copy"
command -v ffmpeg >/dev/null || fail "the small copy needs ffmpeg: brew install ffmpeg, then run this again with --cut-only."
share="Retake/output/share"
mkdir -p "$share"
mp4() { ffmpeg -v error -y "$@" -c:v libx264 -preset veryslow -crf 25 -pix_fmt yuv420p -tune animation -movflags +faststart -c:a aac -b:a 80k -ac 1 -map_metadata -1; }
master() { echo "Retake/output/cuts/$1/$edit/$edit-$1-master.mov"; }
mp4 -i "$(master "$type")" -vf "scale=720:-2:flags=lanczos" "$share/$edit-$type.mp4"
made=("$share/$edit-$type.mp4")

# Both devices' cuts of the one edit side by side, the iPhone's on the left, on the edit's own
# background, with the iPad's sound.
if [[ -f "$(master iphone)" && -f "$(master ipad)" ]]; then
    side() { echo "[0:v]scale=-2:$1:flags=lanczos,pad=iw+$2*2:ih+$2*2:$2:$2:color=0x1B2A4E[a];[1:v]scale=-2:$1:flags=lanczos,pad=iw+$2:ih+$2*2:0:$2:color=0x1B2A4E[b];[a][b]hstack"; }
    mp4 -i "$(master iphone)" -i "$(master ipad)" -filter_complex "$(side 960 24)[v]" -map "[v]" -map 1:a "$share/$edit-both.mp4"
    made+=("$share/$edit-both.mp4")
fi

if $readme; then
    [[ -f "$share/$edit-both.mp4" ]] || fail "--readme shows the iPhone's and the iPad's side by side: record and cut on both, then run this again with --cut-only --readme."
    mkdir -p "$ROOT/Documentation/media"
    cp "$share/$edit-both.mp4" "$ROOT/Documentation/media/showcase.mp4"
    made=("$ROOT/Documentation/media/showcase.mp4")
fi
ls -l "${made[@]}"
