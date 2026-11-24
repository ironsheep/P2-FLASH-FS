#!/usr/bin/env bash
#
# check_style.sh - style gate for the tracked Spin2 sources, enforcing the
# mechanically checkable rules of the central Spin2 authoring guide
# (~/.claude/skills-docs/guides/spin2-authoring-guide.md).
#
# Output has three sections:
#   1. every implemented rule, PASS or FAIL, with findings as `file:line: rule - text`
#   2. the T1 and T1+T2 rules the guide assigns that this script does not check
#   3. the T2 rules left to an agent audit (T0 and T3 are named in one line each)
#
# The rule list, titles and tier counts are parsed from the guide's headings and
# its tier table at run time, so the lists cannot drift from the guide.
#
# Scope: every git-tracked *.spin2 file, plus the ```spin2 fenced examples in
# every git-tracked *.md file. The source-annotation check (guide section 4.11)
# runs over the repository as the guide's "The gate" section shows.
#
# Usage: tools/check_style.sh [--root DIR]
#   --root DIR   audit the git repository at DIR instead of this script's parent
#   STYLE_MAX=N  show at most N findings per rule (default 40, 0 = all)
#
# Exit: 0 no FAIL, 1 at least one FAIL, 2 usage error, 3 no .spin2 file examined.

set -uo pipefail

