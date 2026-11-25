#!/usr/bin/env bash
#
# run_tests.sh - hook-enabled test build and regression runner.
#
# Writes a hook-enabled copy of the driver to RegresssionTests/build/flash_fs.spin2
# (the one line containing REMOVE BEFORE FLIGHT gets its leading `{` changed to `'{`),
# compiles regression programs against it, and, on the macOS host, downloads and runs
# each program and reports it from the summary in its captured log.
# The shipped flash_fs.spin2 is only ever read. Every pnut-ts / pnut-term-ts command is
# echoed (prefixed `+ `) before it runs.
#
# Usage: tools/run_tests.sh [options] [PROGRAM ...]
#   PROGRAM            a regression program: RT_read_seek_tests, RT_read_seek_tests.spin2,
#                      or a path below RegresssionTests/build/ (e.g. build/mutants/M1.spin2).
#                      Default: every RegresssionTests/RT_*.spin2 (run mode skips RT_utilities).
#   --compile-only     generate and compile, do not run (the default off the macOS host)
#   --run              download, run and capture (the default on the macOS host)
#   --set NAME=VALUE   replace the default value of CON constant NAME in the generated copy
#                      (repeatable; e.g. --set MAX_FILES_OPEN=1)
#   --define SYMBOL    define preprocessor SYMBOL for every program compiled (pnut-ts -D;
#                      repeatable; e.g. --define FULL_FLASH_GUARD_ONLY)
#   --timeout SECONDS  per-program run timeout passed to pnut-term-ts (default 600)
#   --driver FILE      driver to copy instead of the repository's flash_fs.spin2
#   --judge LOGFILE    judge an existing log with the run-mode rules; generates and
#                      compiles nothing
#   -h, --help         show this text
#
# Output, one line per program, then a totals line:
#   PASS <prog> <pass>/<total>        run mode: the log shows Fail 0
#   FAIL <prog> <reason>              compile failure, any compiler output other than the
#                                     usual banner/Wrote/Done lines, Fail count above 0,
#                                     BAD TEST COUNTS, or a pnut-term-ts failure or timeout
#   UNKNOWN <prog> <reason>           no usable summary in the log, or truncated log
#   COMPILED <prog> <bytes> bytes     compile-only mode, compile succeeded
#   TOTAL <n> programs: <p> pass, <f> fail, <u> unknown, <c> compiled
# Log verdict: BAD TEST COUNTS anywhere is FAIL; else the last RESULT: PASS|FAIL line; else
# the last `Tests - Pass: P, Fail: F` line (Sub-Test lines excluded); else UNKNOWN.
#
# Files: compiled images go to RegresssionTests/build/bin/ (nothing is written beside the
# sources). Run mode writes the log to RegresssionTests/<prog>.log, overwriting it; a build/
# program writes beside itself as build/<path>.log, and a run of an RT_* program with --driver,
# --set or --define writes RegresssionTests/build/<prog>.DRIVER-<driver dir>.<NAME>-<VALUE>.<SYMBOL>.log
# (each part present only when its option is given), so tracked logs are replaced only
# by plain runs of RT_* programs. pnut-term-ts runs inside RegresssionTests/build/; the session
# log it writes to build/logs/ during the run becomes the program's log, and its standard
# output is used when it wrote none (the run says which).
#
# Exit: 0 every program passed or compiled, 1 any FAIL or UNKNOWN,
#       2 usage error or tool missing, 3 driver marker or --set match count is not 1.

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SELF_DIR/.." && pwd)"
TESTDIR="$ROOT/RegresssionTests"
BUILDDIR="$TESTDIR/build"
BINDIR="$BUILDDIR/bin"
DRIVER="$ROOT/flash_fs.spin2"
MARKER="REMOVE BEFORE FLIGHT"

MODE=""
TIMEOUT=600
JUDGE=""
DRIVERTAG=""
SETS=()
DEFINES=()
PROGS=()

die() { echo "run_tests: $2" >&2; exit "$1"; }

