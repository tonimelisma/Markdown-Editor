//
//  SemanticCommandBudgetTests.swift
//  Markdown EditorTests
//

import AppKit
import Foundation
import Testing
@testable import Markdown_Editor

/// The main-actor cost of a semantic formatting command.
///
/// // Verifies: REQ-143 — a command's complete main-actor work is bounded, not merely recorded.
///
/// Before COR-86 this cost was computed on every command, summed into
/// `WorkLedger.mainThreadBlockedNanos`, serialized into every run log, and compared against
/// nothing. `PerformanceBudgetTests.everyMetricHasABudget` could not see it, because the closed
/// set it iterates is `PerformanceSampler.Metric` and the duration lived on `WorkLedger`.
@MainActor
@Suite(.serialized)
struct SemanticCommandBudgetTests {

    /// A document large enough that a whole-document rebuild is visible, driven through the
    /// production command controller rather than the planner directly.
    @MainActor
    private final class Fixture {
        let document = MarkdownDocument()
        let session = EditorSession()
        let router = EditorActionRouter()
        let controller = EditorCommandController()

        /// The paragraph every measured command is applied to, prepended to the corpus.
        ///
        /// // The corpus shapes are lists, tables and fenced code, and `.bold` legitimately
        /// // refuses on several of them — a corpus-dependent selection would measure refusals
        /// // for some cases and work for others. Prepending one ordinary paragraph makes the
        /// // selection identical across every case while leaving the document the same size,
        /// // which is what the whole-document rebuild cost actually depends on.
        static let lead = "Measured paragraph."

        init(corpus: PerformanceCorpus) {
            document.installTextForTesting(Self.lead + "\n\n" + corpus.source())
            session.attach(document: document)
            session.setMode(.wysiwyg)
            installProjection()
            selectLeadParagraph()
            controller.bind(document: document, session: session, actionRouter: router, window: nil)
        }

        private func installProjection() {
            guard let tree = MarkdownParser.parse(
                document.text,
                sourceVersion: document.sourceVersion
            ).get() else { return }
            let index = MarkdownSourceIndex(
                source: document.text,
                sourceVersion: document.sourceVersion
            )
            session.installProjectionForTesting(
                MarkdownProjectionModel.build(tree: tree, index: index),
                tree: tree
            )
        }

        /// The lead paragraph's own content, selected as a range.
        ///
        /// // Deliberately a *range*, not a caret, and deliberately the content rather than the
        /// // block's `projectionRange`, which includes the synthetic trailing break. Both of
        /// // those refuse, and a refused command builds nothing — so either mistake produces a
        /// // budget proof satisfied by refusal. Re-applied before each measured command, because
        /// // applying one rewrites the projection and retires the previous selection's revision.
        func selectLeadParagraph() {
            guard let presentation = session.presentation else { return }
            session.updateWYSIWYGModeState {
                $0.selection = ProjectionSelection(
                    utf16: NSRange(location: 0, length: (Self.lead as NSString).length),
                    revision: presentation.projectionRevision
                )
            }
        }

        func tearDown() { session.detach() }
    }

    /// Every metric that names a main-actor budget must actually be sampled by the route it
    /// describes. A budget nothing records is the same defect one level up.
    @Test func semanticCommandIsSampledByTheProductionRoute() {
        let fixture = Fixture(corpus: .structuredProse)
        defer { fixture.tearDown() }
        let before = fixture.document.text
        fixture.selectLeadParagraph()
        #expect(fixture.controller.perform(.bold) == .accepted)
        #expect(fixture.document.text != before, "the command refused; the sample would be vacuous")
        let summary = fixture.session.drainPerformanceSummaries()
            .first { $0.metric == .semanticCommand }
        #expect(summary != nil, "the production command route recorded no semanticCommand sample")
        #expect((summary?.count ?? 0) > 0)
    }

