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
Corpus digest: 77fc112a2b9089662d20e0c43bb5565c128e8f9319efd827f0c5621fcb5af81c
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: a7c312d85b594c072eff44a9df57efde3f21a0ac
Run ID: 00301629-6db5-4cf1-906a-966cfaf8e68c

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | n/a | 336 | 32 | 272 | 32 |
| applyCommands | codeHeavy | 100000 | n/a | 84 | 8 | 68 | 8 |
| applyCommands | degenerateParagraph | 10000 | 463171791 | 168 | 22 | 130 | 30 |
| applyCommands | degenerateParagraph | 100000 | n/a | 84 | 14 | 62 | 18 |
| applyCommands | heavyLists | 10000 | 31577500 | 126 | 24 | 90 | 30 |
| applyCommands | heavyLists | 100000 | n/a | 42 | 16 | 22 | 18 |
| applyCommands | imageHeavy | 10000 | 687828542 | 168 | 28 | 90 | 34 |
| applyCommands | imageHeavy | 100000 | 30240792 | 126 | 24 | 22 | 26 |
| applyCommands | structuredProse | 10000 | 19586500 | 168 | 28 | 124 | 36 |
| applyCommands | structuredProse | 100000 | 437277125 | 84 | 20 | 22 | 22 |
| applyCommands | tableDense | 10000 | n/a | 126 | 33 | 81 | 39 |
| applyCommands | tableDense | 100000 | n/a | 42 | 9 | 29 | 11 |
| openAndIdle | codeHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 16 | 0 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | heavyLists | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | heavyLists | 100000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | imageHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | imageHeavy | 100000 | 66587459 | 9 | 0 | 0 | 7 |
| openAndIdle | structuredProse | 10000 | n/a | 9 | 0 | 0 | 9 |
| openAndIdle | structuredProse | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | tableDense | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | tableDense | 100000 | n/a | 8 | 0 | 0 | 8 |
| scrollDocument | codeHeavy | 10000 | n/a | 9 | 0 | 0 | 9 |
| scrollDocument | codeHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 16 | 0 | 0 | 16 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 9 | 0 | 0 | 9 |
| scrollDocument | heavyLists | 10000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | heavyLists | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | imageHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | imageHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | structuredProse | 10000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | structuredProse | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | tableDense | 10000 | n/a | 9 | 0 | 0 | 9 |
| scrollDocument | tableDense | 100000 | n/a | 10 | 0 | 0 | 10 |
| soak | codeHeavy | 10000 | 55361333 | 432 | 432 | 0 | 432 |
| soak | codeHeavy | 100000 | n/a | 360 | 360 | 0 | 360 |
| soak | degenerateParagraph | 10000 | 9803000 | 1296 | 1296 | 0 | 1296 |
| soak | degenerateParagraph | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | heavyLists | 10000 | 65384209 | 576 | 576 | 0 | 576 |
| soak | heavyLists | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | imageHeavy | 10000 | 43092583 | 432 | 432 | 0 | 432 |
| soak | imageHeavy | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | structuredProse | 10000 | 43360667 | 576 | 576 | 0 | 576 |
| soak | structuredProse | 100000 | 109764291 | 540 | 540 | 0 | 540 |
| soak | tableDense | 10000 | 61286500 | 576 | 576 | 0 | 576 |
| soak | tableDense | 100000 | n/a | 540 | 540 | 0 | 540 |
| toggleModes | codeHeavy | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | heavyLists | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | heavyLists | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | imageHeavy | 10000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | imageHeavy | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | structuredProse | 10000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | structuredProse | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 10000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 100000 | n/a | 440 | 440 | 0 | 440 |
| typeAdjacentMarkup | codeHeavy | 10000 | 22507542 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 83998792 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 12812833 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | heavyLists | 10000 | 33833958 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | heavyLists | 100000 | 146580042 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | imageHeavy | 10000 | n/a | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | structuredProse | 10000 | 70932625 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | structuredProse | 100000 | 112368417 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | tableDense | 10000 | 61794917 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | codeHeavy | 10000 | 75529667 | 28 | 28 | 0 | 28 |
| typeInTable | codeHeavy | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | degenerateParagraph | 10000 | 3421375 | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 36187500 | 28 | 28 | 0 | 28 |
| typeInTable | heavyLists | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | imageHeavy | 10000 | n/a | 12 | 12 | 0 | 12 |
| typeInTable | imageHeavy | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 59659334 | 24 | 24 | 0 | 24 |
| typeInTable | structuredProse | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 114924625 | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 35769750 | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 126743791 | 200 | 200 | 0 | 200 |
| typeProse | degenerateParagraph | 10000 | 15969000 | 68 | 68 | 0 | 68 |
| typeProse | degenerateParagraph | 100000 | 2788750 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 43392375 | 40 | 40 | 0 | 40 |
| typeProse | heavyLists | 100000 | 154283791 | 200 | 200 | 0 | 200 |
| typeProse | imageHeavy | 10000 | n/a | 20 | 20 | 0 | 20 |
| typeProse | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeProse | structuredProse | 10000 | 88665083 | 32 | 32 | 0 | 32 |
| typeProse | structuredProse | 100000 | 110198667 | 200 | 200 | 0 | 200 |
| typeProse | tableDense | 10000 | 89184708 | 32 | 32 | 0 | 32 |
| typeProse | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| undoRedoStorm | codeHeavy | 10000 | 32821250 | 400 | 400 | 0 | 400 |
| undoRedoStorm | codeHeavy | 100000 | n/a | 200 | 200 | 0 | 200 |
| undoRedoStorm | degenerateParagraph | 10000 | 9879250 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 400 | 400 | 0 | 400 |
| undoRedoStorm | heavyLists | 10000 | 27194666 | 400 | 400 | 0 | 400 |
| undoRedoStorm | heavyLists | 100000 | n/a | 400 | 400 | 0 | 400 |
| undoRedoStorm | imageHeavy | 10000 | 28076792 | 400 | 400 | 0 | 400 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | structuredProse | 10000 | 48624584 | 400 | 400 | 0 | 400 |
| undoRedoStorm | structuredProse | 100000 | 105694333 | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 10000 | 65200708 | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 100000 | n/a | 400 | 400 | 0 | 400 |
