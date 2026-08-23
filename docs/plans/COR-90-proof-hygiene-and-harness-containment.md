# COR-90 — Proof hygiene and harness containment

> **Status: proposed, not approved.**

- **Executor:** any implementer, unattended.
- **Blockers:** none. Independent of everything else in the queue.
- **Requirements moved to `Done`:** none existing; adds one (Release binary surface).
- **Architecture impact:** none.

## Defect 1 — four tests assert on production source text

`CLAUDE.md` §3: *"Grepping source is legitimate only to prove an **absence**, and such a check
should verify its own detector works."*

`DisplayPreferencePolicyTests` does this exactly right — absence proof, self-verifying detector,
comment citing the rule. It is the template. These four are not:

| Location | What it does | Why it proves nothing |
| --- | --- | --- |
| `NativeSourceContractTests.swift:197-201` | `#expect(contentView.contains(".task(id: document.sourceVersion)"))` and two more literal-expression matches | Asserts on **source formatting**. Renaming `countOwner` or wrapping the call across two lines reddens it while changing no behavior. Brittle *and* non-proving. The same test asserts the real behavior six lines above. |
| `PerformanceCorpusTests.swift:98-105` | `#expect(source.contains("--benchmark-manifest"))`, `#expect(source.contains("os.replace"))` against `Scripts/benchmark.sh` | Presence assertions on a shell script's text. A script's behavior is provable by running it; its text is not. |
| `PerformanceCorpusTests.swift:89-94` | `#expect(!source.contains("accessibility"))` against `BenchmarkDriver.swift` | Legitimate absence *shape*, but no detector self-check, so a typo in the needle passes silently. |
| `PrivacyBoundaryTests.swift:51-57` | Mixed presence/absence over `DiagnosticValue.swift` text | The absence half is a real privacy proof, but it string-matches a **closed enum the repo could iterate directly**, and has no detector check. |

Residue from the retired apparatus.

**Fix.** Delete the `NativeSourceContractTests` greps outright — the behavior assertion above them
is the proof. Rewrite `PrivacyBoundaryTests` as closed-set iteration over `DiagnosticValue`'s
cases, asserting each payload type is in the local-safe set, so mutating the enum reddens it for
the right reason. Replace the `benchmark.sh` greps with an executable check — invoke the script in
a dry-run mode and assert on its structured output — or delete them. Give the surviving
`BenchmarkDriver` absence check a detector self-test.

## Defect 2 — ~900 lines of harness ship inside the product binary

`BenchmarkDriver.swift` (703 lines) and `PerformanceCorpus.swift` are app-target members. The
shipping binary honors `--benchmark`, `--benchmark-manifest <path>` (which reads and JSON-decodes
an arbitrary file), `--diagnostic-smoke-exit`, and four `MARKDOWN_EDITOR_*` environment
variables — including `MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS`, which makes the app **synthesize
edits into the open document**.

Every branch is flag-guarded and this is not a vulnerability: a user-launched, non-sandboxed app
already trusts its own argv. It is **unowned product surface** — no requirement constrains it, and
one path mutates user documents.

**Fix.** The smoke and screenshot verifiers must keep working — `Scripts/check.sh` depends on them
and `DECISIONS.md` deliberately kept them. So: move `BenchmarkDriver` and `PerformanceCorpus`
behind a compile condition active in Debug and a dedicated benchmark configuration, leaving the
small smoke entry points in the shipping binary with a requirement that says so.

**New requirement:** *The Release binary shall expose no argument or environment path that mutates
document content.* Proved by iterating the closed set of recognized flags.

## Defect 3 — orphaned linter, undocumented OS floor, stale ignores

- `.markdownlint-cli2.jsonc` targets `CLAUDE.md` and `docs/**/*.md` and **nothing runs it**. Run
  today it reports **21 violations across four existing documents**. Either wire it into
  `check.sh` (pure Node, seconds) or delete it. An orphaned linter config is a claim the repo does
  not honor — and the violation count proves the claim has been false for some time.
- `MACOSX_DEPLOYMENT_TARGET = 27.0` — the just-released OS, and only it. A large audience decision
  with **no entry in DECISIONS**, whose stated purpose is *"the short list of things someone will
  otherwise re-litigate or accidentally undo."* Record it with its reason.
- `.gitignore` carries entries for three deleted systems (`.perf-suite-build/`, `.perf-suite.log`,
  `.gate-receipt.json`). Untracked leftovers `default.profraw` (344 KB) and `.gate-receipt.json`
  sit in the working tree.

## Files, types, and routes

**Modify:** `NativeSourceContractTests.swift`, `PrivacyBoundaryTests.swift`,
`PerformanceCorpusTests.swift`, `project.pbxproj` (compile condition), `Scripts/check.sh` (only if
markdownlint is wired), `.gitignore`, `docs/DECISIONS.md`, `docs/REQUIREMENTS.md`.

**Delete:** the four source-text assertions; `.gate-receipt.json` and `default.profraw` from the
working tree; three stale `.gitignore` entries; `.markdownlint-cli2.jsonc` if not wired.

## Ordered phases

1. Rewrite the four tests. Each replacement must be **observed red** against a deliberate
   mutation before it is trusted — that is the question `CLAUDE.md` §3 asks, and these are exactly
   the tests that failed to ask it.
2. Compile-condition the harness; add the Release-surface requirement and its closed-set proof.
3. Decide markdownlint: wire or delete. If wired, fix the 21 violations in the same change.
4. DECISIONS entry for the OS floor; `.gitignore` and working-tree cleanup.
5. `Scripts/check.sh`. Report actual output.

## Automated non-UI proof

- `diagnosticValueCasesAreLocalSafe` — closed-set iteration replacing the text grep.
- `releaseBinaryExposesNoDocumentMutatingFlag` — closed-set over recognized flags.
- `benchmarkDriverAbsenceDetectorWorks` — the detector self-test the current check lacks.
- Whatever replaces the `benchmark.sh` greps must **execute** the script.

## Failure and rollback behavior

No runtime behavior changes outside the Release harness surface, which becomes smaller. Rollback
is reverting the commit.

## Deletion and conformance gate

No test in the suite asserts the *presence* of a string in a production source file. Proved by an
absence check over the test target with a self-verifying detector — which is itself the pattern
the increment is enforcing, and must therefore be written to that standard or not at all.
