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
Corpus digest: bea047d9944c52e5cecd2a2ee24e44a1444103036483b48027bd7a3e31d7e715
Corpus/action authority: PerformanceCorpus.swift and BenchmarkDriver.swift
Method: Scripts/benchmark.sh builds the Release binary, passes a parameter-only manifest, and verifies the exact Swift-owned 6 x 2 x 9 matrix plus per-case action contracts.
Warmup: 1.5 s per case
Duration: 2 s per case
Interval: 120 ms
Samples: 108 case results
Frame hitch ms/s: n/a
Commit: bb1fca8cbae6441cdca74de9c82f72a98554828a
Run ID: cfb0134c-15fd-484b-9a10-dba9082c0a5d

| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 17242458 | 14404916 | 336 | 160 | 8 | 176 |
| applyCommands | codeHeavy | 100000 | 835709375 | 173557375 | 294 | 140 | 7 | 154 |
| applyCommands | degenerateParagraph | 10000 | 558417 | 6194833 | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 214911625 | 49250125 | 252 | 120 | 6 | 132 |
| applyCommands | heavyLists | 10000 | 63779750 | 115625458 | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 122895542 | 29549750 | 42 | 20 | 1 | 22 |
| applyCommands | imageHeavy | 10000 | 13578708 | 66203833 | 126 | 60 | 3 | 66 |
| applyCommands | imageHeavy | 100000 | 103552917 | 23886083 | 84 | 40 | 2 | 44 |
| applyCommands | structuredProse | 10000 | 4485958 | n/a | 252 | 120 | 6 | 132 |
| applyCommands | structuredProse | 100000 | 144546042 | 374804750 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 42946625 | 53819500 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 148949875 | 30807500 | 84 | 40 | 2 | 44 |
| openAndIdle | codeHeavy | 10000 | 12533083 | 19136792 | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | 46249750 | 45591667 | 9 | 9 | 0 | 9 |
| openAndIdle | degenerateParagraph | 10000 | 6132375 | 2835000 | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | 247442542 | 40168834 | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 10000 | 19710875 | 10363917 | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 100000 | 99308250 | 65114667 | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | 7845834 | 4319417 | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | 42565792 | n/a | 10 | 10 | 0 | 10 |
| openAndIdle | structuredProse | 10000 | 5339459 | 25995500 | 11 | 11 | 0 | 11 |
| openAndIdle | structuredProse | 100000 | 68353250 | 20988459 | 11 | 11 | 0 | 11 |
| openAndIdle | tableDense | 10000 | 14698375 | 10539292 | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 100000 | 166598125 | 26222875 | 11 | 11 | 0 | 11 |
| scrollDocument | codeHeavy | 10000 | 9012875 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | codeHeavy | 100000 | 14379583 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | degenerateParagraph | 10000 | 641916 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | 11691459 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | heavyLists | 10000 | 9753250 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | heavyLists | 100000 | 495946458 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 10000 | n/a | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 100000 | 21611875 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | structuredProse | 10000 | 5497333 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | structuredProse | 100000 | 38806042 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 10000 | 16600167 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 100000 | 103646667 | n/a | 10 | 10 | 0 | 20 |
| soak | codeHeavy | 10000 | 12767084 | 45247000 | 1032 | 1032 | 0 | 1032 |
| soak | codeHeavy | 100000 | 44357625 | 1092589833 | 1140 | 1140 | 0 | 1140 |
| soak | degenerateParagraph | 10000 | 642959 | 6263833 | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | 6739708 | 842992667 | 1140 | 1140 | 0 | 1140 |
| soak | heavyLists | 10000 | 48171417 | 76324583 | 1376 | 1376 | 0 | 1376 |
| soak | heavyLists | 100000 | 65393333 | 1395348333 | 1140 | 1140 | 0 | 1140 |
| soak | imageHeavy | 10000 | 17297084 | 59502917 | 1032 | 1032 | 0 | 1032 |
| soak | imageHeavy | 100000 | 33728250 | 1887226750 | 760 | 760 | 0 | 760 |
| soak | structuredProse | 10000 | 16032834 | 74995791 | 1032 | 1032 | 0 | 1032 |
| soak | structuredProse | 100000 | 114644584 | 1157780125 | 760 | 760 | 0 | 760 |
| soak | tableDense | 10000 | 30718666 | 70824584 | 1032 | 1032 | 0 | 1032 |
| soak | tableDense | 100000 | 75745750 | 1649511542 | 1140 | 1140 | 0 | 1140 |
| toggleModes | codeHeavy | 10000 | 2190583 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | codeHeavy | 100000 | 46239417 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | degenerateParagraph | 10000 | 449333 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | 16725375 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | heavyLists | 10000 | 30620792 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | heavyLists | 100000 | 130380542 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | imageHeavy | 10000 | 48270125 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | imageHeavy | 100000 | 60885583 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | structuredProse | 10000 | 10223917 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | structuredProse | 100000 | 52723125 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 10000 | 9944333 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 100000 | 138714458 | n/a | 360 | 360 | 0 | 360 |
| typeAdjacentMarkup | codeHeavy | 10000 | 69857458 | 52442875 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 43323916 | 154930291 | 120 | 120 | 0 | 120 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 13114416 | 4882542 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | 1947833 | 343339750 | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | heavyLists | 10000 | 51829125 | 329633500 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | heavyLists | 100000 | 122807541 | 23463250 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | imageHeavy | 10000 | 18355542 | 303751208 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | imageHeavy | 100000 | 30566125 | 37456042 | 120 | 120 | 0 | 120 |
| typeAdjacentMarkup | structuredProse | 10000 | 21516041 | 27637625 | 44 | 44 | 0 | 44 |
| typeAdjacentMarkup | structuredProse | 100000 | 118310125 | 936213417 | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | tableDense | 10000 | 58458958 | 611225417 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | tableDense | 100000 | 148236083 | 1055871000 | 280 | 280 | 0 | 280 |
| typeInTable | codeHeavy | 10000 | 96906333 | 217611250 | 28 | 28 | 0 | 28 |
| typeInTable | codeHeavy | 100000 | 62476750 | 362895625 | 160 | 160 | 0 | 160 |
| typeInTable | degenerateParagraph | 10000 | 6642334 | 148704083 | 56 | 56 | 0 | 56 |
| typeInTable | degenerateParagraph | 100000 | 1656917 | 8966125 | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 45180292 | 360836750 | 24 | 24 | 0 | 24 |
| typeInTable | heavyLists | 100000 | 104620000 | 993173416 | 120 | 120 | 0 | 120 |
| typeInTable | imageHeavy | 10000 | 51939917 | 254898000 | 24 | 24 | 0 | 24 |
| typeInTable | imageHeavy | 100000 | 104590125 | 699957459 | 80 | 80 | 0 | 80 |
| typeInTable | structuredProse | 10000 | 113740958 | 309635542 | 32 | 32 | 0 | 32 |
| typeInTable | structuredProse | 100000 | 107499500 | 503022375 | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 136194000 | 171549375 | 28 | 28 | 0 | 28 |
| typeInTable | tableDense | 100000 | 169353583 | 541023166 | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 19842959 | 84576500 | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 49970333 | 529296667 | 280 | 280 | 0 | 280 |
| typeProse | degenerateParagraph | 10000 | 10423084 | 4812125 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 4459708 | 24835542 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 20491667 | 63694208 | 36 | 36 | 0 | 36 |
| typeProse | heavyLists | 100000 | n/a | 13597042 | 200 | 200 | 0 | 200 |
| typeProse | imageHeavy | 10000 | 26208417 | 84393250 | 36 | 36 | 0 | 36 |
| typeProse | imageHeavy | 100000 | n/a | 634139458 | 160 | 160 | 0 | 160 |
| typeProse | structuredProse | 10000 | 25668209 | 98951917 | 40 | 40 | 0 | 40 |
| typeProse | structuredProse | 100000 | 118335291 | 389717166 | 280 | 280 | 0 | 280 |
| typeProse | tableDense | 10000 | 40511917 | 90017208 | 44 | 44 | 0 | 44 |
| typeProse | tableDense | 100000 | 157518208 | 21297709 | 280 | 280 | 0 | 280 |
| undoRedoStorm | codeHeavy | 10000 | 15873583 | 68436500 | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | 39921875 | 44718750 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 5237291 | 2356958 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | 9252583 | 1183733500 | 600 | 600 | 0 | 600 |
| undoRedoStorm | heavyLists | 10000 | 22041417 | 76069833 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | heavyLists | 100000 | 92339584 | 77969166 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | imageHeavy | 10000 | 11586125 | 16796583 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | imageHeavy | 100000 | 29857333 | 495462542 | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 14777791 | 22666209 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | structuredProse | 100000 | 61494667 | 100312417 | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 10000 | 40079708 | 20786333 | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 100000 | 178184417 | 474090167 | 1200 | 1200 | 0 | 1200 |
