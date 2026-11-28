# Performance baseline

- **Authority:** Evidence only
- **First researched:** 2026-08-21
- **Last verified:** 2026-08-21
- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.
Machine: an arm64 MacBook Pro
OS: macOS 27.0
OS build: 26A5416b
Architecture: arm64
Configuration: Release
Xcode: Xcode 27.0; Build version 27A5228h
Corpus digest: bbdeb4d3109c93dda6c58ef34e798a0d1ca2e2d20bd673c36df67c01b59b845c
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Source implementation digest: e8f5aba0a5d9011eced14e060c3d92e181892abb9cde66bad9dce4f7cccf95d5
Source implementation authority: PerformanceCorpus.swift, BenchmarkDriver.swift, IncrementalSourceHighlighter.swift, SourceEditor.swift, and PerformanceSampler.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 0e2764ff6804f35e2fc0add0a460823a5f57747f
Run ID: ec1d87aa-cdd4-4085-812e-6f659975b660

| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | parse budget exceeded | source budget exceeded | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 11374750 | n/a | False | n/a | 336 | 160 | 8 | 176 |
| applyCommands | codeHeavy | 100000 | 50658625 | n/a | False | n/a | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 464208 | n/a | False | n/a | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 10387833 | n/a | False | n/a | 210 | 100 | 5 | 110 |
| applyCommands | heavyLists | 10000 | 11481625 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 71850250 | n/a | False | n/a | 42 | 20 | 1 | 22 |
| applyCommands | imageHeavy | 10000 | 1875458 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 100000 | 19243625 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | structuredProse | 10000 | 5201042 | n/a | False | n/a | 168 | 80 | 4 | 88 |
| applyCommands | structuredProse | 100000 | 14707500 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 20235834 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 23999000 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| openAndIdle | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | structuredProse | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | structuredProse | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | tableDense | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| scrollDocument | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | heavyLists | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | heavyLists | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | tableDense | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | tableDense | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| soak | codeHeavy | 10000 | 35700042 | 24462875 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | codeHeavy | 100000 | 25211041 | 102923500 | False | True | 1140 | 1140 | 0 | 1140 |
| soak | degenerateParagraph | 10000 | 7611375 | 2321750 | False | False | 2752 | 2752 | 0 | 2752 |
| soak | degenerateParagraph | 100000 | n/a | 72179958 | n/a | False | 760 | 760 | 0 | 760 |
| soak | heavyLists | 10000 | 28715834 | 65860333 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | heavyLists | 100000 | 102805750 | 392228125 | True | True | 760 | 760 | 0 | 760 |
| soak | imageHeavy | 10000 | n/a | 56406000 | n/a | False | 1032 | 1032 | 0 | 1032 |
| soak | imageHeavy | 100000 | n/a | 316423041 | n/a | True | 1140 | 1140 | 0 | 1140 |
| soak | structuredProse | 10000 | 17400125 | 34682625 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | structuredProse | 100000 | 49487916 | 183956625 | False | True | 760 | 760 | 0 | 760 |
| soak | tableDense | 10000 | 31022458 | 71140125 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | tableDense | 100000 | 120384125 | 403052333 | True | True | 1140 | 1140 | 0 | 1140 |
| toggleModes | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 440 | 440 | 0 | 440 |
| toggleModes | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | heavyLists | 10000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | heavyLists | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | structuredProse | 10000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | structuredProse | 100000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 10000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 100000 | n/a | n/a | n/a | n/a | 440 | 440 | 0 | 440 |
| typeAdjacentMarkup | codeHeavy | 10000 | 123057916 | 22286625 | True | False | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 31923125 | 125309875 | False | True | 80 | 80 | 0 | 80 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 10306500 | 3208125 | False | False | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 97180834 | n/a | False | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | heavyLists | 10000 | 45185208 | 63656417 | False | False | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | heavyLists | 100000 | 154238750 | n/a | True | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | imageHeavy | 10000 | 9079208 | 84249042 | False | False | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | structuredProse | 10000 | 46429458 | 45153125 | False | False | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | structuredProse | 100000 | 69119416 | 201444875 | False | True | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | tableDense | 10000 | 38792333 | 92890333 | False | False | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | tableDense | 100000 | 140461458 | n/a | True | n/a | 280 | 280 | 0 | 280 |
| typeInTable | codeHeavy | 10000 | 31062875 | 165178833 | False | True | 28 | 28 | 0 | 28 |
| typeInTable | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 240 | 240 | 0 | 240 |
| typeInTable | degenerateParagraph | 10000 | 3073791 | 35145667 | False | False | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 124467833 | 86073958 | True | False | 28 | 28 | 0 | 28 |
| typeInTable | heavyLists | 100000 | n/a | 164388750 | n/a | True | 200 | 200 | 0 | 200 |
| typeInTable | imageHeavy | 10000 | n/a | 73497708 | n/a | False | 24 | 24 | 0 | 24 |
| typeInTable | imageHeavy | 100000 | n/a | 194264333 | n/a | True | 200 | 200 | 0 | 200 |
| typeInTable | structuredProse | 10000 | n/a | 106924291 | n/a | True | 20 | 20 | 0 | 20 |
| typeInTable | structuredProse | 100000 | n/a | 196408458 | n/a | True | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 210141792 | 102113959 | True | True | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | n/a | n/a | n/a | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 45084875 | 28218333 | False | False | 40 | 40 | 0 | 40 |
| typeProse | codeHeavy | 100000 | 42035875 | 159195167 | False | True | 320 | 320 | 0 | 320 |
| typeProse | degenerateParagraph | 10000 | 9230208 | 3842583 | False | False | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 3323917 | 24023083 | False | False | 480 | 480 | 0 | 480 |
| typeProse | heavyLists | 10000 | 61619500 | 128084500 | False | True | 36 | 36 | 0 | 36 |
| typeProse | heavyLists | 100000 | 119694666 | n/a | True | n/a | 280 | 280 | 0 | 280 |
| typeProse | imageHeavy | 10000 | 16031250 | 64827167 | False | False | 36 | 36 | 0 | 36 |
| typeProse | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| typeProse | structuredProse | 10000 | 47850250 | 84803792 | False | False | 24 | 24 | 0 | 24 |
| typeProse | structuredProse | 100000 | 73211459 | 224588584 | False | True | 320 | 320 | 0 | 320 |
| typeProse | tableDense | 10000 | 24275416 | 75084334 | False | False | 36 | 36 | 0 | 36 |
| typeProse | tableDense | 100000 | 145888834 | n/a | True | n/a | 240 | 240 | 0 | 240 |
| undoRedoStorm | codeHeavy | 10000 | 31186125 | 6701917 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | 45056500 | 31659208 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 5842458 | 1480375 | False | False | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 59903334 | n/a | False | 600 | 600 | 0 | 600 |
| undoRedoStorm | heavyLists | 10000 | 33993834 | 3820292 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | heavyLists | 100000 | 99209375 | 26340208 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 10000 | 19037292 | 2637125 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 25826167 | n/a | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 16368291 | 1167375 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 100000 | 60732166 | 14310208 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 10000 | 24881750 | 2199000 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 100000 | 116885291 | 34135417 | True | False | 900 | 900 | 0 | 900 |
