#!/usr/bin/env python3
"""Import CommonMark and GFM spec examples as a traceable conformance corpus.

REQ-132: "imported conformance verification … reproducible seeds/provenance". This script *is*
the refresh command recorded in the manifest: the corpus is never hand-edited, and re-running this
reproduces it byte for byte or reports that upstream changed.

What the corpus is for, and what it is not
------------------------------------------
These examples are used as a large, real, traceable *input set* for the structural properties in
`PropertyTests` — parse without crashing, source-index round trips, projection-oracle acceptance,
token containment and grapheme alignment, and incremental/full lexer agreement.

They are **not** used as an HTML conformance oracle. This app is an editor, not a renderer; it does
not emit the spec's HTML and does not claim spec-conformant output. Storing the expected HTML and
never asserting on it would be exactly the kind of decorative evidence `docs/DECISIONS.md` warns
about, so the HTML half of each example is deliberately discarded here.

Usage:
    Scripts/import-spec-corpus.py --commonmark <spec.txt> --gfm <spec.txt> --out <dir>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys

# `spec.txt` delimits examples with a run of backticks followed by `example`, then markdown, a lone
# `.`, the expected HTML, and a closing run. GFM appends extension names (` example table`).
EXAMPLE = re.compile(
    r"^(`{32,})\s*example([^\n]*)\n(.*?)^\.\n(.*?)^\1\s*$",
    re.MULTILINE | re.DOTALL,
)


def parse_front_matter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n...\n")
    if end == -1:
        return {}
    fields: dict[str, str] = {}
    for line in text[4:end].splitlines():
        if ":" in line:
            key, _, value = line.partition(":")
            fields[key.strip()] = value.strip().strip("'\"")
    return fields


def extract(text: str, source: str) -> list[dict[str, object]]:
    examples = []
    for index, match in enumerate(EXAMPLE.finditer(text), start=1):
        extensions = match.group(2).strip()
        markdown = match.group(3).replace("→", "\t")
        examples.append(
            {
                "id": f"{source}-{index:04d}",
                "source": source,
                # Section heading this example sits under, for a readable failure.
                "extensions": extensions,
                "markdown": markdown,
            }
        )
    return examples


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--commonmark", required=True, type=pathlib.Path)
    parser.add_argument("--gfm", required=True, type=pathlib.Path)
    parser.add_argument("--out", required=True, type=pathlib.Path)
    args = parser.parse_args()

    args.out.mkdir(parents=True, exist_ok=True)
    sources = []
    examples: list[dict[str, object]] = []

    for label, path, url in (
        (
            "commonmark",
            args.commonmark,
            "https://raw.githubusercontent.com/commonmark/commonmark-spec/0.31.2/spec.txt",
        ),
        (
            "gfm",
            args.gfm,
            "https://raw.githubusercontent.com/github/cmark-gfm/master/test/spec.txt",
        ),
    ):
        raw = path.read_bytes()
        text = raw.decode("utf-8")
        front = parse_front_matter(text)
        found = extract(text, label)
        if not found:
            print(f"import-spec-corpus: no examples found in {path}", file=sys.stderr)
            return 1
        examples.extend(found)
        sources.append(
            {
                "name": front.get("title", label),
                "version": front.get("version", "unknown"),
                "date": front.get("date", "unknown"),
                "license": front.get("license", "unknown"),
                "url": url,
                "sha256": hashlib.sha256(raw).hexdigest(),
                "exampleCount": len(found),
            }
        )

    manifest = {
        "schemaVersion": 1,
        "purpose": (
            "Structural-property input corpus. NOT an HTML conformance oracle: the expected HTML "
            "in each upstream example is deliberately not imported, because this app is an editor "
            "and does not claim spec-conformant HTML output."
        ),
        "refreshCommand": (
            "curl -sSL -o /tmp/commonmark.txt <commonmark url> && "
            "curl -sSL -o /tmp/gfm.txt <gfm url> && "
            "Scripts/import-spec-corpus.py --commonmark /tmp/commonmark.txt --gfm /tmp/gfm.txt "
            "--out 'Markdown EditorTests/Fixtures/Specifications'"
        ),
        "sources": sources,
        "examples": examples,
    }

    target = args.out / "spec-corpus.json"
    target.write_text(json.dumps(manifest, ensure_ascii=False, indent=1, sort_keys=False) + "\n")
    total = len(examples)
    print(f"import-spec-corpus: wrote {total} examples from {len(sources)} sources to {target}")
    for source in sources:
        print(f"  {source['name']} {source['version']} — {source['exampleCount']} examples, sha256 {source['sha256'][:16]}…")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