    /// Typing is excluded, because `nativeInputCallback` already bounds it. Recording both would
    /// place one keystroke under two budgets and make each of them a lie about the other.
    @Test func typingDoesNotRecordASemanticCommandSample() {
        let fixture = Fixture(corpus: .structuredProse)
        defer { fixture.tearDown() }
        guard let presentation = fixture.session.presentation else {
            Issue.record("fixture installed no presentation")
            return
        }
        _ = fixture.session.perform(
            .insertText("x"),
            selection: .projection(ProjectionSelection(
                utf16: NSRange(location: 0, length: 0),
                revision: presentation.projectionRevision
            )),
            expectedSourceRevision: SourceRevision(value: fixture.document.sourceVersion),
            inputRoute: .wysiwygReplacement
        )
        let summary = fixture.session.drainPerformanceSummaries()
            .first { $0.metric == .semanticCommand }
        #expect(summary == nil, "typing recorded a semanticCommand sample and is double-counted")
    }

    /// Commands measured per corpus.
    ///
    /// // Kept deliberately small, and the suite is `.serialized`, because each command blocks
    /// // the main actor for the duration REQ-143 is about. At eight samples running in parallel
    /// // across six corpora this suite starved `ImagePlacementControllerLifecycleTests` past its
    /// // 15 s timeout — the defect under measurement, reproduced against its own neighbours.
    /// // Raise this only once REQ-143 is `Done`.
    static let sampleCount = 3

    /// Worst-case ceilings per corpus.
    ///
    /// // After COR-89, four of six corpora meet REQ-143's 16 ms budget and their Release ceiling
    /// // *is* that budget — the assertion is the requirement. `heavyLists` and `tableDense`
    /// // remain pinned above it, which is why REQ-143 is still `Correction`.
    ///
    /// // These are **not** the requirement's 16 ms budget. REQ-143 is not met yet; COR-88 and
    /// // COR-89 close it. Asserting the budget here would park a permanently red test in the
    /// // suite, and asserting nothing would leave the regression undetected — so this pins the
    /// // measured behaviour instead, exactly as `ContrastConformanceTests` pinned its violations
    /// // while REQ-139 was in `Correction`. When every corpus is under budget, delete these
    /// // tables and assert `PerformanceSampler.budgetNanos[.semanticCommand]` directly.
    ///
    /// // Configuration-aware because the gate runs Debug and the evidence in
    /// // `research/2026-08-22-semantic-command-main-actor-cost.md` is Release; one table would
    /// // either be unfalsifiable in Debug or spuriously red in Release.
    static func ceilingMillis(for corpus: PerformanceCorpus) -> Double {
        #if DEBUG
        // Deliberately loose. The gate runs Debug with tests in parallel, so these numbers carry
        // scheduling contention as well as the work; a tight bound here would be flaky rather
        // than informative. Their job is to catch a catastrophic regression, not drift.
        switch corpus {
        case .degenerateParagraph: return 30
        case .codeHeavy: return 60
        case .imageHeavy: return 170
        case .structuredProse: return 200
        case .tableDense: return 480
        case .heavyLists: return 440
        }
        #else
        // Release is where the evidence lives and where drift matters — roughly 1.7x the
        // measured worst case.
        // Four corpora now meet REQ-143 outright, so their ceiling *is* the requirement's
        // budget: the assertion is the requirement, not a pin. Only the two pathological shapes
        // remain pinned above it.
        switch corpus {
        case .degenerateParagraph: return 16
        case .codeHeavy: return 16
        case .imageHeavy: return 16
        case .structuredProse: return 16
        case .heavyLists: return 55
        case .tableDense: return 50
        }
        #endif
    }

