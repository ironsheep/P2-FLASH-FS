#!/usr/bin/env bash
#
# check_docs.sh - documentation-drift checker: compares the driver with the files that
# describe it. Shell tools only (bash, awk, sed, grep, unzip, cmp).
#
# Checks, each reported under its own heading:
#   1. every PUB signature in flash_fs.spin2 (TEST_ methods excluded) against the
#      flash_fs.txt interface list and the per-method headings; locals after the `|`
#      are not part of the public signature and are ignored
#   2. the E_* codes in the driver's CON against the string_for_error cases (and that
#      each message begins with its code name), against the E_* names flash_fs.txt uses
#   3. version strings: LIB_VERSION (and its comment), the newest flash_fs.txt history
#      line (the driver header points to CHANGELOG.md for its history), README.md, CHANGELOG.md (absent is reported,
#      not an error) and DOCs/*.md "flash_fs vX.Y.Z" lines, all against LIB_VERSION
#   4. the `PASS P/T` (or `FAIL P/T`) count each RegresssionTests/README.md table row gives,
#      read with the first `(<name>.log)` link after it, against
#      the last `RESULT: PASS|FAIL <program> P/T` line of each RegresssionTests/*.log;
#      a log with no RESULT line is reported
#   5. the flash_fs.spin2 inside cgsm_flash_file_demo.zip (and cgsm_flash_file_demo/
#      flash_fs.spin2 when present, else reported as skipped) byte-identical to the
#      root driver
#
# Line prefixes: DRIFT a mismatch, INFO a fact worth knowing that is not drift,
# SKIP a check that could not run on an optional input, ok a clean comparison.
#
# Usage: tools/check_docs.sh [--root DIR]
#   --root DIR   check the tree at DIR instead of this script's parent
#
# Exit: 0 clean (no DRIFT), 1 at least one DRIFT, 2 usage error,
#       3 a required input is missing or unreadable (nothing was judged).

set -uo pipefail

die() { echo "check_docs: $2" >&2; exit "$1"; }

ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 ]] || die 2 "--root needs a directory"
            ROOT="$2"; shift 2 ;;
        -h|--help)
            awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        *) die 2 "unknown argument: $1 (try --help)" ;;
    esac
done
if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$ROOT" || die 3 "cannot enter $ROOT"

DRIVER="flash_fs.spin2"
APITXT="flash_fs.txt"
README="README.md"
TESTREADME="RegresssionTests/README.md"
ZIP="cgsm_flash_file_demo.zip"
DEMOCOPY="cgsm_flash_file_demo/flash_fs.spin2"
CHANGELOG="CHANGELOG.md"

drifts=0
skips=0
drift() { echo "DRIFT  $*"; drifts=$((drifts + 1)); }
info()  { echo "INFO   $*"; }
skip()  { echo "SKIP   $*"; skips=$((skips + 1)); }
ok()    { echo "ok     $*"; }

# ---- required inputs ----------------------------------------------------------------

missing=0
need_file() {
    if [[ ! -f "$1" || ! -r "$1" ]]; then
        echo "ERROR  required input missing or unreadable: $1" >&2
        missing=$((missing + 1))
    fi
}
for f in "$DRIVER" "$APITXT" "$README" "$TESTREADME" "$ZIP"; do need_file "$f"; done
if [[ ! -d DOCs ]]; then
    echo "ERROR  required input missing: DOCs/" >&2; missing=$((missing + 1))
fi
if ! command -v unzip >/dev/null 2>&1; then
    echo "ERROR  required tool missing: unzip" >&2; missing=$((missing + 1))
fi
if ! command -v cmp >/dev/null 2>&1; then
    echo "ERROR  required tool missing: cmp" >&2; missing=$((missing + 1))
fi
if [[ $missing -gt 0 ]]; then
    echo "check_docs: $missing required input(s) missing under $ROOT - nothing was judged" >&2
    exit 3
fi

TMP="$(mktemp)" || die 3 "cannot create a temporary file"
PROD="$(mktemp)" || die 3 "cannot create a temporary file"
trap 'rm -f "$TMP" "$PROD"' EXIT

