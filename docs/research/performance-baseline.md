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
Corpus digest: 7350202147bd8c27b798d1de43b90c6cf198982ff0f44479cad7db41f57cd9ac
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 40e077dfb70e6510e64663ee9b68ba0451ce3c1b
Run ID: 5964ab00-b421-4401-8c42-5fed92918e6f

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 7128709 | 336 | 160 | 8 | 176 |
| applyCommands | codeHeavy | 100000 | 30401584 | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 500834 | 588 | 280 | 14 | 308 |
| applyCommands | degenerateParagraph | 100000 | 8943625 | 168 | 80 | 4 | 88 |
| applyCommands | heavyLists | 10000 | 10291875 | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 28260959 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 10000 | 7919250 | 168 | 80 | 4 | 88 |
| applyCommands | imageHeavy | 100000 | n/a | 168 | 80 | 4 | 88 |
| applyCommands | structuredProse | 10000 | 3669584 | 252 | 120 | 6 | 132 |
| applyCommands | structuredProse | 100000 | 78802625 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 8779667 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | n/a | 42 | 20 | 1 | 22 |
| openAndIdle | codeHeavy | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 17 | 17 | 0 | 17 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 10000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | n/a | 8 | 8 | 0 | 8 |
| openAndIdle | imageHeavy | 100000 | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | structuredProse | 10000 | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | structuredProse | 100000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 10000 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 100000 | n/a | 10 | 10 | 0 | 10 |
| scrollDocument | codeHeavy | 10000 | n/a | 1 | 1 | 0 | 2 |
| scrollDocument | codeHeavy | 100000 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | heavyLists | 10000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | heavyLists | 100000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 10000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 100000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 10000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | structuredProse | 100000 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | tableDense | 10000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 100000 | n/a | 9 | 9 | 0 | 18 |
| soak | codeHeavy | 10000 | 58186583 | 688 | 688 | 0 | 688 |
| soak | codeHeavy | 100000 | 66044083 | 1520 | 1520 | 0 | 1520 |
| soak | degenerateParagraph | 10000 | 10856375 | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | n/a | 1140 | 1140 | 0 | 1140 |
| soak | heavyLists | 10000 | 60147959 | 1032 | 1032 | 0 | 1032 |
| soak | heavyLists | 100000 | n/a | 1520 | 1520 | 0 | 1520 |
| soak | imageHeavy | 10000 | 34425666 | 1376 | 1376 | 0 | 1376 |
| soak | imageHeavy | 100000 | n/a | 1140 | 1140 | 0 | 1140 |
| soak | structuredProse | 10000 | 36889208 | 1376 | 1376 | 0 | 1376 |
| soak | structuredProse | 100000 | 95327000 | 1140 | 1140 | 0 | 1140 |
| soak | tableDense | 10000 | 68222750 | 1376 | 1376 | 0 | 1376 |
| soak | tableDense | 100000 | n/a | 1140 | 1140 | 0 | 1140 |
| toggleModes | codeHeavy | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | heavyLists | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | heavyLists | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | imageHeavy | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | imageHeavy | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | structuredProse | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | structuredProse | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | tableDense | 100000 | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | codeHeavy | 10000 | 45241042 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 68585375 | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 15038250 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | heavyLists | 10000 | 101840542 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | heavyLists | 100000 | 164108417 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | imageHeavy | 10000 | 46009750 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | structuredProse | 10000 | 84282416 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | structuredProse | 100000 | 112587250 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | tableDense | 10000 | 95272833 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | codeHeavy | 10000 | 134913083 | 32 | 32 | 0 | 32 |
| typeInTable | codeHeavy | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | degenerateParagraph | 10000 | 28791458 | 52 | 52 | 0 | 52 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 72477334 | 28 | 28 | 0 | 28 |
| typeInTable | heavyLists | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | imageHeavy | 10000 | 69807333 | 28 | 28 | 0 | 28 |
| typeInTable | imageHeavy | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | structuredProse | 10000 | 129975250 | 32 | 32 | 0 | 32 |
| typeInTable | structuredProse | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 129821084 | 32 | 32 | 0 | 32 |
| typeInTable | tableDense | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeProse | codeHeavy | 10000 | 51804625 | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 71562500 | 280 | 280 | 0 | 280 |
| typeProse | degenerateParagraph | 10000 | 10460667 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 5461875 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 45773541 | 40 | 40 | 0 | 40 |
| typeProse | heavyLists | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeProse | imageHeavy | 10000 | 12308959 | 36 | 36 | 0 | 36 |
| typeProse | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeProse | structuredProse | 10000 | 41072250 | 36 | 36 | 0 | 36 |
| typeProse | structuredProse | 100000 | 124200792 | 200 | 200 | 0 | 200 |
| typeProse | tableDense | 10000 | 68916042 | 36 | 36 | 0 | 36 |
| typeProse | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| undoRedoStorm | codeHeavy | 10000 | 32689750 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | codeHeavy | 100000 | 150668958 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 9965333 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 900 | 900 | 0 | 900 |
| undoRedoStorm | heavyLists | 10000 | 50192625 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | heavyLists | 100000 | 150926875 | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 10000 | 39490375 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 40273625 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | structuredProse | 100000 | n/a | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | tableDense | 10000 | 48400250 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | tableDense | 100000 | n/a | 900 | 900 | 0 | 900 |
