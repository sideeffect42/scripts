#!/usr/bin/env python3
#
# Produces a unified diff of two files, but only for lines where a difference
# overlaps with a regex match.
# Added/removed lines are ignored.
#
# usage: python3 diff-by-regex.py file1 file2 regex
#

import difflib
import re
import sys

from collections import (OrderedDict, Counter)


class Hunk:
    """Class to represent a raw diff hunk (i.e. a range line and two sets of
    lines (before and after)).
    """
    __slots__ = ("range", "lines_a", "lines_b")

    class Range:
        """Structured representation of a range line ("@@ ... @@")."""
        __re_range = re.compile(
            r"^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@$")
        __slots__ = ("a_begin", "a_lines", "b_begin", "b_lines")

        def __init__(self, a_begin, a_lines, b_begin, b_lines):
            self.a_begin = a_begin
            self.a_lines = a_lines
            self.b_begin = b_begin
            self.b_lines = b_lines

        @classmethod
        def fromstr(cls, s):
            """New Range from a range line string."""
            matches = cls.__re_range.match(s.rstrip("\n"))
            return cls(
                int(matches.group(1)), int(matches.group(2) or 1),
                int(matches.group(3)), int(matches.group(4) or 1))

        def __str__(self):
            """Generate range line from object fields."""
            s1 = "-%d" % (self.a_begin)
            if self.a_lines != 1:
                s1 += ",%d" % (self.a_lines)
            s2 = "+%d" % (self.b_begin)
            if self.b_lines != 1:
                s2 += ",%d" % (self.b_lines)
            return "@@ %s %s @@\n" % (s1, s2)

    def __init__(self, range_str):
        """New Hunk from range string."""
        self.range = self.Range.fromstr(range_str)
        self.lines_a = []
        self.lines_b = []

    def append_line(self, diffline):
        """Append a line of diff output to this Hunk.

        "-" lines are appended to lines_a and
        "+" lines to lines_b
        " " lines (context) are appended to both.
        """
        if diffline.startswith("-"):
            self.lines_a.append(diffline[1:])
        elif diffline.startswith("+"):
            self.lines_b.append(diffline[1:])
        else:
            self.lines_a.append(diffline[1:])
            self.lines_b.append(diffline[1:])


def is_junk(c):
    """Return True if the character should not be used as a synchronisation
    point in the string.
    """
    return c in " \t\r\n"


def overlaps(a, b):
    """Return True if the span a = (start, end) overlaps with b = (start, end),
    otherwise False.
    """
    return (a[0]   >= b[0] and a[0]   <= b[1]-1) \
        or (a[1]-1 >= b[0] and a[1]-1 <= b[1]-1) \
        or (b[0]   >= a[0] and b[0]   <= a[1]-1) \
        or (b[1]-1 >= a[0] and b[1]-1 <= a[1]-1)


def diff_overlaps_regex(line, re_prog, diff_spans):
    """Return the diff spans that overlap with a match of re_prog in line."""
    res, pos = [], 0

    while True:
        m = re_prog.search(line, pos)
        if m is None:
            break
        re_span = m.span(0)[0:2]

        for i, ds in ((i, ds) for i, ds in enumerate(diff_spans) if ds is not None):
            if overlaps(ds, re_span):
                res.append((i, ds))
                # only take the part of range that match regex
                # FIXME
                # res.append((i, (max(ds[0], re_span[0]), min(ds[1], re_span[1]))))
        pos = re_span[1]

    return res


def duplicate_values(m):
    """Return the keys of m if the value assigned to it occurs more than once
    in the dict.
    """
    if not m:
        return True
    c = Counter((x for x in m.values() if x is not None))
    if not c:
        return True
    return [v for v, c in c.items() if c > 1]


def map_same_lines(lines_a, lines_b):
    """Return mapping from lines in b to an index in a for lines which are
    identical in lines_a and lines_b.
    """
    map_b = OrderedDict.fromkeys(lines_b, None)

    # Map leading context lines
    for i in range(min(len(lines_a), len(lines_b))):
        if lines_a[i] == lines_b[i]:
            map_b[lines_b[i]] = i
        else:
            break

    # Map trailing context lines
    for i in range(min(len(lines_a), len(lines_b)) - 1, -1, -1):
        if lines_a[i] == lines_b[i]:
            map_b[lines_b[i]] = i
        else:
            break

    return map_b


def map_order_lines(lines_a, lines_b, cutoff_min=0.4):
    """Map lines_a and lines_b using similarity.

    Returns two lists of same length.
    """
    map_b = map_same_lines(lines_a, lines_b)
    fixed_indices = tuple(map_b.values())

    candidates_a = [l for i, l in enumerate(lines_a) if i not in fixed_indices]

    cutoff = cutoff_min
    while cutoff <= 1.0:
        for line in [ln for ln in lines_b if map_b[ln] is None]:
            try:
                best_match = difflib.get_close_matches(
                    line, candidates_a, n=1, cutoff=cutoff)[0]
                map_b[line] = lines_a.index(best_match)
            except IndexError:
                # is added line
                pass

        duplicate_indices = duplicate_values(map_b)
        if not duplicate_indices:
            # all lines could be mapped without conflicts
            break

        if cutoff < 1.0:
            # we can try again using a greater cutoff

            for k in [k for k, v in map_b.items() if v in duplicate_indices]:
                map_b[k] = None

            cutoff = min(1.0, cutoff * 1.1)
            continue
        else:
            # cannot uniquely map lines
            raise RuntimeError(
                "failed to map lines uniquely (cutoff: %f)" % (cutoff),
                "lines_a:\n" + "".join(
                    "%u:%s" % x for x in enumerate(lines_a)),
                "lines_a[i]->line_b:\n" + "".join(
                    "%s:%s" % (v, k) for (k, v) in map_b.items()))

    # Construct result lists.
    res_a, res_b = list(lines_a), ([None] * len(lines_a))

    for line, idx in map_b.items():
        if idx is not None:
            res_b[idx] = line

    for pos, line in enumerate(map_b.keys()):
        if map_b[line] is not None:
            continue
        i = min((i for i in map_b.values() if i is not None and i >= pos),
                default=len(res_a))
        res_a.insert(i, None)
        res_b.insert(i, line)

    assert len(res_a) == len(res_b)
    return res_a, res_b