ROOT=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --root)
            [[ $# -ge 2 ]] || { echo "check_style: --root needs a directory" >&2; exit 2; }
            ROOT="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,25p' "${BASH_SOURCE[0]}" | cut -c3-
            exit 0 ;;
        *)
            echo "check_style: unknown argument: $1 (try --help)" >&2
            exit 2 ;;
    esac
done
if [[ -z "$ROOT" ]]; then
    ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$ROOT" || { echo "check_style: cannot enter $ROOT" >&2; exit 2; }

GUIDE="${SPIN2_GUIDE:-$HOME/.claude/skills-docs/guides/spin2-authoring-guide.md}"
ANNOTATION_CHECK="${ANNOTATION_CHECK:-$HOME/.claude/skills/build-wrapup/references/check-source-annotations.sh}"
MAXSHOW="${STYLE_MAX:-40}"
DASH=$'\xe2\x80\x94'

fails=0

# Rules this script checks, with the scope each check covers.
IMPLEMENTED=(1.1 1.4 1.8 1.9 2.1 2.1.4 2.4 3.1 3.2 4.1 4.2 4.2.1 4.5 4.9 4.11 5.0 5.1 5.2 5.3)
declare -A SCOPE=(
    [1.1]="every codepoint above 127 outside U+2500-U+259F, anywhere in a .spin2 file, comments included; in md fences, string literals"
    [1.4]="duplicate PUB/PRI method names within one file, compared case-insensitively"
    [1.8]="the literal @\"\" in code (md fences included)"
    [1.9]="an OBJ '|' override naming a constant the same file defines in its own CON"
    [2.1]="single-letter names in method signatures, VAR declarations and DAT data labels (md fences: signatures)"
    [2.1.4]="single-letter-plus-digit names (h1, h2) in method signatures"
    [2.4]="a local CON constant whose name an OBJ-declared tracked object already defines (constants marked user-overridable excepted)"
    [3.1]="{Spin2_v##} only on line 1; the first CON, OBJ, DAT/VAR and PUB blocks appear in guide order (a DAT/VAR block that first appears after the methods is allowed by 3.4)"
    [3.2]="no PUB method after the first PRI"
    [4.1]="'' doc comment inside CON/DAT/VAR/OBJ/PRI blocks or on a PUB @local line; {{ }} outside the license footer"
    [4.2]="a '' header block at line 1 (line 2 after a directive) naming File, Purpose, Author(s), E-mail, Started and Updated"
    [4.2.1]="file ends with a CON line plus {{ }} block containing the repo LICENSE text (copyright holder and year included)"
    [4.5]="'' on a CON/DAT/VAR/OBJ/PUB/PRI declaration line, a label-less or full-width border there, {Spin2_Doc_CON} on a CON line"
    [4.9]="a comment inside a CON block that is only a horizontal rule (3 or more of - _ = * # ~ + . or box-drawing)"
    [4.11]="check-source-annotations.sh over every tracked .spin2/.spin2h file"
    [5.0]="a parameter, return variable or local never named in the method body"
    [5.1]="a return variable with no assignment evidence in the body (detects the never-assigned case only)"
    [5.2]="a return statement that is not the last code line of its method"
    [5.3]="a return statement inside a repeat loop"
)

echo ""
echo "Spin2 style gate - guide: $GUIDE"
echo ""

if [[ ! -r "$GUIDE" ]]; then
    echo "FAIL  the authoring guide is not readable at $GUIDE - the rule list cannot be derived; the gate did not run"
    exit 1
fi

# ---- tracked files ----------------------------------------------------------

mapfile -t ALLSPIN < <(git ls-files '*.spin2' 2>/dev/null | sort)
FILES=()
for f in "${ALLSPIN[@]}"; do [[ -f "$f" ]] && FILES+=("$f"); done
mapfile -t ALLMD < <(git ls-files '*.md' 2>/dev/null | sort)
MDFILES=()
for f in "${ALLMD[@]}"; do [[ -f "$f" ]] && MDFILES+=("$f"); done

if [[ ${#FILES[@]} -eq 0 ]]; then
    echo "n/a  no git-tracked .spin2 file found under $ROOT - nothing examined"
    exit 3
fi
echo "Files examined: ${#FILES[@]} tracked .spin2 file(s); ${#MDFILES[@]} tracked .md file(s) scanned for spin2 fences"
echo ""

# ---- guide parse: tier table and rule headings ------------------------------

PARSED="$(perl -CSD -ne '
    if (/^###\s+(\d+(?:\.\d+)*)\s+(.*?)\s+\x{00B7}\s+\*\*(T[0-3](?:\+T2)?)\*\*\s*$/) {
        print "H\t$1\t$3\t$2\n"; next;
    }
    if (/^\|\s*\*\*(T[0-3](?:\+T2)?)\*\*\s*\|.*\|\s*(\d+)\s*\|\s*$/) {
        print "C\t$1\t$2\n"; next;
    }
' "$GUIDE")"

declare -A TITLE TIER TABLECOUNT PARSEDCOUNT
RULE_IDS=()
while IFS=$'\t' read -r kind a b c; do
    case "$kind" in
        H) RULE_IDS+=("$a"); TIER[$a]="$b"; TITLE[$a]="$c"
           PARSEDCOUNT[$b]=$(( ${PARSEDCOUNT[$b]:-0} + 1 )) ;;
        C) TABLECOUNT[$a]="$b" ;;
    esac
done <<< "$PARSED"

echo "Tier cross-check (guide table vs headings parsed at run time):"
for t in T0 T1 T1+T2 T2 T3; do
    want="${TABLECOUNT[$t]:-missing}"
    got="${PARSEDCOUNT[$t]:-0}"
    if [[ "$want" == "$got" ]]; then
        printf "  %-6s table %-3s parsed %-3s ok\n" "$t" "$want" "$got"
    else
        printf "  %-6s table %-3s parsed %-3s MISMATCH\n" "$t" "$want" "$got"
        echo "FAIL  tier table drift: $t table says $want, headings give $got"
        fails=$((fails + 1))
    fi
done
echo ""

for id in "${IMPLEMENTED[@]}"; do
    case "${TIER[$id]:-none}" in
        T1|T1+T2) ;;
        *) echo "FAIL  registry drift: rule $id is implemented here but is not a T1 or T1+T2 heading in the guide"
           fails=$((fails + 1)) ;;
    esac
done

# ---- the rule engine --------------------------------------------------------

read -r -d '' PERL_ENGINE <<'PERL_END'
use strict;
use warnings FATAL => 'all';
use Encode ();

my $root = shift @ARGV;
my $mode = shift @ARGV;
my @files = @ARGV;

sub emit {
    my ($rule, $file, $line, $text) = @_;
    $text =~ s/[\t\r\n]+/ /g;
    print join("\t", $rule, $file, $line, $text), "\n";
}

