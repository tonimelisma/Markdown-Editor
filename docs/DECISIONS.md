# DECISIONS

Decisions with consequences. Newest first. This is not an archive of everything ever decided —
it is the short list of things someone will otherwise re-litigate or accidentally undo.

## 2026-11-26 — Cloud-first development: CI is the Mac, Sparkle is the installer

**Decision.** Claude Code cloud sessions are this repository's default environment. A cloud session
has no Xcode, so GitHub Actions' `xcode-27` runner runs `Scripts/check.sh` for every pull request and
every push to `main`. That run, on a pull request's last commit, verifies a change made in the cloud.
A session on the owner's Mac is optional: it runs the same gate locally and does not wait for CI. Where
there is no Xcode, `Scripts/check.sh` ends `INCOMPLETE` with exit status 3, never `PASS`.

Every `main` commit that passes CI and changes the app is published by `.github/workflows/release.yml`:
a signed Release build, a disk image, and Sparkle's feed. Installed copies update themselves within
the hour (REQ-033). The shape is Otos's ADR 0059, adapted. The evidence is in
[research/2026-11-26-cloud-first-development.md](research/2026-11-26-cloud-first-development.md).

**Criteria**, from VISION's objectives and evaluation order:

1. No silent pass. `CLAUDE.md` §3: the build and the tests are either observed or reported as not run.
2. Trustworthy files. An update must not cost the user an edit.
3. Local and private (objective 5). Any network access is bounded, named and carries no content.
4. One obvious path, and cost. One gate everywhere, one installer, and no apparatus the
   2026-08-22 entry below would recognise.
5. The owner's stated constraint: no dependency on the MacBook.

**Alternatives, ranked.**

| Option | 1 | 2 | 3 | 4 | 5 |
| --- | --- | --- | --- | --- | --- |
| **A. Cloud sessions + GitHub macOS runner + Sparkle (chosen)** | ✓ CI's run is observed output | ✓ installs on quit, after autosave | ✓ one feed request, no profile | ✓ one gate, one workflow | ✓ |
| B. Cloud sessions drive the Mac (latchkey's `shell_run`, Remote Control) | ✓ | ✓ | ✓ | ✗ two verification paths | ✗ needs the Mac awake |
| C. A self-hosted runner on the Mac | ✓ | ✓ | ✓ | ✓ | ✗ needs the Mac awake; runs CI code on it |
| D. Sparkle replaced by a hand-rolled updater or an install script | ✓ | ? | ✓ | ✗ re-implements signature checks and replace-and-relaunch | ✓ |
| E. Do nothing (develop on the Mac) | ✓ | — | ✓ | ✓ | ✗ |

B was closest. It would let a cloud session see a real local run. It still depends on the Mac being
awake, and it adds a second way to verify the same change.

**Choices inside A, and where each is worse.**

- **Two ways to work, as latchkey settled the same day.** A cloud session never reaches the
  MacBook during development (owner, in latchkey: "never via latchkey MCP access to my macbook
  from the cloud env during dev process"), except for a live check the owner asks for. A local
  session is one the owner started on the Mac. Both are described in `CLAUDE.md` itself (owner:
  "All in CLAUDE.md").
- **Five minutes per commit, local and CI together** (owner, in Otos: "just try to ensure each
  commit wraps up in 5 minutes of testing"). `check.sh` prints its duration. CI restores Xcode's
  compilation cache, and only a push to `main` saves it. Otos's prefix mapping is left out because
  it rewrites `#filePath`, which the tests here use to find files. A CI run's checkout path is
  constant, so its cache hits without it. Not yet measured here: the first CI runs give the
  baseline.

- **Automatic checks and installs, with no consent prompt.** `SUEnableAutomaticChecks` and
  `SUAutomaticallyUpdate` are set, as in latchkey and Otos, because the owner asked for
  auto-updates. This is worse for "no surprises" for any future user who did not expect an hourly
  request to GitHub. Sparkle's second-launch permission prompt is the change to make when the app is
  distributed to others.
- **The update key is set only in the Release configuration.** Debug and Release share a bundle
  identifier (see the restoration note in `MarkdownAppDelegate.init`). A Debug build that carried
  the key would replace itself, in DerivedData, with the published build.
- **Signing takes what it is given.** With a Developer ID identity and App Store Connect API key
  secrets, the release is notarized and stapled, as VISION's Distribution section promises. With an
  Apple Development identity, as the siblings use, it is not, and the release notes say how to open
  it. That is worse than VISION until a Developer ID exists.
- **The repository is public** (owner, 2026-11-26: "Make repo public"), as latchkey and Otos are.
  A private repository's release assets cannot be downloaded without credentials, so the feed
  would be unreachable. Standard macOS runners are also free for public repositories, and the first
  CI run, while the repository was private, was never started. Publishing to a separate public
  repository was the alternative, and it was dropped from the scripts once this was chosen. The
  history was checked before publication: no credential, no personal path or location metadata.
  The one private value in it is the Apple team ID in `project.pbxproj`, which latchkey and Otos
  keep out of their repositories. It is also visible in every signed build. Removing it from
  history would need a rewrite of `main` and stays the owner's call.
- **Documentation-only changes skip the macOS job**, which builds nothing they could change. The
  `changes` job lists exactly which paths count as documentation; anything else, `.github/`
  included, runs macOS.

**Consequences.**

- REQ-030 now allows one network access: the update check, REQ-033. `PrivacyBoundaryTests` bounds it
  to the one file that imports Sparkle.
- `CLAUDE.md` was rebuilt around this, with its section numbers kept because other documents
  cite them. The stale model-named commit trailer gave way to the harness's attribution, and "small
  doc fixes can go straight to `main`" gave way to one pull request per session.
- The repository gained a shared scheme. CI's fresh checkout has no autocreated scheme to rely on.
- The owner runs `Scripts/release-setup.sh` once on the Mac, because the signing certificate's
  private key is in its keychain. Nothing after that needs the Mac.
- Not yet observed: a published release, and an installed copy updating itself. Both wait on the
  owner's setup and the visibility choice. Until then REQ-033 is `Active`, not `Done`.

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
