# COR-62 proof-floor audit record

- **Authority:** Evidence only
- **First researched:** 2026-08-11
- **Last verified:** 2026-08-11
- **Refresh when:** any requirement, proof, architecture invariant, test suite, gate schema, SDK, or implementation route changes.
- Environment: macOS 27.0 (26A5406e), arm64, Xcode 27.0 (27A5228h), Debug XCTest run `/private/tmp/md-editor-dd-final/Full2.xcresult`.
- Method: snapshot every `Done` row before this audit; validate and execute `Scripts/check-falsification.sh --all`; inspect the cited proof shape against the requirement's subject, quantified input class, and liveness obligation; demote rows without a falsifying manifest.

## Result

The pre-audit snapshot contained 104 Done rows. No row was deleted. The audit retained 18 original
manifest-backed rows as Done and demoted 86 rows to Correction because no falsifying manifest was
present. COR-44/COR-45 were then reimplemented and added six manifest-backed Done rows; COR-60 was
promoted after its provenance fixtures passed. The closing mutation run passed for all 24 retained
rows.

## Per-requirement answers

Format: Q1 manifest that can turn a cited proof red; Q2 proof asserts the promised behavior; Q3 quantified input class is structurally covered or not applicable; Q4 capability has a success proof or is not applicable.

- REQ-001 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-002 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-003 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-004 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-005 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-006 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-007 — Q1 yes; Q2 yes; Q3 yes; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-010 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-011 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-012 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-020 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-021 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-022 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-030 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-031 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-032 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-040 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-041 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-043 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-044 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-045 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-046 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-047 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-048 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-049 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-050 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-051 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-060 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-061 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-062 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-063 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-064 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-065 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-066 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-067 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-068 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-069 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-070 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-071 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-072 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-073 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-074 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-075 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-076 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-077 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-013 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-014 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-015 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-016 — Q1 yes; Q2 yes; Q3 n/a; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-017 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-018 — Q1 yes; Q2 yes; Q3 n/a; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-019 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-052 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-053 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-054 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-055 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-056 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-057 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-058 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-059 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-113 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-078 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-079 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-080 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-081 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-082 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-083 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-084 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-085 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-086 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-087 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-088 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-089 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-091 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-092 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-093 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-094 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-095 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-096 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-097 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-098 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-099 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-100 — Q1 yes; Q2 yes; Q3 n/a; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-101 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-102 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-103 — Q1 yes; Q2 yes; Q3 yes; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-104 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-114 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-115 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-116 — Q1 yes; Q2 yes; Q3 yes; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-117 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-118 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-105 — Q1 yes; Q2 yes; Q3 n/a; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-106 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-107 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-108 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-109 — Q1 yes; Q2 yes; Q3 yes; Q4 yes; disposition: remains Done pending the observed mutation result.
- REQ-110 — Q1 yes; Q2 yes; Q3 n/a; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-111 — Q1 yes; Q2 yes; Q3 yes; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-112 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-133 — Q1 yes; Q2 yes; Q3 yes; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-134 — Q1 yes; Q2 yes; Q3 yes; Q4 n/a; disposition: remains Done pending the observed mutation result.
- REQ-135 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.
- REQ-136 — Q1 no manifest; Q2 not assessed; Q3 not assessed; Q4 not assessed; disposition: Correction, with `COR-62 audit` as the re-verification owner.

## Findings and limits

- The 86 demotions are an evidence-floor result, not a claim that the implementation is absent. Their existing tests and production code remain preserved, but the repository had no recorded mutation capable of demonstrating that the cited proof would fail.
- The audit does not repair demoted behavior, invent manifests, or delete plans. Follow-up implementation increments must restore each row only after a real falsifying mutation turns the cited proof red and the full proof run observes the proof passing.
- The retained manifest rows completed the mutation command and full proof gates; the remaining
  Correction rows are intentionally not promoted by this audit.