sub slurp {
    my ($f) = @_;
    open(my $fh, '<:raw', $f) or return ();
    local $/ = "\n";
    my @l = <$fh>;
    close $fh;
    for (@l) { chomp; s/\r$//; $_ = Encode::decode('UTF-8', $_, Encode::FB_DEFAULT); }
    return @l;
}

# Blank out string contents and comments, keeping line numbers and columns.
# Returns the code view, the line comment text per line, and the brace blocks.
sub strip_comments {
    my @raw = @_;
    my (@code, @cm, @blocks);
    my ($depth, $bstart, $bdbl) = (0, 0, 0);
    for my $ln (0 .. $#raw) {
        my $s = $raw[$ln];
        my $n = length $s;
        my ($o, $instr, $cmt) = ('', 0, undef);
        for (my $i = 0; $i < $n; $i++) {
            my $c = substr($s, $i, 1);
            if ($depth > 0) {
                if ($c eq '{') { $depth++ }
                elsif ($c eq '}') {
                    $depth--;
                    push @blocks, [$bstart, $ln, $bdbl] if $depth == 0;
                }
                $o .= ' ';
                next;
            }
            if ($instr) {
                if ($c eq '"') { $instr = 0; $o .= '"' } else { $o .= ' ' }
                next;
            }
            if ($c eq '"') { $instr = 1; $o .= '"'; next }
            if ($c eq "'") { $cmt = substr($s, $i); $o .= ' ' x ($n - $i); last }
            if ($c eq '{') {
                $depth = 1; $bstart = $ln;
                $bdbl = (substr($s, $i + 1, 1) eq '{') ? 1 : 0;
                $o .= ' ';
                next;
            }
            $o .= $c;
        }
        push @code, $o;
        push @cm, $cmt;
    }
    push @blocks, [$bstart, $#raw, $bdbl] if $depth > 0;
    return (\@code, \@cm, \@blocks);
}

sub parse_sig {
    my ($s) = @_;
    $s =~ s/^\s*(?:pub|pri)\s+//i;
    return unless $s =~ s/^([A-Za-z_]\w*)\s*//;
    my $name = $1;
    my ($p, $r, $l) = ('', '', '');
    if ($s =~ s/^\(([^)]*)\)\s*//) { $p = $1 }
    if ($s =~ s/^:\s*([^|]*)//)    { $r = $1 }
    if ($s =~ s/^\|\s*(.*)$//)     { $l = $1 }
    my @v;
    for my $pair (['param', $p], ['return', $r], ['local', $l]) {
        for my $piece (split /,/, $pair->[1]) {
            $piece =~ s/\[[^\]]*\]//g;
            $piece =~ s/=.*$//;
            $piece =~ s/\s+$//;
            push @v, [$pair->[0], $1] if $piece =~ /([A-Za-z_]\w*)\s*$/;
        }
    }
    return ($name, \@v);
}

# Constants a file defines in its CON blocks: lc name => 1-based line.
sub con_names {
    my ($code, $sec, $iskw) = @_;
    my %n;
    for my $i (0 .. $#$code) {
        next unless $sec->[$i] eq 'CON';
        my $l = $code->[$i];
        $l =~ s/^\s*con(?=\s|$)//i if $iskw->[$i];
        if ($l =~ /^\s*#/) {
            my @p = split /,/, $l;
            shift @p;
            for (@p) {
                s/\[[^\]]*\]//g; s/=.*//; s/^\s+|\s+$//g;
                $n{lc $_} //= $i + 1 if /^[A-Za-z_]\w*$/;
            }
            next;
        }
        while ($l =~ /(?:^|,)\s*([A-Za-z_]\w*)\s*(?:\[[^\]]*\])?\s*=(?!=)/g) {
            $n{lc $1} //= $i + 1;
        }
    }
    return \%n;
}

sub analyse {
    my ($f) = @_;
    my @raw = slurp($f);
    my ($code, $cm, $blocks) = strip_comments(@raw);
    my (@sec, @iskw);
    my $cur = '';
    for my $i (0 .. $#raw) {
        if ($code->[$i] =~ /^(con|dat|var|obj|pub|pri)(?=\s|$)/i) {
            $cur = uc $1;
            $iskw[$i] = $cur;
        }
        $sec[$i] = $cur;
    }
    return { raw => \@raw, code => $code, cm => $cm, blocks => $blocks, sec => \@sec, iskw => \@iskw };
}

sub indent_of {
    my ($t) = @_;
    $t =~ s/\t/        /g;
    return length(($t =~ /^( *)/)[0]);
}

sub norm_text {
    my ($t) = @_;
    $t = lc $t;
    $t =~ s/[^a-z0-9]//g;
    return $t;
}

my %tracked;
if ($mode eq 'spin2') {
    for my $f (@files) {
        (my $b = $f) =~ s{.*/}{};
        $b =~ s/\.spin2$//i;
        $tracked{lc $b} //= $f;
    }
}
my %objcache;

my $license_norm;
my $license_present = 0;
if ($mode eq 'spin2') {
    for my $cand (qw(LICENSE LICENSE.txt LICENSE.md)) {
        my $p = "$root/$cand";
        next unless -f $p;
        $license_present = 1;
        $license_norm = norm_text(join("\n", slurp($p)));
        last;
    }
}

sub check_spin2 {
    my ($f) = @_;
    my $an = analyse($f);
    my @raw = @{ $an->{raw} };
    my @code = @{ $an->{code} };
    my @cm = @{ $an->{cm} };
    my @sec = @{ $an->{sec} };
    my @iskw = @{ $an->{iskw} };
    my @blocks = @{ $an->{blocks} };
    my $last = $#raw;

    # 1.1
    for my $i (0 .. $last) {
        my (%seen, @bad);
        while ($raw[$i] =~ /([^\x00-\x7F])/g) {
            my $o = ord($1);
            next if $o >= 0x2500 && $o <= 0x259F;
            push @bad, sprintf("U+%04X", $o) unless $seen{$o}++;
        }
        emit('1.1', $f, $i + 1, 'non-ASCII ' . join(' ', @bad)) if @bad;
    }

    # 1.8
    for my $i (0 .. $last) {
        emit('1.8', $f, $i + 1, 'empty string literal @""') if index($code[$i], '@""') >= 0;
    }

    # methods
    my @methods;
    for my $i (0 .. $last) {
        next unless defined $iskw[$i] && $iskw[$i] =~ /^(?:PUB|PRI)$/;
        my $end = $last;
        for my $j ($i + 1 .. $last) {
            if (defined $iskw[$j]) { $end = $j - 1; last }
        }
        my ($name, $vars) = parse_sig($code[$i]);
        next unless defined $name;
        push @methods, { name => $name, vars => $vars, kind => $iskw[$i], start => $i, end => $end };
    }

    # 1.4
    my %seenm;
    for my $m (@methods) {
        my $k = lc $m->{name};
        if (exists $seenm{$k}) {
            emit('1.4', $f, $m->{start} + 1, "method $m->{name} is already declared at :" . ($seenm{$k} + 1));
        } else {
            $seenm{$k} = $m->{start};
        }
    }

    # 2.1 and 2.1.4: signatures
    for my $m (@methods) {
        for my $v (@{ $m->{vars} }) {
            if ($v->[1] =~ /^[A-Za-z]$/) {
                emit('2.1', $f, $m->{start} + 1, "single-letter $v->[0] name '$v->[1]' in $m->{name}");
            } elsif ($v->[1] =~ /^[A-Za-z]\d+$/) {
                emit('2.1.4', $f, $m->{start} + 1, "single-letter-plus-digit $v->[0] name '$v->[1]' in $m->{name}");
            }
        }
    }
    # 2.1: VAR declarations and DAT data labels
    for my $i (0 .. $last) {
        if ($sec[$i] eq 'VAR') {
            my $l = $code[$i];
            $l =~ s/^\s*var(?=\s|$)//i;
            next unless $l =~ /^\s*(?:byte|word|long)\s+(.+)$/i;
            for my $piece (split /,/, $1) {
                $piece =~ s/\[[^\]]*\]//g;
                $piece =~ s/^\s+|\s+$//g;
                emit('2.1', $f, $i + 1, "single-letter VAR name '$piece'") if $piece =~ /^[A-Za-z]$/;
            }
        } elsif ($sec[$i] eq 'DAT') {
            emit('2.1', $f, $i + 1, "single-letter DAT label '$1'")
                if $code[$i] =~ /^\s*([A-Za-z])\s+(?:byte|word|long|res)\b/i;
        }
    }

    # 3.2
    my ($firstpri, $lastpub);
    for my $m (@methods) {
        $firstpri //= $m->{start} if $m->{kind} eq 'PRI';
        $lastpub = $m->{start} if $m->{kind} eq 'PUB';
    }
    if (defined $firstpri && defined $lastpub && $lastpub > $firstpri) {
        emit('3.2', $f, $lastpub + 1, 'PUB follows the first PRI at :' . ($firstpri + 1));
    }

    # 3.1
    for my $i (1 .. $last) {
        emit('3.1', $f, $i + 1, 'Spin2 version directive is not on line 1')
            if $raw[$i] =~ /^\s*\{\s*Spin2_v\d+\s*\}/i;
    }
    {
        my %rank = (CON => 1, OBJ => 2, DAT => 3, VAR => 4, PUB => 5, PRI => 6);
        my %first;
        for my $i (0 .. $last) {
            next unless defined $iskw[$i];
            $first{$iskw[$i]} //= $i;
        }
        my @order = sort { $first{$a} <=> $first{$b} } keys %first;
        for my $k (1 .. $#order) {
            my ($prev, $this) = ($order[$k - 1], $order[$k]);
            next unless $rank{$this} < $rank{$prev};
            next if $this =~ /^(?:DAT|VAR)$/ && $prev =~ /^(?:PUB|PRI)$/;
            next if $this eq 'PUB' && $prev eq 'PRI';
            emit('3.1', $f, $first{$this} + 1,
                 "first $this block follows the first $prev block at :" . ($first{$prev} + 1) . " (guide order CON, OBJ, DAT, VAR, PUB)");
        }
    }

    # last non-blank raw line
    my $lastnb = $last;
    $lastnb-- while $lastnb >= 0 && $raw[$lastnb] =~ /^\s*$/;

    # 4.1
    for my $i (0 .. $last) {
        my $c = $cm[$i];
        next unless defined $c && $c =~ /^''/;
        my $s = $sec[$i];
        if ($s =~ /^(?:CON|DAT|VAR|OBJ)$/) {
            emit('4.1', $f, $i + 1, "'' doc comment inside a $s block");
        } elsif ($s eq 'PRI' && !defined $iskw[$i]) {
            emit('4.1', $f, $i + 1, "'' doc comment inside a PRI method");
        } elsif ($s eq 'PUB' && $c =~ /\@local/) {
            emit('4.1', $f, $i + 1, '@local tag uses doubled apostrophes');
        }
    }
    for my $b (@blocks) {
        next unless $b->[2];
        next if $b->[1] == $lastnb && $raw[$lastnb] =~ /^\s*\}\}\s*$/;
        emit('4.1', $f, $b->[0] + 1, '{{ }} block that is not the license footer');
    }

    # 4.5
    for my $i (0 .. $last) {
        next unless defined $iskw[$i];
        my $c = $cm[$i];
        if (defined $c) {
            if ($c =~ /^''/) {
                emit('4.5', $f, $i + 1, "'' on a $iskw[$i] declaration line");
            }
            (my $text = $c) =~ s/^'+\s*//;
            if ($text ne '' && $text !~ /[A-Za-z0-9]/) {
                emit('4.5', $f, $i + 1, "decorative border with no label on a $iskw[$i] declaration line");
            } elsif ($text =~ /[\x{2500}-\x{257F}_=*#~-]{8,}/) {
                emit('4.5', $f, $i + 1, "full-width border on a $iskw[$i] declaration line");
            }
        }
        emit('4.5', $f, $i + 1, '{Spin2_Doc_CON} on the CON declaration line')
            if $iskw[$i] eq 'CON' && $raw[$i] =~ /\{\s*Spin2_Doc_CON\s*\}/i;
    }

    # 4.9
    for my $i (0 .. $last) {
        next unless $sec[$i] eq 'CON' && !defined $iskw[$i];
        my $c = $cm[$i];
        next unless defined $c;
        (my $text = $c) =~ s/^'+\s*//;
        $text =~ s/\s+$//;
        emit('4.9', $f, $i + 1, 'horizontal rule comment inside a CON block')
            if $text =~ /^[\x{2500}-\x{259F}_=*#~+.-]{3,}$/;
    }

    # 4.2
    {
        my $start = ($last >= 0 && $raw[0] =~ /^\s*\{\s*Spin2_v\d+\s*\}\s*$/i) ? 1 : 0;
        if ($start > $last || $raw[$start] !~ /^''/) {
            emit('4.2', $f, $start + 1, "no '' header block at line " . ($start + 1));
        } else {
            my $h = '';
            my $j = $start;
            while ($j <= $last && $raw[$j] =~ /^''/) { $h .= "$raw[$j]\n"; $j++ }
            my @want = (
                ['File', qr/^''\s*File\b/im],
                ['Purpose', qr/^''\s*Purpose\b/im],
                ['Author(s)', qr/^''\s*Authors?\b/im],
                ['E-mail', qr/^''\s*E-?mail\b/im],
                ['Started', qr/^''\s*Started\b/im],
                ['Updated', qr/^''\s*Updated\b/im],
            );
            for my $w (@want) {
                emit('4.2', $f, $start + 1, "header block has no $w->[0] line") unless $h =~ $w->[1];
            }
        }
    }

    # 4.2.1
    {
        if (!$license_present) {
            emit('4.2.1', $f, $lastnb + 1, 'the repository has no LICENSE file');
        } elsif ($lastnb < 0 || $raw[$lastnb] !~ /^\s*\}\}\s*$/) {
            emit('4.2.1', $f, $lastnb + 1, 'the file does not end with a {{ }} license footer');
        } else {
            my ($fb) = grep { $_->[1] == $lastnb && $_->[2] } @blocks;
            if (!defined $fb) {
                emit('4.2.1', $f, $lastnb + 1, 'the last block is not a {{ }} block');
            } else {
                my $p = $fb->[0] - 1;
                $p-- while $p >= 0 && $raw[$p] =~ /^\s*$/;
                emit('4.2.1', $f, $fb->[0] + 1, 'the license block is not preceded by a CON line')
                    if $p < 0 || $raw[$p] !~ /^\s*con(?:\s|$)/i;
                my $text = join("\n", @raw[$fb->[0] .. $fb->[1]]);
                emit('4.2.1', $f, $fb->[0] + 1, 'the footer does not contain the repository LICENSE text (terms, copyright holder and year)')
                    if index(norm_text($text), $license_norm) < 0;
            }
        }
    }

    # 5.x per method
    for my $m (@methods) {
        my @idx = ($m->{start} + 1 .. $m->{end});
        my $body = join("\n", map { $code[$_] } @idx);

        # 5.0 and 5.1
        for my $v (@{ $m->{vars} }) {
            my $q = quotemeta $v->[1];
            my $mentioned = ($body =~ /(?<![\w.])$q(?!\w)/i);
            if (!$mentioned) {
                emit('5.0', $f, $m->{start} + 1, "$v->[0] '$v->[1]' of $m->{name} is never used in the body");
                next;
            }
            next unless $v->[0] eq 'return';
            my $assigned = 0;
            $assigned = 1 if $body =~ /(?<![\w.])$q\s*(?:\[[^\]]*\]\s*)?(?::=|(?:\/\/|<<|>>|[-+*\/\\&|^])=|\+\+|--|~~?)/i;
            $assigned = 1 if $body =~ /(?:\+\+|--)\s*$q(?!\w)/i;
            $assigned = 1 if $body =~ /\@$q(?!\w)/i;
            $assigned = 1 if $body =~ /\brepeat\s+$q\s+from\b/i;
            $assigned = 1 if $body =~ /(?<![\w.])(?:return|abort)\s+[^\s]/i;
            if (!$assigned) {
                for my $l (split /\n/, $body) {
                    if ($l =~ /^(.*?):=/ && $1 =~ /(?<![\w.])$q(?!\w)/i) { $assigned = 1; last }
                }
            }
            emit('5.1', $f, $m->{start} + 1, "return variable '$v->[1]' of $m->{name} is never assigned") unless $assigned;
        }

        # 5.2 and 5.3
        my $lastcode;
        for my $i (reverse @idx) {
            next if $code[$i] =~ /^\s*$/ || $code[$i] =~ /^\s*#/;
            $lastcode = $i;
            last;
        }
        my @loops;
        for my $i (@idx) {
            next if $code[$i] =~ /^\s*$/ || $code[$i] =~ /^\s*#/;
            my $ind = indent_of($code[$i]);
            pop @loops while @loops && $loops[-1] >= $ind;
            my $hasret = ($code[$i] =~ /(?<![\w.])return(?!\w)/i);
            if ($hasret) {
                emit('5.2', $f, $i + 1, "return before the end of $m->{name}")
                    if !defined $lastcode || $i != $lastcode;
                emit('5.3', $f, $i + 1, "return inside a repeat loop in $m->{name}") if @loops;
            }
            push @loops, $ind if $code[$i] =~ /^\s*repeat(?!\w)/i;
        }
    }

    # 1.9 and 2.4
    my $cons = con_names(\@code, \@sec, \@iskw);
    for my $i (0 .. $last) {
        next unless $sec[$i] eq 'OBJ';
        my $rawl = $raw[$i];
        next unless $rawl =~ /^\s*(?:obj\s+)?([A-Za-z_]\w*)(?:\[[^\]]*\])?\s*:\s*"([^"]+)"/i;
        my ($alias, $objfile) = ($1, $2);
        my $tail = $code[$i];
        my %overridden;
        if ($tail =~ /\|(.*)$/) {
            my $ov = $1;
            while ($ov =~ /([A-Za-z_]\w*)\s*=/g) {
                my $nm = lc $1;
                $overridden{$nm} = 1;
                emit('1.9', $f, $i + 1, "OBJ override of $1 while this file also defines $1 in CON at :$cons->{$nm}")
                    if exists $cons->{$nm};
            }
        }
        (my $base = $objfile) =~ s{.*/}{};
        $base =~ s/\.spin2$//i;
        my $path = $tracked{lc $base};
        next unless defined $path && $path ne $f;
        my $oc = $objcache{$path} //= do {
            my $oa = analyse($path);
            my $names = con_names($oa->{code}, $oa->{sec}, $oa->{iskw});
            my %ok;
            for my $nm (keys %$names) {
                my $ln = $names->{$nm};
                $ok{$nm} = $ln unless $oa->{raw}[$ln - 1] =~ /user-overridable/i;
            }
            \%ok;
        };
        for my $nm (sort keys %$cons) {
            next unless exists $oc->{$nm};
            next if $overridden{$nm};
            emit('2.4', $f, $cons->{$nm}, "CON constant $nm duplicates $alias.$nm ($path:$oc->{$nm})");
        }
    }
}

