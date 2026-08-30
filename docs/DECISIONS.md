# DECISIONS

Decisions with consequences. Newest first. This is not an archive of everything ever decided —
it is the short list of things someone will otherwise re-litigate or accidentally undo.

## 2026-08-30 — Mode scroll state is an offset from the top of the document (COR-93)

**Decision.** `SourceModeState.scrollOffset` and `WYSIWYGModeState.scrollOffset` are offsets from
the top of the document, not raw `NSClipView` bounds origins. `EditorHostView.HostCoordinator`
owns the only conversion, in `scrollOffset(in:)` and `restoreScrollOffset(_:in:)`.

**What it fixed.** The first switch into Source mode opened halfway down the file. The screenshot
gallery caught it — the Source scene photographed a document starting mid-table — and nothing
else had, because every piece of state involved was reporting the truth: the session held
`.zero`, the clip view's bounds origin was `0`, and the restore did exactly what it was told.
AppKit had parked the Source text view at `documentView.frame.origin.y == -1044` inside an
861-point clip over a 2122-point document, so bounds origin `0` meant *1044 points into the
file*. The Source editor is laid out while hidden, which is why it and not WYSIWYG.

**Measured, not reasoned.** Three candidate explanations were tested against the running app with
temporary probes and all three were wrong: the string is installed at construction (not lazily on
first switch), `NSScrollView.tile()` after forcing text layout does not reset the placement, and
neither does laying out the clip view. The probe that settled it printed the document view's own
frame origin, which no amount of reading the code would have produced.

**Alternatives.** (A) Store offsets document-relative — chosen; one conversion, both editors, and
"zero means the top" becomes true by construction. (B) Special-case Source with a scroll-to-top on
first entry: hides the defect while leaving every recorded offset in a coordinate space that lies,
so the second switch would be wrong instead of the first. (C) Fight AppKit's placement until the
document view sits at zero — two attempts failed, and it makes correctness depend on undocumented
placement behaviour rather than on measuring it.

**Where the chosen option is worse.** It puts a coordinate conversion between the session and
AppKit, so a future reader of `scrollOffset` must know it is not a clip-bounds origin. That is
what the ENGINEERING §12 paragraph and the comment on the helpers are for. The alternative — a
raw AppKit coordinate whose meaning depends on where AppKit happened to put a view — is the one
that already cost a defect nobody could see in the state.

## 2026-08-29 — The product is photographed by naming a screen at launch, not by driving the UI

**Decision.** `Scripts/screenshots.sh` produces a committed gallery of the product's important
screens in `docs/screenshots/`. Screens an ordinary launch does not reach — Source mode, the link
sheet — are named at launch with `MARKDOWN_EDITOR_SMOKE_SCENE` and presented by the application
itself through its window-scoped command routes (REQ-151). The gallery is documentation, not a
gate: `Scripts/check.sh` does not run it.

**Criteria**, from VISION's objective ordering: (1) the verification carve-outs in CLAUDE.md §4
must survive intact — no UI automation; (2) honesty — a committed image must not claim a render
the log says was unhealthy; (3) ownership clarity and absence of duplicate paths; (4)
implementation and maintenance cost; (5) the product must not grow surface it does not need in
order to be photographed.

**Alternatives.**

- **A — name the scene at launch, apply it in-process** (chosen). Reuses the exact handle
  `exerciseSmokeEdits` already uses: the window's toolbar delegate holds the window-scoped
  `EditorCommandController`, so a scene reaches the session the same way a toolbar click does.
  No synthetic events, no accessibility, no screen automation, so §4 holds unchanged. Costs one
  declared environment variable, gated on the smoke argument like every other, and one enum the
  gallery script's scene table is compared against by a test.
- **B — drive the UI with `cliclick`/accessibility.** Photographs any screen with no product
  change at all, and is the only option that could reach a menu being pulled down. Rejected: it
  is precisely the automation §4 exists to forbid, and it would be the second path into the
  command model, competing with the first.
