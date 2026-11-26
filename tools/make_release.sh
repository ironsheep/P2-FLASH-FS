#!/usr/bin/env bash
#
# make_release.sh - prepare the assets of a GitHub release from the committed tree.
# Shell tools only (bash, awk, sed, grep, unzip, cmp).
#
# Checks, each a refusal when it fails:
#   1. the tag is vX.Y.Z and matches LIB_VERSION in flash_fs.spin2
#   2. the newest CHANGELOG.md heading is "## <tag> (YYYY-MM-DD)" with a real date,
#      not the YYYY-MM-DD placeholder
#   3. the flash_fs.spin2 inside cgsm_flash_file_demo.zip is byte-identical to the root driver
#
# Output, in the output directory:
#   release-notes.md           the body of the tag's CHANGELOG section, for the release page
#   cgsm_flash_file_demo.zip   the tracked demo zip, as the release asset
#
# Usage: tools/make_release.sh <tag> [--out DIR]
#   <tag>       the release tag, e.g. v2.1.0
#   --out DIR   where to write the output (default: dist/ under the repo root)
#
# Exit: 0 ready, 1 a check refused, 2 usage error.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$ROOT/flash_fs.spin2"
CHANGELOG="$ROOT/CHANGELOG.md"
ZIP="$ROOT/cgsm_flash_file_demo.zip"
OUT="$ROOT/dist"
TAG=""

usage() { echo "usage: tools/make_release.sh <tag> [--out DIR]" >&2; exit 2; }
refuse() { echo "REFUSED  $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --out) [[ $# -ge 2 ]] || usage; OUT="$2"; shift 2 ;;
        -*) usage ;;
        *) [[ -z "$TAG" ]] || usage; TAG="$1"; shift ;;
    esac
done
[[ -n "$TAG" ]] || usage

# ---- check 1: the tag against LIB_VERSION ----------------------------------------------

[[ "$TAG" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || refuse "tag $TAG is not vX.Y.Z"
tagv="${TAG#v}"
libv="$(sed -nE 's/^[[:space:]]*LIB_VERSION[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$DRIVER" | head -n 1)"
[[ -n "$libv" ]] || refuse "no LIB_VERSION constant in flash_fs.spin2"
drvv="$((libv / 100)).$(((libv / 10) % 10)).$((libv % 10))"
[[ "$tagv" == "$drvv" ]] || refuse "tag $TAG, but LIB_VERSION $libv is $drvv"
echo "ok     tag $TAG matches LIB_VERSION $libv"

# ---- check 2: the newest CHANGELOG heading ----------------------------------------------

heading="$(grep -m 1 -E '^## ' "$CHANGELOG")"
[[ "$heading" =~ ^##\ (v[0-9]+\.[0-9]+\.[0-9]+)\ \((.*)\)$ ]] || refuse "newest CHANGELOG heading is not '## vX.Y.Z (date)': $heading"
[[ "${BASH_REMATCH[1]}" == "$TAG" ]] || refuse "newest CHANGELOG heading is ${BASH_REMATCH[1]}, not $TAG"
date="${BASH_REMATCH[2]}"
[[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || refuse "the $TAG CHANGELOG heading has no date yet: ($date)"
echo "ok     CHANGELOG heading: $heading"

# ---- check 3: the demo zip's driver copy -------------------------------------------------

mapfile -t members < <(unzip -Z1 "$ZIP" 2>/dev/null | grep -E '(^|/)flash_fs\.spin2$' | grep -v -E '^__MACOSX/')
[[ ${#members[@]} -eq 1 ]] || refuse "$(basename "$ZIP") holds ${#members[@]} flash_fs.spin2 members (need exactly 1)"
unzip -p "$ZIP" "${members[0]}" | cmp -s - "$DRIVER" || refuse "$(basename "$ZIP"):${members[0]} differs from flash_fs.spin2"
echo "ok     $(basename "$ZIP") holds the current driver"

# ---- output ---------------------------------------------------------------------------

mkdir -p "$OUT" || refuse "cannot create $OUT"
awk -v h="$heading" '
    $0 == h { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
' "$CHANGELOG" | sed -e '/./,$!d' > "$OUT/release-notes.md"
[[ -s "$OUT/release-notes.md" ]] || refuse "the $TAG CHANGELOG section is empty"
cp "$ZIP" "$OUT/" || refuse "cannot copy $(basename "$ZIP") to $OUT"
echo "ok     wrote $OUT/release-notes.md ($(wc -l < "$OUT/release-notes.md") lines) and $OUT/$(basename "$ZIP")"