# The regression-test block (from the REMOVE BEFORE FLIGHT line to the end) ships commented out
# and is not part of the public interface, so checks 1-3 read only the lines before it.
MARKER_LINE="$(grep -n 'REMOVE BEFORE FLIGHT' "$DRIVER" | head -n 1 | cut -d: -f1)"
if [[ -n "$MARKER_LINE" ]]; then
    head -n "$((MARKER_LINE - 1))" "$DRIVER" > "$PROD"
else
    cp "$DRIVER" "$PROD"
fi

echo ""
echo "Documentation drift - tree: $ROOT"

# ---- check 1: PUB signatures ----------------------------------------------------------

# load_sigs ARRAY ORDER - read PUB lines on stdin; ARRAY[name]=signature (locals dropped),
# ORDER gets the names in input order.
load_sigs() {
    local -n sigs=$1
    local -n order=$2
    local line name
    while IFS= read -r line; do
        line="${line%$'\r'}"
        line="${line%%|*}"
        line="${line%"${line##*[![:space:]]}"}"
        name="${line#PUB }"
        name="${name%%(*}"
        name="${name//[[:space:]]/}"
        sigs[$name]="$line"
        order+=("$name")
    done
}
sigkey() { local k="${1//[[:space:]]/}"; echo "$k"; }

echo ""
echo "== 1. PUB signatures: $DRIVER vs $APITXT"
declare -A DSIG LSIG SSIG
DORDER=(); LORDER=(); SORDER=()
load_sigs DSIG DORDER < <(grep -E '^PUB ' "$PROD" | grep -v -E '^PUB[[:space:]]+TEST_')
load_sigs LSIG LORDER < <(awk '/^Object .*Interface/ { inl = 1; next } inl && /^_+[[:space:]]*$/ { exit } inl && /^PUB / { print }' "$APITXT")
load_sigs SSIG SORDER < <(awk '/^_+[[:space:]]*$/ { seen = 1; next } seen && /^PUB / { print }' "$APITXT")
echo "       ${#DORDER[@]} driver PUBs, ${#LORDER[@]} in the interface list, ${#SORDER[@]} method headings"
c1=$drifts
for n in "${DORDER[@]}"; do
    if [[ -z "${LSIG[$n]+x}" ]]; then
        drift "PUB $n: in the driver, not in the $APITXT interface list"
    elif [[ "$(sigkey "${DSIG[$n]}")" != "$(sigkey "${LSIG[$n]}")" ]]; then
        drift "PUB $n: interface list differs - driver '${DSIG[$n]}' / txt '${LSIG[$n]}'"
    fi
    if [[ -z "${SSIG[$n]+x}" ]]; then
        drift "PUB $n: in the driver, no method heading in $APITXT"
    elif [[ "$(sigkey "${DSIG[$n]}")" != "$(sigkey "${SSIG[$n]}")" ]]; then
        drift "PUB $n: method heading differs - driver '${DSIG[$n]}' / txt '${SSIG[$n]}'"
    fi
done
for n in "${LORDER[@]}"; do
    [[ -n "${DSIG[$n]+x}" ]] || drift "PUB $n: in the $APITXT interface list, not in the driver"
done
for n in "${SORDER[@]}"; do
    [[ -n "${DSIG[$n]+x}" ]] || drift "PUB $n: has a method heading in $APITXT, not in the driver"
done
[[ ${#DORDER[@]} -gt 0 ]] || drift "no PUB found in $DRIVER"
[[ $drifts -eq $c1 ]] && ok "every driver PUB matches the interface list and its heading"

# ---- check 2: error codes -------------------------------------------------------------

echo ""
echo "== 2. error codes: CON vs string_for_error vs $APITXT"
c2=$drifts
declare -A CONVAL CASEMSG
CONORDER=()
while read -r name val; do
    CONVAL[$name]="$val"; CONORDER+=("$name")
done < <(sed -nE 's/^[[:space:]]+(E_[A-Z_0-9]+)[[:space:]]*=[[:space:]]*(-?[0-9]+).*/\1 \2/p' "$PROD")

CASEORDER=()
while IFS=$'\t' read -r label msg; do
    CASEMSG[$label]="$msg"; CASEORDER+=("$label")
done < <(awk '/^PUB string_for_error/ { inf = 1; next } inf && /^(PUB|PRI|CON)[[:space:]]/ { exit }
    inf && match($0, /^[[:space:]]+E_[A-Z_0-9]+:/) {
        line = $0
        sub(/^[[:space:]]+/, "", line)
        label = line; sub(/:.*/, "", label)
        msg = ""
        if (match(line, /@"[^"]*"/)) msg = substr(line, RSTART + 2, RLENGTH - 3)
        print label "\t" msg
    }' "$PROD")
echo "       ${#CONORDER[@]} E_* codes in CON, ${#CASEORDER[@]} in string_for_error"
[[ ${#CONORDER[@]} -gt 0 ]] || drift "no E_* code found in the CON of $DRIVER"
for n in "${CONORDER[@]}"; do
    if [[ -z "${CASEMSG[$n]+x}" ]]; then
        drift "$n (${CONVAL[$n]}): in CON, no case in string_for_error"
    elif [[ "${CASEMSG[$n]}" != "$n:"* ]]; then
        drift "$n: string_for_error text does not begin with '$n:' - '${CASEMSG[$n]}'"
    fi
done
for n in "${CASEORDER[@]}"; do
    [[ -n "${CONVAL[$n]+x}" ]] || drift "$n: string_for_error has a case, no such constant in CON"
done
declare -A TXTUSE
while read -r n; do
    TXTUSE[$n]=1
    [[ -n "${CONVAL[$n]+x}" ]] || drift "$n: named in $APITXT, no such constant in CON"
done < <(grep -o -w -E 'E_[A-Z_0-9]+' "$APITXT" | sort -u)
for n in "${CONORDER[@]}"; do
    [[ -n "${TXTUSE[$n]+x}" ]] || drift "$n (${CONVAL[$n]}): in CON, named in no $APITXT error list"
done
[[ $drifts -eq $c2 ]] && ok "CON, string_for_error and $APITXT agree"

# ---- check 3: version strings ---------------------------------------------------------

echo ""
echo "== 3. version strings"
c3=$drifts
libv="$(sed -nE 's/^[[:space:]]*LIB_VERSION[[:space:]]*=[[:space:]]*([0-9]+).*/\1/p' "$PROD" | head -n 1)"
if [[ -z "$libv" ]]; then
    drift "$DRIVER: no LIB_VERSION constant found"
else
    want="$((libv / 100)).$(((libv / 10) % 10)).$((libv % 10))"
    echo "       LIB_VERSION $libv = $want"
    # version_agrees FOUND MISSING-TEXT MISMATCH-PREFIX - one drift line when FOUND is empty
    # or differs from LIB_VERSION's X.Y.Z.
    version_agrees() {
        if [[ -z "$1" ]]; then
            drift "$2"
        elif [[ "$1" != "$want" ]]; then
            drift "$3 $1, LIB_VERSION is $want"
        fi
    }
    version_agrees "$(grep -E '^[[:space:]]*LIB_VERSION[[:space:]]*=' "$PROD" | head -n 1 | sed -nE "s/.*'[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/p")" \
        "$DRIVER: the LIB_VERSION line carries no X.Y.Z comment" "$DRIVER: LIB_VERSION comment says"
    version_agrees "$(grep -E '^ v[0-9]+\.[0-9]+\.[0-9]+' "$APITXT" | tail -n 1 | sed -nE 's/^ v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')" \
        "$APITXT: no ' vX.Y.Z' history line" "$APITXT: newest history line is"
    mapfile -t rv < <(grep -o -E '\bv?[0-9]+\.[0-9]+\.[0-9]+\b' "$README" | sort -u)
    if [[ ${#rv[@]} -eq 0 ]]; then
        info "$README: no full X.Y.Z version string"
    else
        for v in "${rv[@]}"; do
            [[ "${v#v}" == "$want" ]] || drift "$README: version string $v, LIB_VERSION is $want"
        done
    fi
    if [[ -f "$CHANGELOG" ]]; then
        version_agrees "$(grep -E '^#+ ' "$CHANGELOG" | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)" \
            "$CHANGELOG: no X.Y.Z version heading" "$CHANGELOG: newest version heading is"
    else
        info "$CHANGELOG: absent"
    fi
    shopt -s nullglob
    for d in DOCs/*.md; do
        mapfile -t dv < <(grep -o -E 'flash\\?_fs v[0-9]+\.[0-9]+\.[0-9]+' "$d" | grep -o -E '[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)
        if [[ ${#dv[@]} -eq 0 ]]; then
            info "$d: no 'flash_fs vX.Y.Z' line"
        else
            for v in "${dv[@]}"; do
                [[ "$v" == "$want" ]] || drift "$d: driver version $v, LIB_VERSION is $want"
            done
        fi
    done
    shopt -u nullglob
fi
[[ $drifts -eq $c3 ]] && ok "version strings agree"

# ---- check 4: test counts -------------------------------------------------------------

echo ""
echo "== 4. test counts: $TESTREADME vs RegresssionTests/*.log RESULT lines"
c4=$drifts
declare -A RPASS=() RFAIL=()
while IFS=$'\t' read -r name p t; do
    RPASS[$name]="$p"; RFAIL[$name]=$((t - p))
done < <(sed -nE 's/^\|.*[[:space:]](PASS|FAIL) ([0-9]+)\/([0-9]+)[^(]*\(([^)]*\.log)\).*/\4\t\2\t\3/p' "$TESTREADME" | sed 's/\\//g')
shopt -s nullglob
logs=(RegresssionTests/*.log)
shopt -u nullglob
echo "       ${#logs[@]} logs, ${#RPASS[@]} with counts in the README"
declare -A SEEN
for lg in "${logs[@]}"; do
    base="${lg##*/}"
    SEEN[$base]=1
    line="$(grep -E 'RESULT: (PASS|FAIL) ' "$lg" | tail -n 1)"
    if [[ -z "$line" ]]; then
        drift "$base: no RESULT line"
        continue
    fi
    if [[ ! "$line" =~ RESULT:\ (PASS|FAIL)\ ([^[:space:]]+)\ ([0-9]+)/([0-9]+) ]]; then
        drift "$base: unparseable RESULT line: $line"
        continue
    fi
    lp="${BASH_REMATCH[3]}"; lf=$((BASH_REMATCH[4] - BASH_REMATCH[3]))
    if [[ -z "${RPASS[$base]+x}" ]]; then
        drift "$base: has a RESULT line ($lp passes, $lf fails), the README lists no counts for it"
    elif [[ "${RPASS[$base]}" != "$lp" || "${RFAIL[$base]}" != "$lf" ]]; then
        drift "$base: README says ${RPASS[$base]} passes, ${RFAIL[$base]} fails; the log says $lp passes, $lf fails"
    fi
done
for base in "${!RPASS[@]}"; do
    [[ -n "${SEEN[$base]+x}" ]] || drift "$base: the README lists counts for it, no such log in RegresssionTests/"
done
[[ $drifts -eq $c4 ]] && ok "README counts match every log"

# ---- check 5: demo driver copies ------------------------------------------------------

echo ""
echo "== 5. demo driver copies vs $DRIVER"
c5=$drifts
mapfile -t members < <(unzip -Z1 "$ZIP" 2>/dev/null | grep -E '(^|/)flash_fs\.spin2$' | grep -v -E '^__MACOSX/')
if [[ ${#members[@]} -ne 1 ]]; then
    echo "ERROR  $ZIP holds ${#members[@]} flash_fs.spin2 members (need exactly 1) or cannot be listed" >&2
    exit 3
fi
if ! unzip -p "$ZIP" "${members[0]}" > "$TMP" 2>/dev/null; then
    echo "ERROR  cannot extract ${members[0]} from $ZIP" >&2
    exit 3
fi
out="$(cmp - "$DRIVER" < "$TMP" 2>&1)"
if [[ $? -eq 0 ]]; then
    ok "$ZIP:${members[0]} is byte-identical"
else
    drift "$ZIP:${members[0]} differs from $DRIVER - cmp: ${out#cmp: }"
fi
if [[ -f "$DEMOCOPY" ]]; then
    out="$(cmp "$DEMOCOPY" "$DRIVER" 2>&1)"
    if [[ $? -eq 0 ]]; then
        ok "$DEMOCOPY is byte-identical"
    else
        drift "$DEMOCOPY differs from $DRIVER - cmp: ${out#cmp: }"
    fi
else
    skip "$DEMOCOPY is absent (not compared)"
fi

# ---- summary --------------------------------------------------------------------------

echo ""
if [[ $drifts -gt 0 ]]; then
    echo "RESULT: DRIFT ($drifts finding(s), $skips skipped)"
    exit 1
fi
echo "RESULT: CLEAN (no drift, $skips skipped)"
exit 0