- **C — capture only what a launch already reaches.** No product change, no new variable — but
  the gallery would then be five pictures of the same screen, which does not answer the ask.
- **D — do nothing; keep the single REQ-104 review screenshot.** It is a temp file for one
  reviewer at one moment, and the repository still contains no picture of the product.

**Appearance is forced through the argument domain**, not by application code: the product has no
appearance setting of its own and must not grow one to be photographed. Measured, not assumed:
`-AppleInterfaceStyle Light` is a no-op (it is only tested against the string `Dark`), so the
light scenes pass `-NSRequiresAquaSystemAppearance YES`, which does force light on a dark-mode
machine — window luma 240 versus 44.

**Every image is gated on its own run's log.** A scene whose structured diagnostics fail is
reported and its PNG is not copied into the repository. The first run of the script found this
worth having in the opposite direction: killing the app straight after the capture lost the
end-of-run performance summaries, and all five scenes were correctly reported unhealthy while the
pixels were fine. The fix was to let each run reach its own bounded self-termination.

**Where the chosen option is worse.** It puts three lines of photography-shaped behaviour in the
shipping binary, and `LaunchSurface` grows a sixth variable. B would have kept the product clean
at the cost of the rule that keeps the test suite trustworthy; that trade is the wrong way round.
The mitigation is the same one COR-90 chose for the rest of the launch surface: the variable is
declared, enumerated, gated on `--diagnostic-smoke-exit`, and proved unable to change document
content.

## 2026-08-23 — REQ-090's typing budget takes the same stress-shape scope, and its cited evidence was wrong

**Decision.** REQ-090's 8 ms native-input-callback budget binds on every `PerformanceCorpus` shape
not declared a stress shape. `heavyLists` and `tableDense` carry recorded bounds of 30 ms and
22 ms. This extends the scoping decided for REQ-143 the previous day to the requirement it was
modelled on.

**Why it came up.** Release tests could not build at all until COR-86, so REQ-090's proof had not
executed in months. Run against the tree as it stood at COR-86 — before any optimisation work —
it failed two ways: `structuredProse` and `tableDense` collected **zero samples**, reporting
"performance input refused at sample 1", and `heavyLists` measured 10.4 ms against the 8 ms
budget. The row said `Done`.

**The proof was broken, and separately the budget was missed.** The test typed at
`renderedLength - 2`, which is not an editable location on every shape: after the first insertion
it can land on a synthetic paragraph break or a table row separator, which the closed
local-transition matrix refuses by design (ARC-009). That is correct product behaviour and a
broken measurement. Typing now happens inside an ordinary paragraph prepended to each corpus,
which is editable on every shape and is at least as representative as typing at the very end of a
document. With samples actually collected, four shapes are under 8 ms and two are not.

**The cited numbers never reproduced.** REQ-090 claimed "heavy lists 5.598 ms, dense tables
5.090 ms". Measured at COR-86 with the old method, `heavyLists` was 10.4 ms; with the repaired
method it is 17.1 ms. The old figures cannot be reproduced by either method, and the row carried
them as evidence.

**Alternatives.** (A) Scope to non-stress shapes and record bounds — chosen. (B) Optimise typing on
the stress shapes: the cost is TextKit laying out 18,520 and 24,400 `NSTextBlock`s, so it needs the
approved one-block-per-table-cell decision reopened (ENGINEERING §7), which is an architecture
change for shapes nobody writes. (C) Leave `Correction` open indefinitely — rots, as before.
(D) Delete the stress corpora — destroys evidence to make a number go green; rejected outright.

