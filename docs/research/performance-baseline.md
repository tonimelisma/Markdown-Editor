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
Source implementation digest: 7e8892d6bc7dd13a6a943aca0ce5497066f0b21199af388fca48d699c9bca32f
Source implementation authority: PerformanceCorpus.swift, BenchmarkDriver.swift, IncrementalSourceHighlighter.swift, SourceEditor.swift, and PerformanceSampler.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: 41d0d78ece6ac76f1da6c5cf1bad6a37086a6b3b
Run ID: b8655e49-8b90-4465-a850-e72c1293deb9

| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | parse budget exceeded | source budget exceeded | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | --- | --- | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 34578125 | n/a | False | n/a | 336 | 160 | 8 | 176 |
| applyCommands | codeHeavy | 100000 | 46167875 | n/a | False | n/a | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 1775250 | n/a | False | n/a | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 16241833 | n/a | False | n/a | 126 | 60 | 3 | 66 |
| applyCommands | heavyLists | 10000 | 12410417 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 107165084 | n/a | True | n/a | 42 | 20 | 1 | 22 |
| applyCommands | imageHeavy | 10000 | 12938625 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 210 | 100 | 5 | 110 |
| applyCommands | structuredProse | 10000 | 45836750 | n/a | False | n/a | 168 | 80 | 4 | 88 |
| applyCommands | structuredProse | 100000 | 60047416 | n/a | False | n/a | 126 | 60 | 3 | 66 |
| applyCommands | tableDense | 10000 | 20071750 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 14732791 | n/a | False | n/a | 84 | 40 | 2 | 44 |
| openAndIdle | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| openAndIdle | structuredProse | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | structuredProse | 100000 | n/a | n/a | n/a | n/a | 12 | 12 | 0 | 12 |
| openAndIdle | tableDense | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | tableDense | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 9 |
| scrollDocument | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | heavyLists | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | heavyLists | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | structuredProse | 100000 | n/a | n/a | n/a | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | tableDense | 10000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | tableDense | 100000 | n/a | n/a | n/a | n/a | 11 | 11 | 0 | 22 |
| soak | codeHeavy | 10000 | 23081166 | 24063291 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | codeHeavy | 100000 | n/a | 130814333 | n/a | True | 760 | 760 | 0 | 760 |
| soak | degenerateParagraph | 10000 | 5769250 | 1711833 | False | False | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | n/a | 97755791 | n/a | False | 1140 | 1140 | 0 | 1140 |
| soak | heavyLists | 10000 | 29024500 | 54593541 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | heavyLists | 100000 | 98849084 | 366036333 | False | True | 1140 | 1140 | 0 | 1140 |
| soak | imageHeavy | 10000 | 9905708 | 89085333 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | imageHeavy | 100000 | n/a | 335249083 | n/a | True | 760 | 760 | 0 | 760 |
| soak | structuredProse | 10000 | 34046292 | 51344792 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | structuredProse | 100000 | 79739541 | 207441292 | False | True | 1140 | 1140 | 0 | 1140 |
| soak | tableDense | 10000 | 34590625 | 84000625 | False | False | 1032 | 1032 | 0 | 1032 |
| soak | tableDense | 100000 | 132631083 | 684423208 | True | True | 760 | 760 | 0 | 760 |
| toggleModes | codeHeavy | 10000 | n/a | n/a | n/a | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | degenerateParagraph | 10000 | n/a | n/a | n/a | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 400 | 400 | 0 | 400 |
| toggleModes | heavyLists | 10000 | n/a | n/a | n/a | n/a | 440 | 440 | 0 | 440 |
| toggleModes | heavyLists | 100000 | n/a | n/a | n/a | n/a | 400 | 400 | 0 | 400 |
| toggleModes | imageHeavy | 10000 | n/a | n/a | n/a | n/a | 360 | 360 | 0 | 360 |
| toggleModes | imageHeavy | 100000 | n/a | n/a | n/a | n/a | 400 | 400 | 0 | 400 |
| toggleModes | structuredProse | 10000 | n/a | n/a | n/a | n/a | 400 | 400 | 0 | 400 |
| toggleModes | structuredProse | 100000 | n/a | n/a | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | tableDense | 10000 | n/a | n/a | n/a | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 100000 | n/a | n/a | n/a | n/a | 400 | 400 | 0 | 400 |
| typeAdjacentMarkup | codeHeavy | 10000 | 126380042 | 24789416 | True | False | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | codeHeavy | 100000 | 38201333 | 109900291 | False | True | 120 | 120 | 0 | 120 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 13658334 | 2967375 | False | False | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 81505750 | n/a | False | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | heavyLists | 10000 | 36309042 | 137620833 | False | True | 44 | 44 | 0 | 44 |
| typeAdjacentMarkup | heavyLists | 100000 | 97949542 | n/a | False | n/a | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | imageHeavy | 10000 | 21674625 | 69125459 | False | False | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 362043083 | n/a | True | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | structuredProse | 10000 | 28828083 | 32554125 | False | False | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | structuredProse | 100000 | 85512417 | 336258916 | False | True | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | tableDense | 10000 | 33920666 | 74558750 | False | False | 44 | 44 | 0 | 44 |
| typeAdjacentMarkup | tableDense | 100000 | 181399083 | n/a | True | n/a | 320 | 320 | 0 | 320 |
| typeInTable | codeHeavy | 10000 | 71983584 | 117076708 | False | True | 24 | 24 | 0 | 24 |
| typeInTable | codeHeavy | 100000 | n/a | 172358708 | n/a | True | 200 | 200 | 0 | 200 |
| typeInTable | degenerateParagraph | 10000 | 20324792 | 25760417 | False | False | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | n/a | n/a | n/a | n/a | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 84554417 | 100054125 | False | True | 32 | 32 | 0 | 32 |
| typeInTable | heavyLists | 100000 | n/a | 175056834 | n/a | True | 120 | 120 | 0 | 120 |
| typeInTable | imageHeavy | 10000 | n/a | 68640750 | n/a | False | 20 | 20 | 0 | 20 |
| typeInTable | imageHeavy | 100000 | n/a | 231263166 | n/a | True | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 43737208 | 193923292 | False | True | 16 | 16 | 0 | 16 |
| typeInTable | structuredProse | 100000 | n/a | 155942458 | n/a | True | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 103358917 | 86056375 | True | False | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | n/a | 160004917 | n/a | True | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 25142208 | 26732875 | False | False | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 67052083 | 273650125 | False | True | 320 | 320 | 0 | 320 |
| typeProse | degenerateParagraph | 10000 | 8901750 | 3603917 | False | False | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 3049250 | 18092834 | False | False | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 43923625 | 94207292 | False | False | 40 | 40 | 0 | 40 |
| typeProse | heavyLists | 100000 | 106793209 | n/a | True | n/a | 320 | 320 | 0 | 320 |
| typeProse | imageHeavy | 10000 | 5936083 | 901003250 | False | True | 32 | 32 | 0 | 32 |
| typeProse | imageHeavy | 100000 | n/a | 632398250 | n/a | True | 240 | 240 | 0 | 240 |
| typeProse | structuredProse | 10000 | 16636083 | 39030958 | False | False | 36 | 36 | 0 | 36 |
| typeProse | structuredProse | 100000 | 98693334 | 388627625 | False | True | 200 | 200 | 0 | 200 |
| typeProse | tableDense | 10000 | 44418666 | 80979291 | False | False | 40 | 40 | 0 | 40 |
| typeProse | tableDense | 100000 | 132935125 | n/a | True | n/a | 320 | 320 | 0 | 320 |
| undoRedoStorm | codeHeavy | 10000 | 20611375 | 2993166 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | 88359541 | 22574209 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 5237875 | 1097042 | False | False | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 93429625 | n/a | False | 600 | 600 | 0 | 600 |
| undoRedoStorm | heavyLists | 10000 | 26189000 | 4807875 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | heavyLists | 100000 | 92000375 | 25455500 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 10000 | 23255541 | 3262125 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 34207667 | n/a | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 27476666 | 3033541 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 100000 | 72826083 | 15885208 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 10000 | 23311166 | 5198375 | False | False | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 100000 | 112651291 | 35759500 | True | False | 900 | 900 | 0 | 900 |
