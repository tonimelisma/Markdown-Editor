//
//  LaunchSurfaceTests.swift
//  Markdown EditorTests
//

import Foundation
import Testing
@testable import Markdown_Editor

/// The application's launch surface is declared, complete, and cannot mutate a document by
/// accident.
///
/// // Verifies: REQ-144.
///
/// The shipping binary honours `--benchmark-manifest`, `--diagnostic-smoke-exit` and seven
/// `MARKDOWN_EDITOR_*` variables, one of which makes the app type into the open document. That is
/// deliberate — `Scripts/benchmark.sh` builds Release, so the performance evidence describes the
/// configuration that ships — but before COR-90 no requirement described the surface and nothing
/// enumerated it.
struct LaunchSurfaceTests {

    /// Nothing outside the declared list is read. An *absence* proof, with a self-verifying
    /// detector: source inspection is the only way to see a variable nobody declared.
    @Test func noUndeclaredEnvironmentVariableIsRead() throws {
        let source = try productionSourceText()
        #expect(source.contains("MARKDOWN_EDITOR_"), "detector matched nothing and would pass vacuously")

        var found: Set<String> = []
        let pattern = try NSRegularExpression(pattern: "MARKDOWN_EDITOR_[A-Z_]+")
        let ns = source as NSString
        pattern.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            found.insert(ns.substring(with: match.range))
        }

        let declared = Set(MarkdownAppDelegate.LaunchSurface.environmentVariables)
        #expect(
            found.subtracting(declared).isEmpty,
            "undeclared environment variables: \(found.subtracting(declared).sorted())"
        )
        #expect(
            declared.subtracting(found).isEmpty,
            "declared but never read: \(declared.subtracting(found).sorted())"
        )
    }

    /// The safety property. Every document-mutating switch is additionally gated on the smoke
    /// argument, so no ordinary launch — and no environment variable alone — can make the
    /// application type into the user's document.
    @Test func documentMutatingSwitchesRequireTheSmokeArgument() {
        #expect(!MarkdownAppDelegate.LaunchSurface.documentMutating.isEmpty)
        #expect(
            Set(MarkdownAppDelegate.LaunchSurface.documentMutating)
                .isSubset(of: Set(MarkdownAppDelegate.LaunchSurface.environmentVariables))
        )
        // `smokeExercisesEdits` is `isSmokeRun && env == "1"`. This process is a test host and
        // therefore not a smoke run, so setting the variable must still not enable it.
        setenv("MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS", "1", 1)
        defer { unsetenv("MARKDOWN_EDITOR_SMOKE_EXERCISE_EDITS") }
        #expect(MarkdownAppDelegate.isSmokeRun == false, "the test host is not a smoke run")
        #expect(
            MarkdownAppDelegate.smokeExercisesEdits == false,
            "an environment variable alone enabled document-mutating behaviour"
        )
    }

    /// The declared argument list is closed and free of duplicates, so a new mode of operation
    /// cannot be added without appearing here.
    @Test func declaredArgumentsAreUniqueAndFlagShaped() {
        let arguments = MarkdownAppDelegate.LaunchSurface.arguments
        #expect(!arguments.isEmpty)
        #expect(Set(arguments).count == arguments.count)
        for argument in arguments {
            #expect(argument.hasPrefix("--"), "\(argument) is not a launch flag")
        }
    }
}