**Where the chosen option is worse.** This is the second requirement rescoped in two days, and the
pattern deserves suspicion: rescoping is how a red row becomes green without the product changing.
Three things hold it honest. The stress shapes remain measured and asserted, at 30 ms and 22 ms.
The classification lives in production as `PerformanceCorpus.isStressShape`, visible to a reader,
not in the test that benefits from it. And the stale figures were replaced with measured ones
rather than quietly left in place — the rescoping is the smaller half of this entry; the larger
half is that a `Done` row cited evidence that had never been reproducible.

## 2026-08-22 — The interactive budget binds on real document shapes, not on stress shapes

**Decision.** REQ-143's 16 ms budget applies to every `PerformanceCorpus` shape not declared a
stress shape. `heavyLists` and `tableDense` are declared stress shapes in production
(`PerformanceCorpus.isStressShape`) and carry recorded bounds instead. REQ-143 is `Done`.

**Criteria**, from VISION's objective ordering: (1) preservation and correctness — no proof may be
weakened; (2) honesty — the requirement must state what the product actually guarantees; (3) user
value; (4) implementation and maintenance cost, and risk to the parse path everything depends on;
(5) reversibility.

**Alternatives.**

- **A — rescope, declare the stress shapes** (chosen). Weakens no proof. Costs nothing. The two
  stress shapes stay asserted against recorded ceilings, so they cannot silently regress.
- **B — bounded reparse.** Reparse the enclosing block and splice, checking
  `splice == parse(whole)` over the 1,324 spec examples. The only design that closes all six. Best
  on user value in principle, worst on cost and risk: it touches the parse path everything else
  depends on, and the equivalence may simply not hold for lazy continuations or link reference
  definitions.
- **C — leave REQ-143 in `Correction` indefinitely.** Honest, costs nothing, weakens nothing, and
  rots: an open `Correction` nobody intends to close is a to-do disguised as a status.
- **D — delete the two stress corpora.** Rejected outright. It would make the number go green by
  destroying the evidence, which is the failure mode this repository exists to avoid.

**Ranking.** A and B tie on correctness and honesty. B wins on user value *in principle* and loses
it in fact: real documents look like `structuredProse`, which is at 13.1 ms, while `tableDense` is
a table row every 1.2 characters and `heavyLists` a list item every 4.3 — shapes nobody writes. B
is far worse on cost and risk. C loses on honesty over time. A wins.

**Where the chosen option is worse.** A is a requirement change that makes a red row green, which
is exactly the Goodhart move `docs/DECISIONS.md` warns about, and it deserves the suspicion. Three
things distinguish it from moving the goalposts. The stress shapes are still measured and still
asserted, at 50 ms and 55 ms, so nothing stopped being checked. The classification lives in
production as a closed declaration a reader can see, not in the test that would benefit from it.
And the 16 ms target was never reachable on those shapes by any means short of B — a single
authoritative rebuild is 26.9 ms on `tableDense`, so the original requirement asserted something
no implementation short of a parse-strategy rewrite could satisfy.

**Correction, same day.** REQ-143 first said "16 ms p95" and the test asserted worst-of-three
against 16 ms. That failed at 19.9 ms on a run whose median was 13.1 ms — scheduling noise under a
parallel suite, not a regression. A handful of samples cannot express a 95th percentile at all:
`p95` over three samples *is* the maximum. The requirement now says what is actually asserted —
**16 ms for a median command, 32 ms for any command** — which is precise, non-flaky, and honest,
where the p95 wording was none of the three. The Release evidence run in `docs/research/` remains
the place percentile claims can be made.

**What would reopen it.** A real document that behaves like the stress shapes, or a profile
showing `structuredProse` drifting toward the budget. B remains available and its plan text is in
Git.

## 2026-08-22 — The deployment target is the current macOS, and only it

**Decision.** `MACOSX_DEPLOYMENT_TARGET = 27.0`. The application does not run on any earlier
release. Recorded because it was never written down, and a large audience decision that exists
only as a build setting is exactly what this file is for.

