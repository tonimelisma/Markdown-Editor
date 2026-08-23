# CLAUDE.md — Operating Manual

How to work in this repository. `AGENTS.md` is a symlink to this file.

Product direction is in `docs/VISION.md`, architecture in `docs/ENGINEERING.md`, behavior in
`docs/REQUIREMENTS.md`, sequence in `docs/ROADMAP.md`. Why the old verification apparatus was
removed is in `docs/DECISIONS.md` — read it before adding a gate.

## 1. Product

A native macOS Markdown editor: pure Swift, SwiftUI-first with narrow AppKit adapters,
local-first, no accounts, no lock-in, ordinary Markdown files.

## 2. The loop

```bash
Scripts/check.sh
```

Build, test, smoke. That is the gate. It takes a few minutes and it is the only thing that has
to pass.

Work in a branch for anything non-trivial, open a PR, squash-merge. Small doc fixes can go
straight to `main`. Get a review when the change is subtle or you are unsure — not as a ritual.

Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## 3. Honesty

These are the rules that were worth keeping. They cost nothing and they are the reason the test
suite is trustworthy.

- **Never mark work delivered that you have not observed pass.** Report the gate output, not the
  intention. If tests fail, say so and paste it. If you skipped something, say that.
- **A green existing suite is not proof of a new claim.** A new test must fail for the defect it
  is about. Before you trust a test, know the answer to: *what change to production code makes
  this go red?* If the answer is "none", it proves nothing — delete it or fix it.
- **Test behavior, not source text.** Assert on what the code does, not on what it contains.
  Grepping source is legitimate only to prove an *absence* (no networking, no UI-test target),
  and such a check should verify its own detector works.
- **A capability needs a proof that it works**, not only proofs that it refuses when it should.
  REQ-058 was satisfied for months by a build in which four formatting commands reported
  `enabled` and silently refused, because every cited proof asserted availability or refusal.
- **A filtered test run that matches nothing reports success.**
  `xcodebuild test -only-testing:"Target/SuiteName/functionName"` silently selects zero tests for
  a Swift Testing `@Test` function and then prints `** TEST SUCCEEDED **`. A falsification run
  that "passes" after a mutation is therefore ambiguous: either the test does not discriminate, or
  it never ran. Filter to the **suite**, and confirm individual `Test case … passed/failed` lines
  appear before believing either outcome.
- **Where a set is closed** (`EditorCommand.allCases`, `EditorTraceEvent`), prefer a test that
  iterates it, so a new member fails the build until its behavior is declared. A hand-written
  list of examples omits the case nobody thought of.
- **Every recorded measurement carries a bound.** `WorkLedger.mainThreadBlockedNanos` was
  computed, serialized and written to every run log for months, and compared against nothing. An
  unbounded measurement is not evidence — it is the *appearance* of evidence, which is worse than
  none, because it makes the area look examined. If a number is worth computing at runtime, it is
  worth a threshold; if no threshold can be named, do not compute it.
- **A proof is cheaper than the thing it proves.** `ProjectionOracle.validate` cost 3.5× the cmark
  parse it validated, on the main actor, on every formatting command — a property about a few
  thousand segment boundaries proved with a 100,000-element array. When a check is asymptotically
  more expensive than its subject, suspect the check of being badly posed before concluding that
  correctness is expensive. The repair was a *stronger* proof that cost 1% as much.
- **A measurement describes only the input it was measured on.** REQ-090 promised a p95 under
  8 ms and was satisfied by a corpus of one repeated word — 100,000 characters containing no
  heading, list, or table, which parses as a single paragraph. The number was real and described
  a document nobody has.
- **Rendered geometry is proved by forcing layout**, not by reading `NSParagraphStyle` fields.
  Constructing AppKit objects directly and asserting on `NSLayoutManager` line-fragment rects is
  a component test, not a UI test.

## 4. No UI tests

No XCUITest target, no screen automation, no accessibility-inspection assertions. Automated
verification is unit and component tests; constructing AppKit components directly is fine.

Two narrow exceptions, both passive:

- `Scripts/smoke-test.sh` launches the built app on a fixture and asserts only on the structured
  diagnostic records it writes. It never drives or reads the UI.
- `Scripts/smoke-screenshot.sh` captures one screenshot of the app's own window (never the full
  screen) over a rich fixture. Run it when you have changed anything visual, look at the result,
  and send it to the user. It is evidence for human eyes, never a requirement's proof.

## 5. Documentation

Code and tests are canonical. The specs describe current intent.

| Path | Job |
| --- | --- |
| `docs/VISION.md` | Product direction and priorities |
| `docs/ENGINEERING.md` | Current architecture, state ownership, runtime contracts, `ARC-###` invariants |
| `docs/REQUIREMENTS.md` | Numbered behavior requirements (`REQ-###`) |
| `docs/ROADMAP.md` | Delivery state and sequence |
| `docs/DECISIONS.md` | Decisions with consequences, including why the gates were removed |
| `docs/research/` | Costly evidence still valid; never architecture authority |
| `docs/plans/` | Approved, not-yet-implemented plans |

Rewrite or delete stale text in the change that makes it stale. No "superseded" banners, no
archive — Git is the archive. Delete a plan when its work merges, **as tidying, never as
evidence**: delivery evidence is observed gate output, quoted. In August 2026 ten increments were
marked delivered by deleting their plans, having built one comment line each, which is why
deletion is no longer a signal at all.

Keep a `// Verifies: REQ-###` comment on tests that prove a specific requirement. **That comment
is the traceability mapping** — it lives next to the proof and survives refactoring. REQUIREMENTS
names tests as a convenience for the reader and deliberately does not name production types; a
hand-maintained second copy of the code rots silently. Nothing enforces this mechanically.

## 6. Architecture changes

An implementation plan cannot redefine architecture. Changing an `ARC-###` invariant needs a
reproduced counterexample or a new constraint, real API evidence where behavior is not documented,
a decision recorded in `docs/DECISIONS.md` by the §7 method, an atomic update to ENGINEERING and
affected requirements, a test that discriminates the new contract, and deletion of the displaced
path in the same change.

No supersession documents, no indefinite migrations, no compatibility layers.

## 7. Consent

Research, then present findings and options, then get explicit approval, then write it into the
specs. Approval is specific; silence is not consent.

An explicit request to implement an approved plan, or to repair something broken that you found
while doing it, authorizes the ordinary work: code, tests, the gate, branches, PRs, merges,
cleanup. Do not stop to re-ask.

**Decide, do not ask.** When a decision arises — including one that changes the product, changes
the architecture, or widens the scope — work it out and make it. Do not hand it back as a
question. The method:

1. **State the criteria** the decision turns on, derived from `docs/VISION.md`'s objective
   ordering and evaluation section rather than invented for the occasion.
2. **List the real alternatives**, including the one you expect to reject and the one that is
   simply "do nothing".
3. **Rank them against the criteria**, explicitly, including where the ranking is close.
4. **Choose**, and record the choice in `docs/DECISIONS.md` with the reasoning — especially any
   respect in which the chosen option is worse than a rejected one.

A decision that turns out badly is recoverable; Git is the archive and DECISIONS says what was
believed at the time. Stopping to ask is not free — it stalls the work and pushes judgement onto
someone who asked for the work precisely so they would not have to make it.

A user correction is durable: update this file or the authoritative doc in the same change,
sweep the docs it contradicts, and do not keep the displaced rule anywhere.

## 8. Before you say you are done

- The gate ran and you are reporting its actual output.
- Docs that this change made wrong are fixed.
- Branches, worktrees, and stashes you created are gone.
- Anything you left undone is stated plainly.