sub check_md {
    my ($f) = @_;
    my @raw = slurp($f);
    my ($in, $n) = (0, 0);
    for my $i (0 .. $#raw) {
        my $l = $raw[$i];
        if ($l =~ /^\s*```/) {
            if ($in) { $in = 0; next }
            (my $tag = $l) =~ s/^\s*```\s*//;
            $in = 1 if lc($tag) =~ /^spin2(?:\s|$)/;
            next;
        }
        next unless $in;
        next if $l =~ /^\s*'/;
        while ($l =~ /("[^"]*")/g) {
            my $s = $1;
            if ($s =~ /[^\x00-\x7F]/) {
                emit('1.1', $f, $i + 1, "non-ASCII in an example string literal: $s");
                last;
            }
        }
        emit('1.8', $f, $i + 1, 'empty string literal @"" in an example') if index($l, '@""') >= 0;
        if ($l =~ /^(?:pub|pri)\s+[A-Za-z_]/i) {
            (my $c = $l) =~ s/'.*$//;
            my ($name, $vars) = parse_sig($c);
            next unless defined $name;
            for my $v (@$vars) {
                if ($v->[1] =~ /^[A-Za-z]$/) {
                    emit('2.1', $f, $i + 1, "single-letter $v->[0] name '$v->[1]' in an example signature");
                } elsif ($v->[1] =~ /^[A-Za-z]\d+$/) {
                    emit('2.1.4', $f, $i + 1, "single-letter-plus-digit $v->[0] name '$v->[1]' in an example signature");
                }
            }
        }
    }
}