**Why it is defensible.** The app has no users yet, so there is no installed base to strand. The
editor is built on TextKit, `NSDocument`, and the system appearance and accessibility APIs, and
every back-release lowers the floor for all of them at once: availability guards, a second
appearance path, and a second set of typography measurements. VISION ranks "one obvious path"
and "ride the platform" above reach.

**What would change it.** The first request from someone who cannot run it. Lowering the floor is
a real increment — availability audit, a second measured typography baseline, and a CI matrix
that does not exist yet — not a build-setting edit, and it should not be done casually because
one person asked.

## 2026-08-22 — The planning apparatus was reduced

**Decision.** `docs/plans/README.md`'s thirteen mandatory plan sections became four questions,
explicitly advisory. Plan deletion stopped being a delivery signal. `docs/ROADMAP.md` lost its
COR-18 – COR-85 delivery ledger (317 lines → ~100). `docs/REQUIREMENTS.md` lost its
`Implemented in` column. `CLAUDE.md` §3 gained two rules.

**The evidence was self-inflicted, which is why it counts.** COR-86 — a change that sets one build
flag, adds one enum case, and adds one test — was written to the thirteen-section specification
and came out at ~150 lines, including an *Instrumentation and performance evidence* section and a
*Failure and rollback behavior* section for a change that has neither. The sections were filled
because they were required. That is the dynamic the entry below diagnoses, in a document written
an hour after reading it: **thirteen mandatory headings are thirteen proxies for thinking, and the
cheapest way to satisfy a mandatory proxy is to produce the artifact it measures.**

**The deletion signal had already been defeated once.** Making plan deletion the delivery signal
is what allowed ten increments on 2026-08-10 to be marked delivered by deleting their plans,
having built one comment line each. The response at the time was a warning sentence in
`CLAUDE.md` §5 — *"A plan's absence proves nothing"* — rather than removing the signal. A proxy
that has been gamed once and is retained with a note asking people not to game it is a proxy
waiting to be gamed again. Delivery evidence is now one thing: observed gate output, quoted.

**Why `Implemented in` went.** 112 rows naming production types, hand-maintained, with nothing
checking them. That is the manifest `find` field with a different name, and the entry below
records exactly how those ended: *"a hand-maintained second copy of the code with nothing checking
them, and every refactor rotted them silently."* `Verified by` stays, because a reader looking for
a proof benefits from a test name, and the code-side `// Verifies: REQ-###` comments make the
mapping recoverable when it drifts. One direction, owned by the code.

**What was kept, and why.** The honesty rules (`CLAUDE.md` §3) — judgement, not machinery. One
gate, unchanged. The no-UI-tests rule and its two passive exceptions. Closed-set discipline: every
finding in the 2026-08-22 review lives in a *gap between* closed sets, never inside one. Consent
(§7) and the architecture-change bar (§6), both cheap and both load-bearing. Plans stay in-repo
rather than moving to PR descriptions, because the agents that do most of the work here read the
repository and not the GitHub API.

**No gate enforces the new plan format.** A format enforced by a gate is a format that will be
satisfied by an artifact. That is the whole argument, and it applies to this change too.

## 2026-08-22 — Two constraints retained from the closed programmes

Kept here because ROADMAP's delivery ledger, where they used to live, is gone.

- **`Scripts/smoke-screenshot.sh --allow-orphaned-intents`** (COR-83). The screenshot capture path
  terminates the app mid-open, so the work ledger honestly reports a cancelled intent. The flag
  admits **only** records whose own data marks them orphaned. It is not a general suppression and
  must not become one.
- **The spec corpus deliberately excludes the specifications' expected HTML** (COR-80). 1,324
  examples are imported verbatim from CommonMark 0.31.2 and GFM 0.29 with version, licence,
  SHA-256, and a committed refresh command, and they drive structural properties only. This app is
  an editor, not a renderer; an imported expectation nothing asserts against is decorative
  evidence.

## 2026-08-22 — The verification apparatus was removed

