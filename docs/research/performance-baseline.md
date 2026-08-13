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
Corpus digest: 9f9688169908b76dceb3ccf40eed516da1c9de86c9da4f14404b9d4b13037866
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 77b610603cd291b6860fadc6d3653b0f524ab267
Run ID: 93788238-7412-43c8-a874-188c3c05781e

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | n/a | 294 | 28 | 238 | 28 |
| applyCommands | codeHeavy | 100000 | n/a | 126 | 12 | 102 | 12 |
| applyCommands | degenerateParagraph | 10000 | 417686458 | 210 | 26 | 164 | 36 |
| applyCommands | degenerateParagraph | 100000 | 472793208 | 126 | 18 | 96 | 24 |
| applyCommands | heavyLists | 10000 | 31305667 | 126 | 24 | 90 | 30 |
| applyCommands | heavyLists | 100000 | 426452000 | 84 | 20 | 22 | 22 |
| applyCommands | imageHeavy | 10000 | 686435625 | 168 | 28 | 90 | 34 |
| applyCommands | imageHeavy | 100000 | 38813458 | 252 | 36 | 22 | 38 |
| applyCommands | structuredProse | 10000 | 18530958 | 168 | 28 | 124 | 36 |
| applyCommands | structuredProse | 100000 | n/a | 42 | 16 | 22 | 18 |
| applyCommands | tableDense | 10000 | n/a | 126 | 33 | 81 | 39 |
| applyCommands | tableDense | 100000 | 180500958 | 84 | 13 | 29 | 15 |
| openAndIdle | codeHeavy | 10000 | n/a | 0 | 0 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 0 | 0 | 0 | 11 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 0 | 0 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 0 | 0 | 0 | 11 |
| openAndIdle | heavyLists | 10000 | n/a | 0 | 0 | 0 | 10 |
| openAndIdle | heavyLists | 100000 | n/a | 0 | 0 | 0 | 9 |
| openAndIdle | imageHeavy | 10000 | n/a | 0 | 0 | 0 | 9 |
| openAndIdle | imageHeavy | 100000 | 74032500 | 0 | 0 | 0 | 8 |
| openAndIdle | structuredProse | 10000 | n/a | 0 | 0 | 0 | 10 |
| openAndIdle | structuredProse | 100000 | n/a | 0 | 0 | 0 | 10 |
| openAndIdle | tableDense | 10000 | n/a | 0 | 0 | 0 | 11 |
| openAndIdle | tableDense | 100000 | 305241709 | 0 | 0 | 0 | 9 |
| scrollDocument | codeHeavy | 10000 | n/a | 0 | 0 | 0 | 10 |
| scrollDocument | codeHeavy | 100000 | n/a | 0 | 0 | 0 | 10 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 0 | 0 | 0 | 16 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 0 | 0 | 0 | 11 |
| scrollDocument | heavyLists | 10000 | n/a | 0 | 0 | 0 | 10 |
| scrollDocument | heavyLists | 100000 | n/a | 0 | 0 | 0 | 10 |
| scrollDocument | imageHeavy | 10000 | n/a | 0 | 0 | 0 | 9 |
| scrollDocument | imageHeavy | 100000 | 49700416 | 0 | 0 | 0 | 8 |
| scrollDocument | structuredProse | 10000 | n/a | 0 | 0 | 0 | 10 |
| scrollDocument | structuredProse | 100000 | n/a | 0 | 0 | 0 | 11 |
| scrollDocument | tableDense | 10000 | n/a | 0 | 0 | 0 | 11 |
| scrollDocument | tableDense | 100000 | n/a | 0 | 0 | 0 | 11 |
| soak | codeHeavy | 10000 | 72403667 | 576 | 576 | 0 | 576 |
| soak | codeHeavy | 100000 | 80463667 | 540 | 540 | 0 | 540 |
| soak | degenerateParagraph | 10000 | 15731833 | 1296 | 1296 | 0 | 1296 |
| soak | degenerateParagraph | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | heavyLists | 10000 | 85644750 | 576 | 576 | 0 | 576 |
| soak | heavyLists | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | imageHeavy | 10000 | 56920083 | 576 | 576 | 0 | 576 |
| soak | imageHeavy | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | structuredProse | 10000 | 88928250 | 432 | 432 | 0 | 432 |
| soak | structuredProse | 100000 | 112323958 | 360 | 360 | 0 | 360 |
| soak | tableDense | 10000 | 96563291 | 576 | 576 | 0 | 576 |
| soak | tableDense | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | codeHeavy | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | heavyLists | 10000 | n/a | 520 | 520 | 0 | 520 |
| toggleModes | heavyLists | 100000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | imageHeavy | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | imageHeavy | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | structuredProse | 10000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | structuredProse | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 10000 | n/a | 520 | 520 | 0 | 520 |
| toggleModes | tableDense | 100000 | n/a | 600 | 600 | 0 | 600 |
| typeAdjacentMarkup | codeHeavy | 10000 | 37131958 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 84399041 | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 12988459 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | heavyLists | 10000 | 42242875 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | heavyLists | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | imageHeavy | 10000 | n/a | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | structuredProse | 10000 | 50007292 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | structuredProse | 100000 | 124014833 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | tableDense | 10000 | 59109875 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeInTable | codeHeavy | 10000 | 53222834 | 28 | 28 | 0 | 28 |
| typeInTable | codeHeavy | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | degenerateParagraph | 10000 | 3653750 | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 41783125 | 32 | 32 | 0 | 32 |
| typeInTable | heavyLists | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | imageHeavy | 10000 | n/a | 20 | 20 | 0 | 20 |
| typeInTable | imageHeavy | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 60862750 | 32 | 32 | 0 | 32 |
| typeInTable | structuredProse | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 79914834 | 32 | 32 | 0 | 32 |
| typeInTable | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 42361125 | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 77528083 | 320 | 320 | 0 | 320 |
| typeProse | degenerateParagraph | 10000 | 13663583 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 3926333 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 97944000 | 40 | 40 | 0 | 40 |
| typeProse | heavyLists | 100000 | 99414750 | 240 | 240 | 0 | 240 |
| typeProse | imageHeavy | 10000 | n/a | 32 | 32 | 0 | 32 |
| typeProse | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeProse | structuredProse | 10000 | 57595584 | 32 | 32 | 0 | 32 |
| typeProse | structuredProse | 100000 | 115741958 | 240 | 240 | 0 | 240 |
| typeProse | tableDense | 10000 | 71689417 | 36 | 36 | 0 | 36 |
| typeProse | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| undoRedoStorm | codeHeavy | 10000 | 80985500 | 400 | 400 | 0 | 400 |
| undoRedoStorm | codeHeavy | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | degenerateParagraph | 10000 | 13395875 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | heavyLists | 10000 | 127222916 | 400 | 400 | 0 | 400 |
| undoRedoStorm | heavyLists | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | imageHeavy | 10000 | 59349625 | 400 | 400 | 0 | 400 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | structuredProse | 10000 | 63151208 | 400 | 400 | 0 | 400 |
| undoRedoStorm | structuredProse | 100000 | 128523542 | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 10000 | 91626375 | 400 | 400 | 0 | 400 |
| undoRedoStorm | tableDense | 100000 | n/a | 300 | 300 | 0 | 300 |