if ($mode eq 'spin2') { check_spin2($_) for @files }
else                  { check_md($_)    for @files }
PERL_END

declare -A COUNT BUCKET
record() {
    while IFS=$'\t' read -r rule file line text; do
        [[ -z "$rule" ]] && continue
        COUNT[$rule]=$(( ${COUNT[$rule]:-0} + 1 ))
        BUCKET[$rule]+="$file:$line: $rule $DASH $text"$'\n'
    done
}
ENGINE_FAILED=0
ENGINE_OUT="$(perl -CSD -e "$PERL_ENGINE" -- "$ROOT" spin2 "${FILES[@]}" 2>&1)" || ENGINE_FAILED=1
if [[ $ENGINE_FAILED -eq 0 && ${#MDFILES[@]} -gt 0 ]]; then
    MD_OUT="$(perl -CSD -e "$PERL_ENGINE" -- "$ROOT" md "${MDFILES[@]}" 2>&1)" || ENGINE_FAILED=1
    ENGINE_OUT+=$'\n'"$MD_OUT"
fi
if [[ $ENGINE_FAILED -eq 1 ]]; then
    echo "FAIL  the rule engine did not run; no rule below is a PASS:"
    echo "$ENGINE_OUT" | head -20
    exit 1
fi
record <<< "$ENGINE_OUT"

# ---- source-annotation check ------------------------------------------------

ANN_STATUS="unrun"
ANN_OUT=""
ANN_ERR=""
if [[ -x "$ANNOTATION_CHECK" ]]; then
    annerr="$(mktemp)"
    ANN_OUT="$(SOURCE_ANNOTATION_EXCLUDE="none" "$ANNOTATION_CHECK" --include '*.spin2' --include '*.spin2h' . 2>"$annerr")"
    ANN_STATUS=$?
    ANN_ERR="$(cat "$annerr")"
    rm -f "$annerr"
fi
case "$ANN_STATUS" in
    0) ANN_RESULT="PASS" ;;
    1) ANN_RESULT="FAIL"
       while IFS= read -r hit; do
           [[ -z "$hit" ]] && continue
           COUNT[4.11]=$(( ${COUNT[4.11]:-0} + 1 ))
           BUCKET[4.11]+="${hit%%: *}: 4.11 $DASH ${hit#*: }"$'\n'
       done <<< "$ANN_OUT" ;;
    3) ANN_RESULT="N/A" ;;
    *) ANN_RESULT="FAIL"
       COUNT[4.11]=1
       BUCKET[4.11]="(annotation check): 4.11 $DASH the check did not run (status $ANN_STATUS; script $ANNOTATION_CHECK)"$'\n' ;;
