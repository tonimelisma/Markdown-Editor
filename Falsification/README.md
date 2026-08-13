# Falsification manifests

This directory is the approved home for one `REQ-###.json` manifest per delivered requirement and
per active `Correction` requirement whose proof is being repaired. A manifest on a `Correction` row
is pending evidence only; it never implies delivery. `Done` rows still require a manifest. COR-61
Phase 1 validates manifest shape and mutation quality, and the executor runs both delivered and
pending correction manifests selected by the requested scope.

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
