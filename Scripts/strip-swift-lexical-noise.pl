#!/usr/bin/perl
# Strips line comments, block comments (including Swift's nested block comments, which a
# non-greedy regex cannot correctly handle — a naive `s{/\*.*?\*/}{}gs` stops at the first `*/`
# and leaves the rest of a nested comment, including any fake call site inside it, visible to
# a later text search), and string-literal contents from Swift source. Read from stdin, written
# to stdout. Used by check-instrumentation-coverage.sh so a call site that exists only in a
# comment or string literal (dead reference, never executed) cannot be counted as coverage.
use strict;
use warnings;

my $text = do { local $/; <STDIN> };
my $out = '';
my $i = 0;
my $len = length($text);
my $depth = 0;          # block-comment nesting depth; > 0 means "inside a block comment"
my $in_line_comment = 0;
my $in_string = 0;

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
        if ($c eq '\\' && $i + 1 < $len) { $i += 2; next; }
        if ($c eq '"') { $in_string = 0; $out .= '"'; $i++; next; }
        $i++;
        next;
    }

    my $two = substr($text, $i, 2);
    if ($two eq '//') { $in_line_comment = 1; $i += 2; next; }
    if ($two eq '/*') { $depth = 1; $i += 2; next; }
    if ($c eq '"') { $in_string = 1; $out .= '"'; $i++; next; }
    $out .= $c;
    $i++;
}

print $out;