esac

# ---- section 1: implemented rules -------------------------------------------

echo "== 1. Implemented T1 rules =="
echo ""
for id in "${IMPLEMENTED[@]}"; do
    n="${COUNT[$id]:-0}"
    if [[ "$id" == "4.11" ]]; then
        result="$ANN_RESULT"
    elif [[ "$n" -eq 0 ]]; then
        result="PASS"
    else
        result="FAIL"
    fi
    [[ "$result" == "FAIL" ]] && fails=$((fails + 1))
    printf "%-4s %-6s %s [%s] - %s finding(s)\n" "$result" "$id" "${TITLE[$id]:-?}" "${TIER[$id]:-?}" "$n"
    echo "       scope: ${SCOPE[$id]}"
    if [[ "$n" -gt 0 ]]; then
        shown=0
        while IFS= read -r finding; do
            [[ -z "$finding" ]] && continue
            if [[ "$MAXSHOW" -gt 0 && "$shown" -ge "$MAXSHOW" ]]; then
                echo "       ... $((n - shown)) more (STYLE_MAX=0 shows all)"
                break
            fi
            echo "       $finding"
            shown=$((shown + 1))
        done <<< "${BUCKET[$id]}"
    fi
    if [[ "$id" == "4.11" ]]; then
        echo "       annotation check exit status: $ANN_STATUS${ANN_ERR:+; $(echo "$ANN_ERR" | tr '\n' ' ')}"
    fi
