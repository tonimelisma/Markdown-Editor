#!/usr/bin/perl
# Strips line comments, block comments (including Swift's nested block comments, which a
# non-greedy regex cannot correctly handle — a naive `s{/\*.*?\*/}{}gs` stops at the first `*/`
# and leaves the rest of a nested comment, including any fake call site inside it, visible to
# a later text search), and string-literal contents from Swift source — including raw strings
# (`#"..."#`, `##"..."##`, ...) and triple-quoted multiline strings (plain or raw). Read from
# stdin, written to stdout. Used by check-instrumentation-coverage.sh so a call site that exists
# only in a comment or string literal (dead reference, never executed) cannot be counted as
# coverage.
#
# A raw string's embedded quotes are not string terminators — only a `"` (or `"""`) followed by
# the exact same hash count that opened it closes the string (this codebase already has several
# regex patterns written this way, e.g. MarkdownHighlighter.swift). A scanner that only knows
# about plain `"..."` strings terminates a raw string at its first embedded `"`, exposing
# whatever code follows — including a fake `trace?.record(...)` call site — to the search below.
use strict;
use warnings;

my $text = do { local $/; <STDIN> };
my $out = '';
my $i = 0;
my $len = length($text);
my $depth = 0;          # block-comment nesting depth; > 0 means "inside a block comment"
my $in_line_comment = 0;

# String state, entered only from outside any comment/string.
my $in_string = 0;
my $string_hashes = 0;      # number of '#' delimiters; 0 for a plain (non-raw) string
my $string_multiline = 0;   # 1 if the opener was a triple-quote

while ($i < $len) {
    my $c = substr($text, $i, 1);

    if ($in_line_comment) {
        if ($c eq "\n") {
            $in_line_comment = 0;
            $out .= $c;
        }
        $i++;
        next;
    }

    if ($depth > 0) {
        my $two = substr($text, $i, 2);
        if ($two eq '/*') { $depth++; $i += 2; next; }
        if ($two eq '*/') { $depth--; $i += 2; next; }
        $out .= "\n" if $c eq "\n";
        $i++;
        next;
    }

    if ($in_string) {
        # Only a plain (non-raw) string honors backslash escapes — a raw string's backslash is
        # a literal character unless followed by exactly $string_hashes '#', which introduces
        # interpolation rather than escaping the terminator; either way it cannot produce a
        # false terminator match below, so raw strings need no escape handling at all here.
        if ($string_hashes == 0 && $c eq '\\' && $i + 1 < $len) {
            $i += 2;
            next;
        }
        my $terminator = ($string_multiline ? '"""' : '"') . ('#' x $string_hashes);
        if (substr($text, $i, length($terminator)) eq $terminator) {
            $out .= '"';
            $i += length($terminator);
            $in_string = 0;
            $string_hashes = 0;
            $string_multiline = 0;
            next;
        }
        $out .= "\n" if $c eq "\n";
        $i++;
        next;
    }

    my $two = substr($text, $i, 2);
    if ($two eq '//') { $in_line_comment = 1; $i += 2; next; }
    if ($two eq '/*') { $depth = 1; $i += 2; next; }

    if ($c eq '"' || $c eq '#') {
        # Count leading '#' (a raw-string opener candidate); only '#'* immediately followed by
        # '"' actually opens a string — a bare '#if'/'#available'/'#selector' etc. does not, and
        # falls through to be copied literally, one character at a time, below.
        my $j = $i;
        my $hashes = 0;
        while (substr($text, $j, 1) eq '#') { $hashes++; $j++; }
        if (substr($text, $j, 1) eq '"') {
            my $multiline = substr($text, $j, 3) eq '"""';
            $in_string = 1;
            $string_hashes = $hashes;
            $string_multiline = $multiline ? 1 : 0;
            $out .= '"';
            $i = $j + ($multiline ? 3 : 1);
            next;
        }
    }

    $out .= $c;
    $i++;
}

print $out;
