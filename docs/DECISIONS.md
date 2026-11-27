# DECISIONS

Decisions with consequences. Newest first. This is not an archive of everything ever decided —
it is the short list of things someone will otherwise re-litigate or accidentally undo.

## 2026-11-27 — A release launches its bundle twice; the first launch's stall is the runner's

**Decision.** `Scripts/release.sh` launches the signed bundle twice. The first launch passes every
smoke check except `mainActorStall`, which it is allowed. The bundle must start, open the
fixture, take both edits, and exit cleanly with no other fault. The second launch is held to every
check, stalls included.

**What happened.** v1.0.1 could not be published. Release runs 45921027714 and 45922511341 each
built, signed and launched it, recorded two `mainActorStall` faults (1.4 s), and refused.
`repeat-smoke.yml`, now able to launch the hardened Release bundle, found this:

| Runs | First launch on the runner | Later launches |
| --- | --- | --- |
| Release, the same copy (45923148087, 45923150495) | stalled, 2 of 2 | 12 passed |
| Release, a fresh copy at a new path each time (45923944905) | stalled | 7 passed |
| Release, first launch only (45924753146; 45924758118 under `spindump`) | stalled, 2 of 2 | not run |
| Release, `taskpolicy -d important` (45925257684, 45925260329) and its control (45925262536) | stalled, 3 of 3 | 5 passed, 1 `presentationRecovered` (below) |
| Release, first launch 45 s after the build (45924755511) | passed | 2 passed |
| Release, first launch after warming the profilers for several seconds (45923942236) | passed | 5 passed |
| Debug, as `check.sh` launches it (45922040268) | passed (11 s, the slowest) | 11 passed |

In all, the first launch shortly after the build stalled every time: 10 of 10, counting the two
release runs. None of the 43 later launches stalled. The `spindump` of the stalled first launch
in 45924758118 shows the cause. The machine had been up 239 s, and 12% of the shared cache was
resident. The main thread spent 294 of its 546 samples in one synchronous call:
`makeWindowControllers`, which lays out the first window, builds both editors, and runs AppKit's
first-use set-up (`NSSpellChecker`, the text-input cursor, ICU locale tables, the default font).
192 of those samples were asleep in the kernel's `throttle_lowpri_io`, with 4,644 page-ins, while
Spotlight indexed the build. What stalls is a cold virtual disk, read through a throttled I/O
policy, on a just-booted VM. A Mac that people use is not in that state.

