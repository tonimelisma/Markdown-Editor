# Performance baseline

- **Authority:** Evidence only
- **First researched:** 2026-08-21
- **Last verified:** 2026-08-21
- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.
Host: Tonis-MacBook-Pro.local
OS: macOS 27.0
OS build: 26A5416b
Architecture: arm64
Configuration: Release
Xcode: Xcode 27.0; Build version 27A5228h
Corpus digest: bbdeb4d3109c93dda6c58ef34e798a0d1ca2e2d20bd673c36df67c01b59b845c
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Source implementation digest: cbf7635204abbcf97956d305b299632c0bd38b0d821fc16d3a225e11a425ae8b
Source implementation authority: PerformanceCorpus.swift, BenchmarkDriver.swift, IncrementalSourceHighlighter.swift, SourceEditor.swift, and PerformanceSampler.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 3f95efb74b2a944e4f95957c274421631f46f9af
Run ID: 8694f569-6e02-4239-936b-802521a82e1c

| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | parse budget exceeded | source budget exceeded | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 10222125 | n/a | False | n/a | 294 | 140 | 7 | 154 |
| applyCommands | codeHeavy | 100000 | 45160708 | n/a | False | n/a | 294 | 140 | 7 | 154 |
| applyCommands | degenerateParagraph | 10000 | 563041 | n/a | False | n/a | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 16640541 | n/a | False | n/a | 210 | 100 | 5 | 110 |
| applyCommands | heavyLists | 10000 | 5489792 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 20474208 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 10000 | 3394292 | n/a | False | n/a | 168 | 80 | 4 | 88 |
| applyCommands | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 210 | 100 | 5 | 110 |
| applyCommands | structuredProse | 10000 | 5258708 | n/a | False | n/a | 294 | 140 | 7 | 154 |
| applyCommands | structuredProse | 100000 | 48196125 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 17526791 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 17120458 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| openAndIdle | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 8 | 8 | 0 | 8 |
| openAndIdle | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | structuredProse | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | structuredProse | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | tableDense | 10000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | tableDense | 100000 | n/a | n/a | n/a | n/a | 8 | 8 | 0 | 8 |
| scrollDocument | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | heavyLists | 10000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | heavyLists | 100000 | n/a | n/a | n/a | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| soak | codeHeavy | 10000 | 19904958 | 23898834 | False | False | 1376 | 1376 | 0 | 1376 |
| soak | codeHeavy | 100000 | 67542542 | 206384375 | False | True | 1140 | 1140 | 0 | 1140 |
| soak | degenerateParagraph | 10000 | 7188375 | 1748250 | False | False | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | n/a | 56937792 | n/a | False | 1140 | 1140 | 0 | 1140 |
| soak | heavyLists | 10000 | 43736375 | 67140500 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | heavyLists | 100000 | 194962667 | 567534708 | True | True | 1140 | 1140 | 0 | 1140 |
| soak | imageHeavy | 10000 | 20202500 | 93697584 | False | False | 1376 | 1376 | 0 | 1376 |
| soak | imageHeavy | 100000 | n/a | 550302625 | n/a | True | 760 | 760 | 0 | 760 |
| soak | structuredProse | 10000 | 48294000 | 81982750 | False | False | 1376 | 1376 | 0 | 1376 |
| soak | structuredProse | 100000 | 68594833 | 270299500 | False | True | 1520 | 1520 | 0 | 1520 |
| soak | tableDense | 10000 | 35781625 | 82239250 | False | False | 1376 | 1376 | 0 | 1376 |
| soak | tableDense | 100000 | 197264458 | 567862958 | True | True | 1140 | 1140 | 0 | 1140 |
| toggleModes | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 440 | 440 | 0 | 440 |
| toggleModes | heavyLists | 10000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | heavyLists | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | structuredProse | 10000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | structuredProse | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | tableDense | 10000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | tableDense | 100000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| typeAdjacentMarkup | codeHeavy | 10000 | 84937833 | 21773542 | False | False | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | codeHeavy | 100000 | 49643500 | 157550750 | False | True | 80 | 80 | 0 | 80 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 13985625 | 2859292 | False | False | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 154980917 | n/a | True | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | heavyLists | 10000 | 35492041 | 49962208 | False | False | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | heavyLists | 100000 | 125625625 | n/a | True | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | imageHeavy | 10000 | 19608417 | 88786125 | False | False | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | structuredProse | 10000 | 17812208 | 18374875 | False | False | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | structuredProse | 100000 | 110355583 | 340749541 | True | True | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | tableDense | 10000 | 15330625 | 44908917 | False | False | 28 | 28 | 0 | 28 |
| typeAdjacentMarkup | tableDense | 100000 | 97468958 | 447142583 | False | True | 240 | 240 | 0 | 240 |
| typeInTable | codeHeavy | 10000 | 4636125 | 146805750 | False | True | 24 | 24 | 0 | 24 |
| typeInTable | codeHeavy | 100000 | n/a | 205283500 | n/a | True | 120 | 120 | 0 | 120 |
| typeInTable | degenerateParagraph | 10000 | 3566042 | 27977500 | False | False | 60 | 60 | 0 | 60 |
| typeInTable | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 62117208 | 125453208 | False | True | 28 | 28 | 0 | 28 |
| typeInTable | heavyLists | 100000 | n/a | 70179542 | n/a | False | 80 | 80 | 0 | 80 |
| typeInTable | imageHeavy | 10000 | n/a | 98793792 | n/a | False | 28 | 28 | 0 | 28 |
| typeInTable | imageHeavy | 100000 | n/a | 324584625 | n/a | True | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | n/a | 197606084 | n/a | True | 32 | 32 | 0 | 32 |
| typeInTable | structuredProse | 100000 | n/a | 98441084 | n/a | False | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 126180125 | 114055667 | True | True | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | 513532833 | n/a | True | 120 | 120 | 0 | 120 |
| typeProse | codeHeavy | 10000 | 13208959 | 23128291 | False | False | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 47786209 | 198094666 | False | True | 320 | 320 | 0 | 320 |
| typeProse | degenerateParagraph | 10000 | 9282333 | 2946833 | False | False | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 4470459 | 18257750 | False | False | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 94863750 | 112140458 | False | True | 36 | 36 | 0 | 36 |
| typeProse | heavyLists | 100000 | 141417000 | n/a | True | n/a | 280 | 280 | 0 | 280 |
| typeProse | imageHeavy | 10000 | 13869458 | 46436792 | False | False | 28 | 28 | 0 | 28 |
| typeProse | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 160 | 160 | 0 | 160 |
| typeProse | structuredProse | 10000 | 21466458 | 28428250 | False | False | 36 | 36 | 0 | 36 |
| typeProse | structuredProse | 100000 | 164146375 | 321018167 | True | True | 240 | 240 | 0 | 240 |
| typeProse | tableDense | 10000 | 39995958 | 60809667 | False | False | 28 | 28 | 0 | 28 |
| typeProse | tableDense | 100000 | 180187875 | n/a | True | n/a | 200 | 200 | 0 | 200 |
| undoRedoStorm | codeHeavy | 10000 | 13323958 | 4389583 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | 18551042 | 33531750 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 5309417 | 1057000 | False | False | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 49253250 | n/a | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | heavyLists | 10000 | 22122416 | 1619792 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | heavyLists | 100000 | 99986458 | 41060250 | False | False | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | imageHeavy | 10000 | 80085959 | 1398041 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 31458667 | n/a | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 26226750 | 1980042 | False | False | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | structuredProse | 100000 | 85599333 | 12146000 | False | False | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | tableDense | 10000 | 26138250 | 1637833 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 100000 | 197277333 | 56756208 | True | False | 900 | 900 | 0 | 900 |
