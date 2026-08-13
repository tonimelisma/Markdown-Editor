# Performance baseline

- **Authority:** Evidence only
- **First researched:** 2026-08-13
- **Last verified:** 2026-08-13
- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.
Host: Tonis-MacBook-Pro.local
OS: macOS 27.0
OS build: 26A5406e
Architecture: arm64
Configuration: Release
Xcode: Xcode 27.0; Build version 27A5228h
Corpus digest: 1c1ea8a5f6ccf7d1617a8655cf274f94e4661e73ec5b2e77208f89b85984061c
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 5c6ac27e1c16fef54d6c0e0821ef648b17c8b729
Run ID: 597a9673-4093-4819-97be-6739410e2f5a

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 6565041 | 294 | 140 | 7 | 154 |
| applyCommands | codeHeavy | 100000 | 35056375 | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 14948333 | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 12182209 | 210 | 100 | 5 | 110 |
| applyCommands | heavyLists | 10000 | 8147000 | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 17756083 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 10000 | 16485875 | 168 | 80 | 4 | 88 |
| applyCommands | imageHeavy | 100000 | n/a | 210 | 100 | 5 | 110 |
| applyCommands | structuredProse | 10000 | 12878666 | 252 | 120 | 6 | 132 |
| applyCommands | structuredProse | 100000 | 79404250 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 25391916 | 126 | 60 | 3 | 66 |
| applyCommands | tableDense | 100000 | n/a | 42 | 20 | 1 | 22 |
| openAndIdle | codeHeavy | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 100000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 10000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | structuredProse | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | structuredProse | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 100000 | n/a | 7 | 7 | 0 | 7 |
| scrollDocument | codeHeavy | 10000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | codeHeavy | 100000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | heavyLists | 10000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | heavyLists | 100000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 10000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 100000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 10000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | structuredProse | 100000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | tableDense | 10000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 100000 | n/a | 7 | 7 | 0 | 14 |
| soak | codeHeavy | 10000 | 36245042 | 1032 | 1032 | 0 | 1032 |
| soak | codeHeavy | 100000 | 56679167 | 1520 | 1520 | 0 | 1520 |
| soak | degenerateParagraph | 10000 | 11022125 | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | n/a | 1140 | 1140 | 0 | 1140 |
| soak | heavyLists | 10000 | 55252292 | 1376 | 1376 | 0 | 1376 |
| soak | heavyLists | 100000 | n/a | 760 | 760 | 0 | 760 |
| soak | imageHeavy | 10000 | 39530791 | 1376 | 1376 | 0 | 1376 |
| soak | imageHeavy | 100000 | n/a | 760 | 760 | 0 | 760 |
| soak | structuredProse | 10000 | 48548209 | 1376 | 1376 | 0 | 1376 |
| soak | structuredProse | 100000 | n/a | 760 | 760 | 0 | 760 |
| soak | tableDense | 10000 | 57064083 | 1032 | 1032 | 0 | 1032 |
| soak | tableDense | 100000 | n/a | 380 | 380 | 0 | 380 |
| toggleModes | codeHeavy | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | heavyLists | 10000 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | heavyLists | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | imageHeavy | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | imageHeavy | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | structuredProse | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | structuredProse | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | tableDense | 100000 | n/a | 360 | 360 | 0 | 360 |
| typeAdjacentMarkup | codeHeavy | 10000 | 81078000 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 123772958 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 17084250 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | heavyLists | 10000 | 40308041 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | heavyLists | 100000 | 75632000 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | imageHeavy | 10000 | 35549834 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | structuredProse | 10000 | 52108583 | 44 | 44 | 0 | 44 |
| typeAdjacentMarkup | structuredProse | 100000 | 157612333 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | tableDense | 10000 | 59826375 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeInTable | codeHeavy | 10000 | n/a | 16 | 16 | 0 | 16 |
| typeInTable | codeHeavy | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | degenerateParagraph | 10000 | 3519791 | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 116674208 | 32 | 32 | 0 | 32 |
| typeInTable | heavyLists | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | imageHeavy | 10000 | n/a | 24 | 24 | 0 | 24 |
| typeInTable | imageHeavy | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | n/a | 24 | 24 | 0 | 24 |
| typeInTable | structuredProse | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 134955875 | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeProse | codeHeavy | 10000 | 47424625 | 32 | 32 | 0 | 32 |
| typeProse | codeHeavy | 100000 | 186654333 | 200 | 200 | 0 | 200 |
| typeProse | degenerateParagraph | 10000 | 12044625 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 4541250 | 480 | 480 | 0 | 480 |
| typeProse | heavyLists | 10000 | 86360750 | 44 | 44 | 0 | 44 |
| typeProse | heavyLists | 100000 | 159737625 | 240 | 240 | 0 | 240 |
| typeProse | imageHeavy | 10000 | 39429417 | 40 | 40 | 0 | 40 |
| typeProse | imageHeavy | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeProse | structuredProse | 10000 | 79701875 | 28 | 28 | 0 | 28 |
| typeProse | structuredProse | 100000 | 135937750 | 200 | 200 | 0 | 200 |
| typeProse | tableDense | 10000 | 131870667 | 40 | 40 | 0 | 40 |
| typeProse | tableDense | 100000 | n/a | 120 | 120 | 0 | 120 |
| undoRedoStorm | codeHeavy | 10000 | n/a | 600 | 600 | 0 | 600 |
| undoRedoStorm | codeHeavy | 100000 | 70015750 | 600 | 600 | 0 | 600 |
| undoRedoStorm | degenerateParagraph | 10000 | 9774708 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 600 | 600 | 0 | 600 |
| undoRedoStorm | heavyLists | 10000 | 32828959 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | heavyLists | 100000 | n/a | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 10000 | 20562750 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 600 | 600 | 0 | 600 |
| undoRedoStorm | structuredProse | 10000 | 34142125 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | structuredProse | 100000 | n/a | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 10000 | 62539708 | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 100000 | n/a | 300 | 300 | 0 | 300 |
