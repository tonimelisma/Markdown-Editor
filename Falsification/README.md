# Falsification manifests

This directory is the approved home for one `REQ-###.json` manifest per requirement that remains
`Done`. COR-61 Phase 1 validates manifest shape and mutation quality. The mutation executor and
reviewed requirement entries are deliberately not enabled until the later COR-61 phases; the plan
and ROADMAP remain active until those phases and the COR-62 audit are complete.

Each mutation names one exact production replacement and at least one proof that must turn red:

```json
{
  "requirement": "REQ-109",
  "mutations": [{
    "rationale": "A full replacement violates the bounded patch contract.",
    "file": "Markdown Editor/PresentationPatch.swift",
    "find": "return .bounded(...) ",
    "replace": "return .fullReplacement(reason: .recovery)",
    "expect_red": ["newerSnapshotWithChangedTextUsesOneBoundedPatch"]
  }]
}
```