    /// // Verifies: REQ-143 — the command's main-actor cost, on every approved corpus shape.
    ///
    /// Fails if a command stops applying, if no sample is recorded, or if the measured p95
    /// regresses past its pinned ceiling.
    @Test(arguments: PerformanceCorpus.allCases)
    func semanticCommandStaysWithinItsMeasuredCeiling(_ corpus: PerformanceCorpus) async throws {
        let fixture = Fixture(corpus: corpus)
        defer { fixture.tearDown() }

        // One warm-up command, then the measured ones. The first command on a fresh process pays
        // for lazily-initialised caches that a real session pays once, not per command.
        fixture.selectLeadParagraph()
        #expect(fixture.controller.perform(.bold) == .accepted)
        _ = fixture.session.drainPerformanceSummaries()

        var accepted = 0
        for _ in 0..<Self.sampleCount {
            fixture.selectLeadParagraph()
            if fixture.controller.perform(.bold) == .accepted { accepted += 1 }
            // Hand the main actor back between commands. Each one blocks it for the duration
            // REQ-143 is about, and eight back-to-back starved the asynchronous image-placement
            // suite past its 15 s timeout — the defect under measurement, reproduced against this
            // suite's own neighbours. Yielding does not affect the per-command measurement.
            await Task.yield()
        }
        #expect(
            accepted == Self.sampleCount,
            "\(corpus.rawValue): only \(accepted)/\(Self.sampleCount) commands applied — a refused command builds nothing, so the timing below would describe a refusal rather than the work"
        )

        let summary = try #require(
            fixture.session.drainPerformanceSummaries().first { $0.metric == .semanticCommand },
            "no semanticCommand samples for \(corpus.rawValue)"
        )
        // The worst of the samples, not a percentile. Five samples cannot express a 95th
        // percentile honestly — `p95` over five is simply the maximum — so this asserts the
        // maximum and says so. It is the stricter bound, so satisfying it satisfies REQ-143's
        // p95 form as well.
        let worstMillis = Double(summary.max) / 1_000_000
        let ceiling = Self.ceilingMillis(for: corpus)
        #expect(
            worstMillis <= ceiling,
            "\(corpus.rawValue): semantic command worst-of-\(Self.sampleCount) \(String(format: "%.1f", worstMillis)) ms regressed past its pinned \(ceiling) ms ceiling"
        )
    }

    /// REQ-143 is `Correction`, and this records why: the approved corpus does not meet the
    /// declared budget. Delete this test together with the ceilings when it does.
    @Test func theBudgetIsNotYetMetAndIsRecordedAsCorrection() {
        let budgetMillis = Double(PerformanceSampler.budgetNanos[.semanticCommand] ?? 0) / 1_000_000
        let overBudget = PerformanceCorpus.allCases
            .filter { Self.ceilingMillis(for: $0) > budgetMillis }
        #expect(
            !overBudget.isEmpty,
            """
            every corpus ceiling is now within the \(budgetMillis) ms budget — REQ-143 can move to \
            Done: delete ceilingMillis and this test, and assert the budget directly
            """
        )
    }

    /// Closed-set gate over `WorkLedger`'s duration fields.
    ///
    /// // Verifies: REQ-143 — the second door. `mainThreadBlockedNanos` escaped
    /// // `PerformanceBudgetTests.everyMetricHasABudget` for months not because that guard was
    /// // wrong but because it iterates `PerformanceSampler.Metric` and this duration lives on a
    /// // different type. Reflection makes the ledger's own fields the closed set, so a new
    /// // `...Nanos` field reddens this test until someone declares what bounds it.
    @Test func everyRecordedDurationNamesABudgetedMetric() {
        let declared: [String: PerformanceSampler.Metric] = [
            "mainThreadBlockedNanos": .semanticCommand,
        ]
        let durationFields = Mirror(reflecting: WorkLedger()).children
            .compactMap(\.label)
            .filter { $0.hasSuffix("Nanos") }

        // The detector proves itself: if reflection stopped seeing the ledger's fields, the loop
        // below would iterate nothing and this test would pass while checking nothing.
        #expect(
            durationFields.contains("mainThreadBlockedNanos"),
            "the reflection detector found no known duration field and would pass vacuously"
        )

        for field in durationFields {
            guard let metric = declared[field] else {
                Issue.record("WorkLedger.\(field) records a duration that names no budgeted metric")
                continue
            }
            #expect(
                PerformanceSampler.budgetNanos[metric] != nil,
                "WorkLedger.\(field) names \(metric), which has no budget"
            )
        }
    }
}
