# REQUIREMENTS

The single source of truth for **WHAT** the app does. Requirements are **populated per
increment** during the discovery phase (the *Specify* step of [CLAUDE.md §3](../CLAUDE.md)) —
never pre-fabricated. This file is currently a **skeleton**: it defines the format and holds
no requirements yet.

## Conventions

- **ID:** `REQ-###`, assigned sequentially, never reused.
- **EARS notation** — UPPER-CASE keywords: `WHEN` (event), `WHILE` (state), `IF…THEN`
  (unwanted), `WHERE` (optional); otherwise a ubiquitous "The system shall …". One "shall"
  per requirement.
- **Status:** `Planned` · `Active` · `Done` · `Deferred`.
- **Traceability:** code carries `// REQ-###`, tests carry `// Verifies: REQ-###`
  ([CLAUDE.md §4](../CLAUDE.md)). Each row lists its code + test anchors. `—` = not yet built.
- **Forward:** every requirement has ≥1 test. **Backward:** every `REQ-###` in code exists
  here. A `Done` row must have real anchors.

## Requirements

*No requirements yet.* They land here as increments enter their build phase. Row format:

| ID | Requirement (EARS) | Inc | Status | Implemented in | Verified by |
|----|--------------------|-----|--------|----------------|-------------|
| *REQ-001* | *(example — the system shall …)* | *INC-01* | *Planned* | *—* | *—* |

*Next free ID: REQ-001.*
