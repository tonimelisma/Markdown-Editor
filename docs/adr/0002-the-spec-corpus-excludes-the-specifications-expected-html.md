# 0002. The spec corpus excludes the specifications' expected HTML

- Status: accepted
- Date: 2026-08-22

## Context and problem

Kept here because roadmap.md's delivery ledger, where they used to live, is gone.

**The spec corpus deliberately excludes the specifications' expected HTML** (COR-80). 1,324
examples are imported verbatim from CommonMark 0.31.2 and GFM 0.29 with version, licence,
SHA-256, and a committed refresh command, and they drive structural properties only. This app is
an editor, not a renderer; an imported expectation nothing asserts against is decorative
evidence.

## Decision drivers

- An imported expectation nothing asserts against is decorative evidence.
- The app is an editor, not a renderer.

## Considered options

### Import the examples with their expected HTML

- Bad: nothing would assert against the HTML.

### Import the examples for structural properties only (chosen)

- Good: 1,324 examples drive structural properties, with version, licence and SHA-256.

## Decision

As stated in the context above.

## Consequences

As stated above.

## Confirmation

`SpecCorpusTests` drive the imported corpus (`Markdown EditorTests/Fixtures/Specifications/spec-corpus.json`, refreshed by `Scripts/import-spec-corpus.py`).

## Retirement proof

A renderer feature (HTML export, say) whose output the expected HTML would actually check.

## Reversal plan

Re-import with the HTML kept; cheap, but only worth it with a test that reads it.