def line_mod_regex(line_a, line_b, a_diff, b_diff, overlap_spans_a, overlap_spans_b):
    """Generate "new" line from old line with changes that overlap with
    overlap_spans applied.
    """
    res, off = line_a, 0

    overlap_dict_b = dict(overlap_spans_b)
    overlap_indices = sorted(set(
        t[0] for t in overlap_spans_a + overlap_spans_b))

    for idx in overlap_indices:
        overlap_span_b = overlap_dict_b.get(idx, (0, 0))
        a_span = a_diff[idx]
        assert a_span

        d = line_b[overlap_span_b[0]:overlap_span_b[1]]
        res = res[:(a_span[0] + off)] + d + res[(a_span[1] + off):]

        off += ((overlap_span_b[1]-overlap_span_b[0]) - (a_span[1]-a_span[0]))

    return res


def line_diff_spans(line_a, line_b):
    """Return spans for differences between line_a and line_b."""
    # Find areas of line that differ
    matcher = difflib.SequenceMatcher(is_junk, line_a, line_b, autojunk=False)
    blocks = matcher.get_matching_blocks()

    a_diff, a_pos = [], 0
    b_diff, b_pos = [], 0

    for b in blocks:
        if b.size == 0:
            break
        if b.a > 0 and b.b > 0:
            assert b.a >= a_pos
            da = (a_pos, b.a)
            assert b.b >= b_pos
            db = (b_pos, b.b)

            assert (da is not None) and (db is not None)
            a_diff.append(da)
            b_diff.append(db)

        a_pos = b.a + b.size
        b_pos = b.b + b.size

    return a_diff, b_diff


def strip_diff(lines_a, lines_b, re_prog):
    """Order lines in lines_a and lines_b (of a single hunk) and construct a
    diff that only takes changes overlapping with a regular expression.

    Yields diff lines.
    """
    for line_a, line_b in zip(*map_order_lines(lines_a, lines_b)):
        # Handle removes and adds
        if line_a is None:
            yield ("+" + line_b)
            continue
        if line_b is None:
            yield ("-" + line_a)
            # yield (" " + line_a)
            continue

        if line_a is not line_b:  # ref. equality
            a_diff, b_diff = line_diff_spans(line_a, line_b)

            # Test if any of the differing areas overlap with regex
            overlap_spans_a = diff_overlaps_regex(line_a, re_prog, a_diff)
            overlap_spans_b = diff_overlaps_regex(line_b, re_prog, b_diff)

            if overlap_spans_a or overlap_spans_b:
                # yes: keep change
                yield ("-" + line_a)
                yield ("+" + line_mod_regex(
                    line_a, line_b,
                    a_diff, b_diff,
                    overlap_spans_a, overlap_spans_b))
            else:
                # no: keep "original" line
                yield (" " + line_b)
        else:
            # context line
            yield (" " + line_a)


def assemble_hunks(udiff_lines):
    """Read lines from difflib generator and yields Hunk objects."""
    hunk = None
    for diffline in udiff_lines:
        if diffline.startswith("@@"):
            if hunk:  # not on first hunk
                yield hunk

            # new hunk
            hunk = Hunk(diffline)
        else:
            # Go through all the diff hunks and insert them into the hunk
            hunk.append_line(diffline)
    else:
        if hunk:
            yield hunk


def process_hunk(re_prog, hunk):
    """Process a hunk, i.e. process the diff lines and filter the interesting
    ones (i.e. overlap with a regular expression match).
    """
    try:
        return (hunk.range, list(strip_diff(
            hunk.lines_a, hunk.lines_b, re_prog)))
    except RuntimeError as e:
        print(*e.args, sep="\n", file=sys.stderr)
        raise RuntimeError(
            "failed to process hunk: %s" % hunk.range) from None


if __name__ == "__main__":
    re_diff = re.compile(sys.argv[3])

    with open(sys.argv[1]) as fa, open(sys.argv[2]) as fb:
        udiff_lines = difflib.unified_diff(
            list(fa), list(fb), fa.name, fb.name, n=3)

    import functools

    import multiprocessing as mp
    mp.set_start_method('fork')  # workaround

    # Unified diff header
    sys.stdout.write(next(udiff_lines))
    sys.stdout.write(next(udiff_lines))

    with mp.Pool() as pool:
        b_offset = 0
        hunk_gen = assemble_hunks(udiff_lines)

        for hunk_range, lines in pool.imap(
                functools.partial(process_hunk, re_diff), hunk_gen):
            # # Remove all trailing context lines
            # while stripped and stripped[-1][0] == " ":
            #     stripped.pop()

            # Update range line counts because lines have been "stripped"
            new_a_lines = sum(1 for ln in lines if ln.startswith((" ", "-")))
            new_b_lines = sum(1 for ln in lines if ln.startswith((" ", "+")))
            b_offset += (new_b_lines - new_a_lines)

            hunk_range.b_begin = (hunk_range.a_begin + b_offset)
            hunk_range.a_lines = new_a_lines
            hunk_range.b_lines = new_b_lines

            if any(ln.startswith(("-", "+")) for ln in lines):
                # lines have changed -> print new lines
                print(str(hunk_range), *lines, sep="", end="")