**Criteria** (VISION's evaluation section):

1. Automated verification: the gate must keep failing for the app's defects.
2. Deterministic failure behaviour: a release must not depend on how warm the runner is.
3. Measured performance: a measurement describes only the input it was measured on (CLAUDE.md §3).
4. Maintenance cost.

| Option | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| **Two launches; the first may stall (chosen)** | ✓ every check binds on a launch of the exact bundle, and every check but one on its first | ✓ no stall in 43 later launches | ✓ the stall is asserted on a warm launch, as `check.sh`'s already is | ✓ one script, an existing verifier flag |
| Wait a fixed time after the build | ✓ | ~ 45 s worked once; nothing says how long is enough | ✓ | ✓ |
| Launch with unthrottled I/O (`taskpolicy -d important`) | ✓ | ✗ tried: the first launch still stalled, 2 of 2 | — | ✓ |
| Allow `mainActorStall` on every release launch | ✗ a stall the app causes would ship | ✓ | ✗ | ✓ |
| Do nothing | ✓ | ✗ no release can publish | ✓ | ✓ |

**Where it is worse.** A stall that only the very first launch on a machine shows, and that the
app causes, no longer stops a release. `check.sh`'s smoke launch could not catch one either: it
comes after the test suite has warmed the runner. The 2.9 s first-window cost on a cold machine
is real work, though. Building the Source editor only when Source is first shown is one way to
cut it, and it is recorded as open in ROADMAP.

**Also changed: a docs-only push no longer publishes an app that `main` has not built.** v1.0.1
was published from #91, a documentation change. #90's own `main` run had failed two timing-bound
tests, and its re-run was cancelled when #91 landed. #91's CI skipped macOS, because its diff was
documentation, and passed, and Release then published the app #90 had changed. That tree had
passed `check.sh` as pull request #90, and both of the release's launches passed, so v1.0.1 is
the tree that was tested. Even so, nothing on `main` had required it. CI's `changes` job now also
asks, on a push to `main`, whether the app (`Scripts/lib/app-paths.sh`, the list `release.sh`
publishes by) differs from the newest release. If it does, the macOS job runs.

**Also seen.** Control run 45925262536's second launch recorded `presentationRecovered`
(`patchUnprovable`, COR-71): a provisional WYSIWYG presentation disagreed with the authoritative
parse of the same revision. It was seen once in about 40 launches. It is an application fault,
and a release that hits it is still refused. It is open in ROADMAP.

## 2026-11-27 — Apache-2.0, a README, and an app icon drawn in code

**Decision.** The repository is licensed under the Apache License 2.0. It has a README for people
who find it, and an app icon generated by `Scripts/make-app-icon.py`. Sparkle's MIT notice now ships
in the app beside cmark-gfm's.

**Why now.** The repository went public on 2026-11-26 with no licence, so nobody had permission to
use its code. Every published build embeds Sparkle, whose licence requires its notice to travel
with it, and a release disk image showed a blank icon. The owner asked for everything to be fixed.

**Criteria.**

1. The owner's own precedent across his projects.
2. VISION's "no lock-in".
3. Clear permission for anyone who finds the code.
4. Cost.

**The licence.**

| Option | 1 | 2–3 | 4 |
| --- | --- | --- | --- |
| **Apache-2.0 (chosen)** | ✓ latchkey, the owner's other public app with a licence | ✓ permissive, with an explicit patent grant | ✓ |
| MIT | ✗ not used by the owner | ✓ but no patent grant | ✓ |
| GPL-3.0 | ✗ | ✗ copyleft limits reuse | ✓ |
| None (Otos's choice) | ~ | ✗ all rights reserved, so the public code cannot be used | ✓ |

**Where it is worse.** A licence is the owner's to choose, and this one was chosen for him, by
precedent. Code published under Apache-2.0 stays available under it. While the app has no users,
switching to another licence for later versions costs one commit.

**The icon** is drawn in code rather than in a design tool, so a cloud session can regenerate it.
It uses the community's public-domain Markdown mark (an M and a down arrow) on a paper page. It is
a placeholder of honest quality, not a brand.

## 2026-11-26 — An ad hoc app needs the library-validation exception, and a release is proved by launching it

**Decision.** The ad hoc Release build is re-signed with
`com.apple.security.cs.disable-library-validation` (`Scripts/adhoc-harden.sh`), and no release is
published until that exact bundle has been launched and has passed REQ-098's smoke assertions
(`Scripts/release.sh`). `get-task-allow` is dropped from the published signature at the same time.

**What happened.** v1.0.0 (build 202) was published, installed, and could not start. Every launch
died in dyld before `main`:

```text
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Reason: ... not valid for use in process: mapping process and mapped file (non-platform)
have different Team IDs
```

An ad hoc signature carries no Team ID. Library validation, part of the hardened runtime, loads
only a library whose team matches the process's, and "no team" never matches "no team" — so an ad
hoc app cannot load its own embedded framework. Signing the bundle deeply in one pass does not
help; observed on the published bundle and on a build from source.

**Why CI was green.** The gate's smoke run launches the *Debug* app, and Debug is signed without
the hardened runtime: it sets `ENABLE_DEBUG_DYLIB = YES` (previews), and library validation would
refuse that build's own `Markdown Editor.debug.dylib` exactly as it refused Sparkle. Re-signing the
Debug bundle with `--options runtime` and nothing else changed reproduces the crash, which is the
evidence that the hardened runtime is the single switch. `ENABLE_HARDENED_RUNTIME = YES` in both
configurations, so the project setting said nothing. Release signs `0x10002(adhoc,runtime)`, Debug
`0x2(adhoc)`. The release path then checked only `codesign --verify --deep --strict`, which is
content with an app that cannot start, and nothing ever launched a Release build.

**Criteria** (VISION: the product is installable and it works; honesty of evidence; no step on the
owner's Mac; one obvious path, cost).

| Option | Installs and runs | Security given up | No Mac | Cost |
| --- | --- | --- | --- | --- |
| **A. Library-validation exception on the ad hoc build only (chosen)** | ✓ | the one exception; the rest of the hardened runtime stays | ✓ | ✓ one script |
| B. Require a Developer ID (`CERTIFICATE_P12`) | ✓ | none — and notarization becomes possible | ✗ needs a paid account first; no release until then | ✗ |
| C. Drop the hardened runtime from Release | ✓ | all of it, and notarization is then impossible | ✓ | ✓ |
| D. Link Sparkle statically, or drop the updater | ✓ | none | ✓ | ✗ Sparkle ships as a framework; REQ-033 would go |
| E. Do nothing | ✗ | — | ✓ | — |

B is the right end state and A does not block it: the exception is granted only when there is no
identity, so the day `CERTIFICATE_P12` is set, library validation comes back on by itself. C gives
up far more for the same benefit. D trades a shipped requirement for a signing nicety.

**Where A is worse.** The app can load any library placed inside its bundle. For an unsigned
distribution this changes little — anyone who can write into the bundle can also re-sign it ad hoc
— but under a Developer ID it would matter, which is why the exception is not granted then.

**Proof.**

- The defect, from source: a Release build with the release path's own flags, launched, dies in
  dyld with the message above. The same bundle after `Scripts/adhoc-harden.sh` starts and passes
  the smoke assertions (64 records, 5 host updates).
- `Scripts/test-adhoc-harden.sh`, run by the gate: it builds the smallest bundle that can show the
  defect — an ad hoc app, hardened runtime, loading a dylib from its own `Contents/Frameworks` —
  and requires that bundle to **fail** to launch before `Scripts/adhoc-harden.sh` touches it, and
  to run after. Mutations turn it red: dropping the exception (the app stays unable to launch) and
  keeping `get-task-allow`. It also requires the script to refuse an app whose entitlements are
  not the ones Xcode generates, rather than re-sign it with fewer.
- `Scripts/release.sh` refuses to publish unless the signed bundle carries the exception, does not
  carry `get-task-allow`, and passes `SMOKE_APP=… Scripts/smoke-test.sh` — a launch of the bundle
  that is about to be published, asserted on by REQ-098's verifier, whose own discrimination
  `Scripts/test-verify-smoke-log.sh` proves in the gate.

**Where the proof is weaker than it looks.** **GitHub's macOS runners do not enforce library
validation.** The probe above launches there, unhardened — found when this change's own test failed
on CI for exactly that reason, which is the only reason it is known. Two consequences, and they are
the ones to remember:

- A release-time launch **could not have caught build 202**, and cannot catch the next defect of
  this kind. The app would have started on the runner and still died on every Mac. The launch is
  kept because it catches everything else a release can be broken by; what catches *this* is the
  entitlement assertion, which is static and the same on every host.
- The gate's test discriminates only where library validation is enforced — the owner's Mac, and
  anyone else's. On a host without it, it says so in its own output and reports only the
  entitlement half as proved. It never reports a proof it did not make.
- That launch installs nothing: REQ-034 keeps a smoke run from checking for updates
  (`onlyAKeyedBuildOutsideVerificationUpdatesItself`).
- Not yet observed: a published release that a person has installed and opened.

## 2026-11-26 — No Mac, not even once: the update key comes from a secret, and signing is ad hoc

**Decision.** Releasing needs nothing from the owner's Mac. The owner reacted to
`Scripts/release-setup.sh`, a one-time script run on the Mac: "Wtf are these scripts. The repo is
supposed to work without my macbook." latchkey and Otos both export their certificate and update key
from the Mac's keychain, and Otos repeats that yearly, so copying them was wrong here.

- The EdDSA update key is derived on GitHub's runner from one environment secret, `SPARKLE_SEED`, a
  random password the owner sets in GitHub's web settings (`Scripts/sparkle-key.sh`).
- The build is signed ad hoc unless an optional `CERTIFICATE_P12` is set.
- `Scripts/release-setup.sh` is deleted.

**Criteria.**

1. The owner's constraint: no step on the Mac, ever.
2. Updates keep working for every installed copy.
3. Security: no key in the repository, in logs, or in a session's transcript.
4. One obvious path, cost.

**Alternatives, ranked.**

| Option | 1 | 2 | 3 | 4 |
| --- | --- | --- | --- | --- |
| **A. Key derived from a secret password; ad hoc signing (chosen)** | ✓ | ✓ Sparkle accepts any identity while the EdDSA key is unchanged | ✓ only the secret holds it | ✓ one secret |
| B. Key generated by a workflow, stored as a secret with a personal access token | ✓ | ✓ | ✗ a token that can write secrets | ✗ a token to create, rotate, and an extra workflow |
| C. Key generated in this cloud session and handed to the owner | ✓ | ✓ | ✗ the key passes through a transcript | ✓ |
| D. Certificate created through the App Store Connect API in CI | ✓ | ✓ | ✓ | ✗ needs a paid account and an API key first |
| E. Keep `release-setup.sh` (the siblings' shape) | ✗ | ✓ | ✓ | ✓ |

**Where A is worse.**

- **Losing the password breaks updates.** Installed copies reject every later update until
  reinstalled by hand, so it belongs in a password manager.
- **The key is only as strong as the password.** A generated password of 32 or more characters is
  well beyond guessing, but it is not a keychain.
- **Ad hoc signing.** The first open needs "Open Anyway". Each update has a new code identity, so
  macOS may ask again for permissions it granted to the previous build. A Developer ID removes
  both and can be added later without breaking updates (Sparkle 2.10.1 `SUUpdateValidator`: the
  same EdDSA key with any signing identity passes). Until then VISION's notarized download is
  not met.
- **An ad hoc app cannot load its own frameworks** under the hardened runtime, which cost build 202
  every launch. It now carries the library-validation exception, which a Developer ID build does
  not need (the entry above).

**Proof.**

- `Scripts/test-release-scripts.sh`:
  - the same password gives the same key, and a different one a different key;
  - a signature verifies under Python's `cryptography`, an implementation independent of the
    OpenSSL that made it;
  - a changed file fails to verify;
  - mutations of the derivation and of the signed input turn it red.
- Every release also checks its signature with Sparkle's own `sign_update --verify` before
  publishing.
- Observed since: v1.0.0 (build 202) published and installed, and it could not start at all — the
  signing above was published unlaunched (the entry above).
- Not yet observed: an update installing on a real Mac.

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
  secrets, the release is notarized and stapled, as VISION's Distribution section promises. With
  none it is signed ad hoc (entry above), and the release notes say how to open it. That is worse
  than VISION until a Developer ID exists.
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
- Verification builds (`check.sh`, the smoke scripts) sign ad hoc wherever they run
  (`Scripts/lib/build-settings.sh`). The first CI run failed because the project's automatic
  signing wanted a team certificate the runner does not have, and no verification should depend
  on one person's Apple account. latchkey settled the same for its sandbox Mac the same day. Only
  `Scripts/release.sh` signs with a configured identity, when one is set.
- The repository gained a shared scheme. CI's fresh checkout has no autocreated scheme to rely on.
- Not yet observed: an installed copy updating itself. Until then REQ-033 is `Active`, not `Done`.

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
