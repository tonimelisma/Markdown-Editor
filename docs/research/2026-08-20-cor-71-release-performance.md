# COR-71 Release performance evidence

- **Authority:** Evidence only; this file does not change architecture, requirements, or budgets.
- **First researched:** 2026-08-20
- **Last verified:** 2026-08-20
- **Environment:** macOS 27.0, arm64 MacBook Pro, Xcode beta, Release optimization with
  `ENABLE_TESTABILITY=YES` for the test host, pinned `swift-cmark` revision `5d9bdaa`.
- **Method:** focused Release `PersistentEditorCharacterizationTests` measurement over every
  `PerformanceCorpus` case at approximately 100,000 UTF-16 units, ten warmups and forty recorded
  samples per case. The callback sample begins at the native replacement delegate boundary and
  ends after the accepted source and attributed-storage patch returns. The proof uses AppKit's
  concrete `NSTextStorage`; mutation-scope tests separately use an instrumented spy. Command:
  `xcodebuild test -project "Markdown Editor.xcodeproj" -scheme "Markdown Editor" -configuration
  Release -destination 'platform=macOS' -derivedDataPath /private/tmp/cor71-perf-proof-build
  -only-testing:"Markdown EditorTests/PersistentEditorCharacterizationTests" ENABLE_TESTABILITY=YES`.
  Result bundle: `/tmp/cor71-perf-proof-build/Logs/Test/Test-Markdown Editor-2026.08.20_19-30-25--0700.xcresult`.

## Observed result

The local classifier, source mutation, transition construction, scoped attributed builder, and
concrete TextKit 1 storage path all stayed below the existing budget. The passing focused run
recorded these p95 callback values in milliseconds: `degenerateParagraph` 1.914,
`structuredProse` 2.157, `heavyLists` 5.598, `tableDense` 5.090, `codeHeavy` 0.724, and
`imageHeavy` 2.130. Every case produced 40 accepted samples and the test passed.

The earlier 22–28 ms measurements came from the spy storage's replacement path and were not
production evidence; that temporary probe was deleted. A separate probe of
`NSLayoutManager.allowsNonContiguousLayout` was also rejected because it did not improve the spy
measurements. No production layout ownership was changed, and no requirement or budget was
changed on the basis of either temporary probe.

- **Refresh when:** the TextKit configuration changes, the approved corpus changes, or the
macOS/Xcode environment changes. A future run must record the exact command, result bundle, corpus
identity, warmups, sample count, median, p95, dropped-input count, and full-replacement count.