done
echo ""

# ---- section 2: assigned T1 rules not implemented ---------------------------

echo "== 2. T1 rules assigned but NOT implemented =="
declare -A ISIMPL
for id in "${IMPLEMENTED[@]}"; do ISIMPL[$id]=1; done
notimpl=0
for id in "${RULE_IDS[@]}"; do
    case "${TIER[$id]}" in
        T1|T1+T2)
            if [[ -z "${ISIMPL[$id]:-}" ]]; then
                printf "  %-6s %s [%s]\n" "$id" "${TITLE[$id]}" "${TIER[$id]}"
                notimpl=$((notimpl + 1))
            fi ;;
    esac
done
echo "  (${notimpl} rule(s); the gate reports this gap on every run)"
echo ""

# ---- section 3: T2 rules for the agent audit --------------------------------

echo "== 3. T2 rules NOT checked (agent audit) =="
t2=0
for id in "${RULE_IDS[@]}"; do
    if [[ "${TIER[$id]}" == "T2" ]]; then
        printf "  %-6s %s\n" "$id" "${TITLE[$id]}"
        t2=$((t2 + 1))
    fi
done
echo "  (${t2} rule(s))"
both=""
t0=""
t3=""
for id in "${RULE_IDS[@]}"; do
    case "${TIER[$id]}" in
        T1+T2) both+=" $id" ;;
        T0) t0+=" $id" ;;
        T3) t3+=" $id" ;;
    esac
done
echo "  T1+T2 rules whose findings an agent must judge:${both}"
echo "  T0 (the compiler rejects these):${t0}"
echo "  T3 (the owner's decisions, not checked):${t3}"
echo ""

if [[ $fails -gt 0 ]]; then
    echo "RESULT: FAIL ($fails failing item(s))"
    exit 1
fi
echo "RESULT: PASS (no FAIL on the implemented rules; sections 2 and 3 are still owed)"
exit 0
