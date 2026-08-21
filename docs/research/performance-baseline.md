# Performance baseline

- **Authority:** Evidence only
- **First researched:** 2026-08-13
- **Last verified:** 2026-08-20
- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.
Host: Tonis-MacBook-Pro.local
OS: macOS 27.0
OS build: 26A5406e
Architecture: arm64
Configuration: Release
Xcode: Xcode 27.0; Build version 27A5228h
Corpus digest: ef3427c5680dda16896c7980751583a2e237da12ba6f67222dae5f9f84fca048
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: 124.49152
Commit: 22ade2d7fb7ac5a7bebc4e079a7259c5013969d4
Run ID: 6a48a74e-f431-4cb8-8889-5b34c36889cd

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 10224917 | 294 | 140 | 7 | 154 |
| applyCommands | codeHeavy | 100000 | 46712542 | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 541875 | 588 | 280 | 14 | 308 |
| applyCommands | degenerateParagraph | 100000 | 4761708 | 588 | 280 | 14 | 308 |
| applyCommands | heavyLists | 10000 | 2149542 | 294 | 140 | 7 | 154 |
| applyCommands | heavyLists | 100000 | 17944584 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 10000 | 18237875 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 100000 | 13478167 | 84 | 40 | 2 | 44 |
| applyCommands | structuredProse | 10000 | 1068500 | 630 | 300 | 15 | 330 |
| applyCommands | structuredProse | 100000 | 8481459 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 31381750 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 119798167 | 42 | 20 | 1 | 22 |
| openAndIdle | codeHeavy | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 17 | 17 | 0 | 17 |
| openAndIdle | heavyLists | 10000 | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | heavyLists | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | n/a | 8 | 8 | 0 | 8 |
| openAndIdle | structuredProse | 10000 | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | structuredProse | 100000 | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | tableDense | 10000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | tableDense | 100000 | n/a | 9 | 9 | 0 | 9 |
| scrollDocument | codeHeavy | 10000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | codeHeavy | 100000 | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | heavyLists | 10000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | heavyLists | 100000 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | imageHeavy | 10000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 100000 | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | structuredProse | 10000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | structuredProse | 100000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | tableDense | 10000 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | tableDense | 100000 | n/a | 8 | 8 | 0 | 16 |
| soak | codeHeavy | 10000 | 47767625 | 1032 | 1032 | 0 | 1032 |
| soak | codeHeavy | 100000 | n/a | 1140 | 1140 | 0 | 1140 |
| soak | degenerateParagraph | 10000 | 11342000 | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | 5349084 | 3040 | 3040 | 0 | 3040 |
| soak | heavyLists | 10000 | 12561250 | 3096 | 3096 | 0 | 3096 |
| soak | heavyLists | 100000 | 137316500 | 1140 | 1140 | 0 | 1140 |
| soak | imageHeavy | 10000 | 28095250 | 1032 | 1032 | 0 | 1032 |
| soak | imageHeavy | 100000 | n/a | 1140 | 1140 | 0 | 1140 |
| soak | structuredProse | 10000 | 9746709 | 3096 | 3096 | 0 | 3096 |
| soak | structuredProse | 100000 | 13433042 | 3420 | 3420 | 0 | 3420 |
| soak | tableDense | 10000 | n/a | 688 | 688 | 0 | 688 |
| soak | tableDense | 100000 | n/a | 380 | 380 | 0 | 380 |
| toggleModes | codeHeavy | 10000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | codeHeavy | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | heavyLists | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | heavyLists | 100000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | imageHeavy | 10000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | imageHeavy | 100000 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | structuredProse | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | structuredProse | 100000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | tableDense | 10000 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | tableDense | 100000 | n/a | 400 | 400 | 0 | 400 |
| typeAdjacentMarkup | codeHeavy | 10000 | 51767625 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | codeHeavy | 100000 | 26908583 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 12522291 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | 4006209 | 520 | 520 | 0 | 520 |
| typeAdjacentMarkup | heavyLists | 10000 | 11000792 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | heavyLists | 100000 | 25482709 | 640 | 640 | 0 | 640 |
| typeAdjacentMarkup | imageHeavy | 10000 | 24424000 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | structuredProse | 10000 | 15387916 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | structuredProse | 100000 | 13617709 | 640 | 640 | 0 | 640 |
| typeAdjacentMarkup | tableDense | 10000 | 113069416 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | codeHeavy | 10000 | n/a | 24 | 24 | 0 | 24 |
| typeInTable | codeHeavy | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeInTable | degenerateParagraph | 10000 | 3793959 | 52 | 52 | 0 | 52 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 48496500 | 56 | 56 | 0 | 56 |
| typeInTable | heavyLists | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeInTable | imageHeavy | 10000 | n/a | 12 | 12 | 0 | 12 |
| typeInTable | imageHeavy | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 34622125 | 48 | 48 | 0 | 48 |
| typeInTable | structuredProse | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeInTable | tableDense | 10000 | 144547417 | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | 80 | 80 | 0 | 80 |
| typeProse | codeHeavy | 10000 | 104837542 | 32 | 32 | 0 | 32 |
| typeProse | codeHeavy | 100000 | 38934417 | 240 | 240 | 0 | 240 |
| typeProse | degenerateParagraph | 10000 | 14511333 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 5616375 | 480 | 480 | 0 | 480 |
| typeProse | heavyLists | 10000 | 13147041 | 64 | 64 | 0 | 64 |
| typeProse | heavyLists | 100000 | 83136917 | 640 | 640 | 0 | 640 |
| typeProse | imageHeavy | 10000 | 73607875 | 32 | 32 | 0 | 32 |
| typeProse | imageHeavy | 100000 | n/a | 360 | 360 | 0 | 360 |
| typeProse | structuredProse | 10000 | 13948875 | 64 | 64 | 0 | 64 |
| typeProse | structuredProse | 100000 | 16141167 | 640 | 640 | 0 | 640 |
| typeProse | tableDense | 10000 | 121313958 | 40 | 40 | 0 | 40 |
| typeProse | tableDense | 100000 | n/a | 80 | 80 | 0 | 80 |
| undoRedoStorm | codeHeavy | 10000 | 64826375 | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | degenerateParagraph | 10000 | 10363875 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | 5224667 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | heavyLists | 10000 | 8035167 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | heavyLists | 100000 | 86777541 | 600 | 600 | 0 | 600 |
| undoRedoStorm | imageHeavy | 10000 | n/a | 600 | 600 | 0 | 600 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 9263125 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | structuredProse | 100000 | 16284167 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | tableDense | 10000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 100000 | n/a | 600 | 600 | 0 | 600 |
