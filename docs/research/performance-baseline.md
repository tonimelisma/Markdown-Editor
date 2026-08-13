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
Corpus digest: 3b68f6094c6a028a5f2b8897ed804f2c31deb92ea8de86b0769e95fc0f551524
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: ce6c8791f4abd2e37536a425eb3c2ecaf79cb885
Run ID: 72a42415-338e-4949-9d24-11c3cc27aa52

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | n/a | 294 | 28 | 238 | 28 |
| applyCommands | codeHeavy | 100000 | n/a | 126 | 12 | 102 | 12 |
| applyCommands | degenerateParagraph | 10000 | 476448125 | 168 | 22 | 130 | 30 |
| applyCommands | degenerateParagraph | 100000 | n/a | 84 | 14 | 62 | 18 |
| applyCommands | heavyLists | 10000 | 32964084 | 126 | 24 | 90 | 30 |
| applyCommands | heavyLists | 100000 | n/a | 42 | 16 | 22 | 18 |
| applyCommands | imageHeavy | 10000 | 4581167 | 294 | 40 | 56 | 44 |
| applyCommands | imageHeavy | 100000 | 61966583 | 252 | 36 | 22 | 38 |
| applyCommands | structuredProse | 10000 | 20662791 | 168 | 28 | 124 | 36 |
| applyCommands | structuredProse | 100000 | n/a | 42 | 16 | 22 | 18 |
| applyCommands | tableDense | 10000 | n/a | 84 | 21 | 55 | 25 |
| applyCommands | tableDense | 100000 | 151014084 | 84 | 13 | 29 | 15 |
| openAndIdle | codeHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 16 | 0 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | heavyLists | 10000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | heavyLists | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | 47355666 | 9 | 0 | 0 | 7 |
| openAndIdle | structuredProse | 10000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | structuredProse | 100000 | n/a | 9 | 0 | 0 | 9 |
| openAndIdle | tableDense | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | tableDense | 100000 | 436008500 | 9 | 0 | 0 | 8 |
| scrollDocument | codeHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | codeHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 16 | 0 | 0 | 16 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | heavyLists | 10000 | n/a | 9 | 0 | 0 | 9 |
| scrollDocument | heavyLists | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | imageHeavy | 10000 | n/a | 9 | 0 | 0 | 9 |
| scrollDocument | imageHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | structuredProse | 10000 | n/a | 9 | 0 | 0 | 9 |
| scrollDocument | structuredProse | 100000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | tableDense | 10000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | tableDense | 100000 | 1485585291 | 7 | 0 | 0 | 7 |
| soak | codeHeavy | 10000 | 60148916 | 576 | 576 | 0 | 576 |
| soak | codeHeavy | 100000 | 55856458 | 720 | 720 | 0 | 720 |
| soak | degenerateParagraph | 10000 | 11009208 | 1296 | 1296 | 0 | 1296 |
| soak | degenerateParagraph | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | heavyLists | 10000 | 57697417 | 576 | 576 | 0 | 576 |
| soak | heavyLists | 100000 | n/a | 360 | 360 | 0 | 360 |
| soak | imageHeavy | 10000 | 28939250 | 576 | 576 | 0 | 576 |
| soak | imageHeavy | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | structuredProse | 10000 | 41471583 | 576 | 576 | 0 | 576 |
| soak | structuredProse | 100000 | 97883417 | 540 | 540 | 0 | 540 |
| soak | tableDense | 10000 | n/a | 288 | 288 | 0 | 288 |
| soak | tableDense | 100000 | n/a | 540 | 540 | 0 | 540 |
| toggleModes | codeHeavy | 10000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | codeHeavy | 100000 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 520 | 520 | 0 | 520 |
| toggleModes | heavyLists | 10000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | heavyLists | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | imageHeavy | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | imageHeavy | 100000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | structuredProse | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | structuredProse | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | tableDense | 100000 | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | codeHeavy | 10000 | 35443416 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | codeHeavy | 100000 | 89072958 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 12102334 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | heavyLists | 10000 | 141521250 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | heavyLists | 100000 | 64513125 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | imageHeavy | 10000 | n/a | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | structuredProse | 10000 | 44759792 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | structuredProse | 100000 | 140050459 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | tableDense | 10000 | 113892291 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeInTable | codeHeavy | 10000 | 105141833 | 28 | 28 | 0 | 28 |
| typeInTable | codeHeavy | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | degenerateParagraph | 10000 | 3495208 | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 54555042 | 32 | 32 | 0 | 32 |
| typeInTable | heavyLists | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | imageHeavy | 10000 | n/a | 24 | 24 | 0 | 24 |
| typeInTable | imageHeavy | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 65069500 | 28 | 28 | 0 | 28 |
| typeInTable | structuredProse | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 68147917 | 24 | 24 | 0 | 24 |
| typeInTable | tableDense | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeProse | codeHeavy | 10000 | 65044250 | 40 | 40 | 0 | 40 |
| typeProse | codeHeavy | 100000 | 70258083 | 280 | 280 | 0 | 280 |
| typeProse | degenerateParagraph | 10000 | 11485583 | 68 | 68 | 0 | 68 |
| typeProse | degenerateParagraph | 100000 | 2923167 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 62142709 | 40 | 40 | 0 | 40 |
| typeProse | heavyLists | 100000 | 158487750 | 240 | 240 | 0 | 240 |
| typeProse | imageHeavy | 10000 | n/a | 32 | 32 | 0 | 32 |
| typeProse | imageHeavy | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeProse | structuredProse | 10000 | 43503750 | 32 | 32 | 0 | 32 |
| typeProse | structuredProse | 100000 | 145727500 | 280 | 280 | 0 | 280 |
| typeProse | tableDense | 10000 | 64197708 | 36 | 36 | 0 | 36 |
| typeProse | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| undoRedoStorm | codeHeavy | 10000 | 40001500 | 300 | 300 | 0 | 300 |
| undoRedoStorm | codeHeavy | 100000 | 77580084 | 300 | 300 | 0 | 300 |
| undoRedoStorm | degenerateParagraph | 10000 | 8259458 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | heavyLists | 10000 | 44470916 | 400 | 400 | 0 | 400 |
| undoRedoStorm | heavyLists | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | imageHeavy | 10000 | 32096875 | 300 | 300 | 0 | 300 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 400 | 400 | 0 | 400 |
| undoRedoStorm | structuredProse | 10000 | 56600583 | 400 | 400 | 0 | 400 |
| undoRedoStorm | structuredProse | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 10000 | 91695958 | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 100000 | n/a | 300 | 300 | 0 | 300 |