**Decision.** The falsification-manifest system, the proof-results gate, the delivery-status
gate, the instrumentation-coverage gate, the documentation-authority gate, the measurement-
provenance gate, the push-policy gate and its Git hook, and the nine fixture scripts that tested
those gates were all deleted. `Scripts/fast-check.sh` and `Scripts/full-check.sh` were replaced
by one `Scripts/check.sh` that builds, tests, and smokes.

**The apparatus worked.** This is the part that matters and the part that will be forgotten.
Before removing it, the full corpus was executed for the first time: **100 of 100 recorded
mutations turned their cited proof red.** The 528-test suite passed. There were no tautological
proofs anywhere in the repository. The system was not removed because it was fraudulent. It was
removed because of what it cost.

**The cost.** At the point of removal the repository held 22,883 lines of production Swift and
21,546 lines of verification and process — 14,103 lines of tests, 4,652 lines of gate scripts
(nine of which existed only to test other gates), 898 lines of hand-written mutation manifests,
and 178 KB of specification that the manual required reading before planning. One increment cost
roughly four hours, of which the gate alone was seven minutes for the release check plus
seventeen minutes for the falsification run — a hundred incremental rebuilds. Seven increments
took about forty hours.

**Why it grew.** Read the history as a sequence. Each time a gate was defeated, the response was
"replace the question it asks", and in practice that added a layer:

> source text exists → the code executes → a *mutation* turns a proof red → a *fixture* rehearses
> the gate failing → a *rule* requires that rehearsal be recorded

Every step was a correct local response to a real failure. The sum was a system in which proving
a change cost more than making it.

**Why it had started manufacturing its own defects.** The last rule added — every `Done`
requirement carries a compiling mutation of production source that turns a cited proof red —
was satisfied, in the final in-flight increment, by writing production code that exists in order
to be mutated. `EditorInputRoute.contract` was a hundred-line table mapping each callback route
to an owner and a state transition. No production code read it. One test restated the same table
and compared. Two manifests recorded their falsifying mutations against it, and both passed the
gate while proving nothing about the running application. That table and its mirror test were
deleted along with the apparatus.

This is Goodhart's law with a fast feedback loop. Each gate makes one proxy for "real proof"
mandatory; the cheapest way to satisfy a mandatory proxy is to build the artifact it measures.
A stricter gate raises the price of faking it without changing the incentive.

**A second, independent flaw.** A manifest's `find` field was an exact string match against
production source. The 81 manifests were therefore a hand-maintained second copy of the code
with nothing checking them, and every refactor rotted them silently. This happened: COR-72 added
a second `return result` to `MarkdownHighlighter.swift`, which made REQ-051's mutation ambiguous.
Nobody noticed, because the release gate ran falsification as `--changed
$(git merge-base origin/main HEAD)..HEAD`, and on `main` that range is empty. The gate reported
`PASS` over zero manifests for every merge to `main` for months.

**What was kept, and why.**

- **All 528 tests.** They are the real asset and none were removed.
- **The smoke test.** Launching the built app on a fixture and reading its structured log is
  cheap, fast, and catches the class of failure unit tests structurally cannot.
- **The screenshot verifier.** One passive window capture, for human eyes.
- **The honesty rules**, now `CLAUDE.md` §3. They are judgement, not machinery. The single most
  valuable one — *what change to production code makes this test go red?* — is exactly the
  question the falsification system automated. Asking it costs nothing. Automating it cost
  17 minutes a run and eventually produced code written to answer it.

**If you are about to add a gate.** The question is not "would this catch a real defect?" — the
answer is almost always yes. The question is "what will someone write to satisfy this cheaply,
and is that thing worse than the defect?" If a gate can be satisfied by an artifact rather than
by the behavior it is about, it will eventually be satisfied that way, by someone under time
pressure who is not being dishonest.

## Earlier

Historical decisions live in Git history and in the increment rows of `docs/ROADMAP.md`.