# judge_log FILE - sets VERDICT (PASS|FAIL|UNKNOWN) and DETAIL from a run log.
judge_log() {
    local f="$1" line p t
    VERDICT=UNKNOWN; DETAIL="no summary line in log"
    [[ -f "$f" ]] || { DETAIL="log not found: $f"; return; }
    if grep -q "BAD TEST COUNTS" "$f"; then
        VERDICT=FAIL; DETAIL="BAD TEST COUNTS in log"; return
    fi
    line=$(grep -E 'RESULT: (PASS|FAIL) ' "$f" | tail -n 1)
    if [[ -n "$line" ]]; then
        if [[ "$line" =~ RESULT:\ (PASS|FAIL)\ ([^[:space:]]+)\ ([0-9]+)/([0-9]+) ]]; then
            VERDICT="${BASH_REMATCH[1]}"; DETAIL="${BASH_REMATCH[3]}/${BASH_REMATCH[4]}"
            if [[ "$VERDICT" == PASS && "${BASH_REMATCH[3]}" != "${BASH_REMATCH[4]}" ]]; then
                VERDICT=FAIL; DETAIL="RESULT line says PASS but counts differ: $DETAIL"
            fi
        else
            DETAIL="unparseable RESULT line: $line"
        fi
        return
    fi
    line=$(grep -E 'Tests - Pass: [0-9]+, Fail: [0-9]+' "$f" | grep -v 'Sub-Test' | tail -n 1)
    if [[ "$line" =~ Pass:\ ([0-9]+),\ Fail:\ ([0-9]+) ]]; then
        p="${BASH_REMATCH[1]}"; t=$((p + BASH_REMATCH[2]))
        DETAIL="$p/$t"
        if [[ "${BASH_REMATCH[2]}" -eq 0 && "$p" -gt 0 ]]; then VERDICT=PASS; else VERDICT=FAIL; fi
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --compile-only) MODE=compile; shift ;;
        --run)          MODE=run; shift ;;
        --set)
            [[ $# -ge 2 ]] || die 2 "--set needs NAME=VALUE"
            SETS+=("$2"); shift 2 ;;
        --define)
            [[ $# -ge 2 && "$2" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || die 2 "--define needs a symbol name"
            DEFINES+=("$2"); shift 2 ;;
        --timeout)
            [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || die 2 "--timeout needs whole seconds"
            TIMEOUT="$2"; shift 2 ;;
        --driver)
            [[ $# -ge 2 ]] || die 2 "--driver needs a file"
            DRIVER="$2"
            # the name of the directory holding the driver tags the log of a run that uses it
            DRIVERTAG="$2"
            [[ "$2" == */* ]] && DRIVERTAG="${2%/*}"
            DRIVERTAG="DRIVER-${DRIVERTAG##*/}"
            DRIVERTAG="${DRIVERTAG//[^A-Za-z0-9_.-]/_}"
            shift 2 ;;
        --judge)
            [[ $# -ge 2 ]] || die 2 "--judge needs a log file"
            JUDGE="$2"; shift 2 ;;
        -h|--help)
            # the header comment block, from line 2 to the first non-comment line
            awk 'NR == 1 { next } !/^#/ { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
            exit 0 ;;
        -*) die 2 "unknown option: $1 (try --help)" ;;
        *)  PROGS+=("$1"); shift ;;
    esac
done

if [[ -n "$JUDGE" ]]; then
    judge_log "$JUDGE"
    name="$(basename "$JUDGE" .log)"
    echo "$VERDICT $name $DETAIL"
    [[ "$VERDICT" == PASS ]]
    exit $?
fi

[[ -f "$DRIVER" ]] || die 2 "driver not found: $DRIVER"
command -v pnut-ts >/dev/null 2>&1 || die 2 "pnut-ts not found on PATH"

if [[ -z "$MODE" ]]; then
    if [[ "$(uname -s)" == "Darwin" ]]; then MODE=run; else MODE=compile; fi
fi
if [[ "$MODE" == run ]]; then
    command -v pnut-term-ts >/dev/null 2>&1 || die 2 "run mode needs pnut-term-ts on PATH (use --compile-only)"
else
    echo "compile-only mode: nothing is downloaded or run"
fi

# ---- validate the --set overrides ---------------------------------------------------
SETNAMES=(); SETVALS=(); SETTAG=""
for s in ${SETS[@]+"${SETS[@]}"}; do
    if [[ ! "$s" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*([A-Za-z0-9_\$%.+-]+)[[:space:]]*$ ]]; then
        die 2 "--set needs NAME=VALUE with a single-token value: $s"
    fi
    SETNAMES+=("${BASH_REMATCH[1]}"); SETVALS+=("${BASH_REMATCH[2]}")
    tag="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}"
    SETTAG="${SETTAG:+$SETTAG.}${tag//[^A-Za-z0-9_.-]/_}"
done
# Each --define becomes a pnut-ts -D option, and joins the log tag so such a run never
# replaces a tracked log.
DEFARGS=()
for d in ${DEFINES[@]+"${DEFINES[@]}"}; do
    DEFARGS+=(-D "$d")
    SETTAG="${SETTAG:+$SETTAG.}$d"
done

# ---- generate the hook-enabled copy -------------------------------------------------
n=$(grep -c "$MARKER" "$DRIVER")
if [[ "$n" -ne 1 ]]; then
    echo "run_tests: expected exactly 1 line containing '$MARKER' in $DRIVER, found $n" >&2
    exit 3
fi
grep "$MARKER" "$DRIVER" | grep -q '^{' \
    || { echo "run_tests: the '$MARKER' line does not start with '{'" >&2; exit 3; }

# Each override must match exactly one single-token CON default line.
for i in ${SETNAMES[@]+"${!SETNAMES[@]}"}; do
    name="${SETNAMES[$i]}"
    n=$(grep -c -E "^[[:space:]]*$name[[:space:]]*=([^=]|\$)" "$DRIVER")
    if [[ "$n" -ne 1 ]]; then
        echo "run_tests: expected exactly 1 CON line declaring '$name' in $DRIVER, found $n" >&2
        exit 3
    fi
    n=$(grep -c -E "^[[:space:]]*$name[[:space:]]*=[[:space:]]*[^[:space:]']+[[:space:]]*('.*)?\$" "$DRIVER")
    if [[ "$n" -ne 1 ]]; then
        echo "run_tests: the '$name' default is not a single token, found $n single-token lines" >&2
        exit 3
    fi
done

mkdir -p "$BUILDDIR" "$BINDIR"
TMPGEN="$(mktemp "$BUILDDIR/.flash_fs.XXXXXX")" || die 2 "cannot create a temp file in $BUILDDIR"
TMPOUT=""
trap 'rm -f "$TMPGEN" "$TMPOUT"' EXIT
# One sed pass: the marker toggle, then one expression per --set override.
SEDARGS=(-e "/$MARKER/s/^\\{/'{/")
for i in ${SETNAMES[@]+"${!SETNAMES[@]}"}; do
    SEDARGS+=(-e "s/^([[:space:]]*${SETNAMES[$i]}[[:space:]]*=[[:space:]]*)[^[:space:]']+/\\1${SETVALS[$i]}/")
done
sed -E "${SEDARGS[@]}" "$DRIVER" > "$TMPGEN" || die 2 "generation failed"
mv "$TMPGEN" "$BUILDDIR/flash_fs.spin2"
echo "generated $BUILDDIR/flash_fs.spin2 from $DRIVER${SETTAG:+ with $SETTAG}"

# ---- resolve the program list -------------------------------------------------------
if [[ ${#PROGS[@]} -eq 0 ]]; then
    for f in "$TESTDIR"/RT_*.spin2; do
        [[ "$MODE" == run && "$(basename "$f")" == RT_utilities.spin2 ]] && continue
        PROGS+=("$(basename "$f")")
    done
fi

RESOLVED=()
for p in "${PROGS[@]}"; do
    p="${p#RegresssionTests/}"
    [[ "$p" == *.spin2 ]] || p="$p.spin2"
    case "$p" in
        build/*|RT_*) ;;
        *) die 2 "program must be RT_*.spin2 or a path below build/: $p" ;;
    esac
    [[ "$p" != *..* ]] || die 2 "program path may not contain '..': $p"
    [[ -f "$TESTDIR/$p" ]] || die 2 "program not found: RegresssionTests/$p"
    RESOLVED+=("$p")
done

# ---- compile, then run ----------------------------------------------------------------
NPASS=0; NFAIL=0; NUNK=0; NCOMP=0
TMPOUT="$(mktemp)" || die 2 "cannot create a temp file"
# Output lines a clean compile prints; anything else (errors, warnings) fails the program.
CLEAN_RE='^pnut-ts: (\* .*|Compiling with DEBUG|Wrote .* \([0-9,]+ bytes\)|Done)[[:space:]]*$'

for p in "${RESOLVED[@]}"; do
    base="${p%.spin2}"
    bin="$BINDIR/$base.bin"
    mkdir -p "$(dirname "$bin")"
    rm -f "$bin"
    # build/ holds the generated driver; "." lets a program below build/ find RT_utilities.
    echo "+ (in RegresssionTests/) pnut-ts -d${DEFARGS[*]:+ ${DEFARGS[*]}} -I build -I . -o $bin $p"
    (cd "$TESTDIR" && pnut-ts -d ${DEFARGS[@]+"${DEFARGS[@]}"} -I build -I . -o "$bin" "$p") > "$TMPOUT" 2>&1
    rc=$?
    cat "$TMPOUT"
    odd=$(grep -v -E "$CLEAN_RE" "$TMPOUT" | grep -v '^$' | head -n 1)
    if [[ $rc -ne 0 ]]; then
        echo "FAIL $p compile failed (pnut-ts exit $rc)${odd:+: $odd}"
        NFAIL=$((NFAIL + 1)); continue
    fi
    if [[ -n "$odd" ]]; then
        echo "FAIL $p unexpected compiler output (warning?): $odd"
        NFAIL=$((NFAIL + 1)); continue
    fi
    bytes=$(sed -n 's/.*Wrote .*(\([0-9][0-9,]*\) bytes).*/\1/p' "$TMPOUT" | tail -n 1)
    if [[ -z "$bytes" || ! -f "$bin" ]]; then
        echo "FAIL $p compile reported no output image"
        NFAIL=$((NFAIL + 1)); continue
    fi

    if [[ "$p" == build/* ]]; then
        log="$TESTDIR/$base${SETTAG:+.$SETTAG}.log"
    elif [[ -n "$DRIVERTAG$SETTAG" ]]; then
        log="$BUILDDIR/$base.${DRIVERTAG}${DRIVERTAG:+${SETTAG:+.}}${SETTAG}.log"
    else
        log="$TESTDIR/$base.log"
    fi

    if [[ "$MODE" == compile ]]; then
        echo "COMPILED $p $bytes bytes (compile-only, nothing run; a run would log to $log)"
        NCOMP=$((NCOMP + 1)); continue
    fi

    # pnut-term-ts writes its session log to logs/ under its working directory, so it runs
    # inside the gitignored build tree; the newest log written during this run becomes the
    # program's log, and its standard output is the fallback when it wrote none.
    mkdir -p "$BUILDDIR/logs"
    stamp="$BUILDDIR/logs/.run-start"
    : > "$stamp"
    echo "+ (in RegresssionTests/build/) pnut-term-ts --headless -r $bin --end-marker --timeout $TIMEOUT"
    (cd "$BUILDDIR" && pnut-term-ts --headless -r "$bin" --end-marker --timeout "$TIMEOUT") > "$TMPOUT" 2>&1
    rc=$?
    cat "$TMPOUT"
    newest=$(find "$BUILDDIR/logs" -type f -name '*.log' -newer "$stamp" -exec ls -t {} + 2>/dev/null | head -n 1)
    if [[ -n "$newest" ]]; then
        cp "$newest" "$log"
        echo "log: $newest -> $log"
    else
        cp "$TMPOUT" "$log"
        echo "log: no session log in $BUILDDIR/logs; standard output -> $log"
    fi
    rm -f "$stamp"
    case $rc in
        0)   judge_log "$log" ;;
        124) VERDICT=FAIL; DETAIL="timed out after ${TIMEOUT}s (pnut-term-ts exit 124)" ;;
        125) VERDICT=UNKNOWN; DETAIL="shutdown drain timed out, log may be truncated (exit 125)" ;;
        *)   VERDICT=FAIL; DETAIL="pnut-term-ts exit $rc (1 port, 2 bad command line, 3 download failed)" ;;
    esac
    echo "$VERDICT $p $DETAIL"
    case $VERDICT in
        PASS) NPASS=$((NPASS + 1)) ;;
        FAIL) NFAIL=$((NFAIL + 1)) ;;
        *)    NUNK=$((NUNK + 1)) ;;
    esac
done

echo "TOTAL ${#RESOLVED[@]} programs: $NPASS pass, $NFAIL fail, $NUNK unknown, $NCOMP compiled"
[[ $NFAIL -eq 0 && $NUNK -eq 0 ]]
