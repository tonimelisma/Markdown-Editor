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
Corpus digest: ac614805e368970d1b03d59dca0a6f331718d82f514808a662d44ae1a95d3988
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 6bb23620fe78668d44f95063221eefae80c41506
Run ID: 0a4974cd-299a-4c62-b59c-0312a725ff95

| scenario | corpus | size | parseProjection p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | n/a | 336 | 32 | 272 | 32 |
| applyCommands | codeHeavy | 100000 | n/a | 42 | 4 | 34 | 4 |
| applyCommands | degenerateParagraph | 10000 | 383349042 | 210 | 26 | 164 | 36 |
| applyCommands | degenerateParagraph | 100000 | n/a | 84 | 14 | 62 | 18 |
| applyCommands | heavyLists | 10000 | 73182291 | 126 | 24 | 90 | 30 |
| applyCommands | heavyLists | 100000 | n/a | 42 | 16 | 22 | 18 |
| applyCommands | imageHeavy | 10000 | 678416292 | 168 | 28 | 90 | 34 |
| applyCommands | imageHeavy | 100000 | 69137458 | 294 | 28 | 0 | 28 |
| applyCommands | structuredProse | 10000 | 43761750 | 168 | 28 | 124 | 36 |
| applyCommands | structuredProse | 100000 | n/a | 42 | 16 | 22 | 18 |
| applyCommands | tableDense | 10000 | n/a | 126 | 33 | 81 | 39 |
| applyCommands | tableDense | 100000 | 519587583 | 84 | 13 | 29 | 15 |
| openAndIdle | codeHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 16 | 0 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | heavyLists | 10000 | n/a | 12 | 0 | 0 | 12 |
| openAndIdle | heavyLists | 100000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | imageHeavy | 10000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | 88357250 | 10 | 0 | 0 | 8 |
| openAndIdle | structuredProse | 10000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | structuredProse | 100000 | n/a | 9 | 0 | 0 | 9 |
| openAndIdle | tableDense | 10000 | n/a | 11 | 0 | 0 | 11 |
| openAndIdle | tableDense | 100000 | n/a | 8 | 0 | 0 | 8 |
| scrollDocument | codeHeavy | 10000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | codeHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 16 | 0 | 0 | 16 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | heavyLists | 10000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | heavyLists | 100000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | imageHeavy | 10000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | imageHeavy | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | structuredProse | 10000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | structuredProse | 100000 | n/a | 10 | 0 | 0 | 10 |
| scrollDocument | tableDense | 10000 | n/a | 11 | 0 | 0 | 11 |
| scrollDocument | tableDense | 100000 | n/a | 11 | 0 | 0 | 11 |
| soak | codeHeavy | 10000 | 45127167 | 432 | 432 | 0 | 432 |
| soak | codeHeavy | 100000 | 65460250 | 540 | 540 | 0 | 540 |
| soak | degenerateParagraph | 10000 | 10782208 | 1296 | 1296 | 0 | 1296 |
| soak | degenerateParagraph | 100000 | n/a | 360 | 360 | 0 | 360 |
| soak | heavyLists | 10000 | 45996708 | 576 | 576 | 0 | 576 |
| soak | heavyLists | 100000 | 122636500 | 540 | 540 | 0 | 540 |
| soak | imageHeavy | 10000 | 26257291 | 576 | 576 | 0 | 576 |
| soak | imageHeavy | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | structuredProse | 10000 | 46379167 | 576 | 576 | 0 | 576 |
| soak | structuredProse | 100000 | n/a | 540 | 540 | 0 | 540 |
| soak | tableDense | 10000 | 82357166 | 576 | 576 | 0 | 576 |
| soak | tableDense | 100000 | n/a | 180 | 180 | 0 | 180 |
| toggleModes | codeHeavy | 10000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | degenerateParagraph | 10000 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | 520 | 520 | 0 | 520 |
| toggleModes | heavyLists | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | heavyLists | 100000 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | imageHeavy | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | imageHeavy | 100000 | 57457542 | 360 | 360 | 0 | 360 |
| toggleModes | structuredProse | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | structuredProse | 100000 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 10000 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | tableDense | 100000 | n/a | 400 | 400 | 0 | 400 |
| typeAdjacentMarkup | codeHeavy | 10000 | 49917125 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 49829792 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 13125041 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | heavyLists | 10000 | 37138833 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | heavyLists | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | imageHeavy | 10000 | n/a | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | structuredProse | 10000 | 42183833 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | structuredProse | 100000 | 113109875 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | tableDense | 10000 | 75904125 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | codeHeavy | 10000 | 69931625 | 32 | 32 | 0 | 32 |
| typeInTable | codeHeavy | 100000 | n/a | 200 | 200 | 0 | 200 |
| typeInTable | degenerateParagraph | 10000 | 22412625 | 52 | 52 | 0 | 52 |
| typeInTable | degenerateParagraph | 100000 | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 44473667 | 32 | 32 | 0 | 32 |
| typeInTable | heavyLists | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeInTable | imageHeavy | 10000 | n/a | 24 | 24 | 0 | 24 |
| typeInTable | imageHeavy | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 18321292 | 28 | 28 | 0 | 28 |
| typeInTable | structuredProse | 100000 | n/a | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 160451417 | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 47514209 | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 62975875 | 320 | 320 | 0 | 320 |
| typeProse | degenerateParagraph | 10000 | 16709042 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 2782042 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 55430458 | 40 | 40 | 0 | 40 |
| typeProse | heavyLists | 100000 | 154797083 | 240 | 240 | 0 | 240 |
| typeProse | imageHeavy | 10000 | n/a | 36 | 36 | 0 | 36 |
| typeProse | imageHeavy | 100000 | n/a | 280 | 280 | 0 | 280 |
| typeProse | structuredProse | 10000 | 140314583 | 40 | 40 | 0 | 40 |
| typeProse | structuredProse | 100000 | 140198625 | 320 | 320 | 0 | 320 |
| typeProse | tableDense | 10000 | 71892666 | 40 | 40 | 0 | 40 |
| typeProse | tableDense | 100000 | n/a | 160 | 160 | 0 | 160 |
| undoRedoStorm | codeHeavy | 10000 | 45233542 | 400 | 400 | 0 | 400 |
| undoRedoStorm | codeHeavy | 100000 | 137135250 | 300 | 300 | 0 | 300 |
| undoRedoStorm | degenerateParagraph | 10000 | 7962792 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | heavyLists | 10000 | 41398250 | 400 | 400 | 0 | 400 |
| undoRedoStorm | heavyLists | 100000 | 150857000 | 300 | 300 | 0 | 300 |
| undoRedoStorm | imageHeavy | 10000 | 38857459 | 300 | 300 | 0 | 300 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 300 | 300 | 0 | 300 |
| undoRedoStorm | structuredProse | 10000 | 46659792 | 400 | 400 | 0 | 400 |
| undoRedoStorm | structuredProse | 100000 | 94209542 | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 10000 | 75141292 | 300 | 300 | 0 | 300 |
| undoRedoStorm | tableDense | 100000 | n/a | 300 | 300 | 0 | 300 |
