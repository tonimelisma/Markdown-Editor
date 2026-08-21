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
Commit: 826841c74a2bb3796f4756e554441c53e6f07dd9
Run ID: de025e57-ccd4-4cae-b1bb-01206461f0f4

| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 8505583 | 22654667 | 294 | 140 | 7 | 154 |
| applyCommands | codeHeavy | 100000 | 33899333 | 79305583 | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 4758917 | 5386750 | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 242476167 | 54662333 | 252 | 120 | 6 | 132 |
| applyCommands | heavyLists | 10000 | 29180000 | 99485958 | 84 | 40 | 2 | 44 |
| applyCommands | heavyLists | 100000 | 79244708 | 20404542 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 10000 | 17362000 | 38915875 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 100000 | 31710084 | 11742125 | 210 | 100 | 5 | 110 |
| applyCommands | structuredProse | 10000 | 4414542 | n/a | 252 | 120 | 6 | 132 |
| applyCommands | structuredProse | 100000 | 92553458 | 244122709 | 126 | 60 | 3 | 66 |
| applyCommands | tableDense | 10000 | 46145333 | 59201375 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 98411750 | 15612375 | 42 | 20 | 1 | 22 |
| openAndIdle | codeHeavy | 10000 | 16146208 | 15491292 | 10 | 10 | 0 | 10 |
| openAndIdle | codeHeavy | 100000 | 75332875 | 70158125 | 10 | 10 | 0 | 10 |
| openAndIdle | degenerateParagraph | 10000 | 302458 | 1112542 | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | 17837000 | 84045459 | 10 | 10 | 0 | 10 |
| openAndIdle | heavyLists | 10000 | 6682625 | 15503334 | 11 | 11 | 0 | 11 |
| openAndIdle | heavyLists | 100000 | 78878375 | 25916875 | 10 | 10 | 0 | 10 |
| openAndIdle | imageHeavy | 10000 | 3103292 | 31375792 | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | n/a | n/a | 11 | 11 | 0 | 11 |
| openAndIdle | structuredProse | 10000 | 7860250 | 22176667 | 11 | 11 | 0 | 11 |
| openAndIdle | structuredProse | 100000 | 35852917 | 13545417 | 11 | 11 | 0 | 11 |
| openAndIdle | tableDense | 10000 | 36545334 | 12005375 | 10 | 10 | 0 | 10 |
| openAndIdle | tableDense | 100000 | 114580334 | 37934833 | 10 | 10 | 0 | 10 |
| scrollDocument | codeHeavy | 10000 | 1697917 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | codeHeavy | 100000 | 32915792 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | degenerateParagraph | 10000 | 584000 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | 14087000 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | heavyLists | 10000 | 16352708 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | heavyLists | 100000 | 95229292 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 10000 | 5507083 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 100000 | 47528709 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | structuredProse | 10000 | 4570583 | n/a | 12 | 12 | 0 | 24 |
| scrollDocument | structuredProse | 100000 | 29144875 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | tableDense | 10000 | 16155666 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | tableDense | 100000 | 105891000 | n/a | 9 | 9 | 0 | 18 |
| soak | codeHeavy | 10000 | 2445042 | 1648513000 | 344 | 344 | 0 | 344 |
| soak | codeHeavy | 100000 | 23517541 | 112447542 | 760 | 760 | 0 | 760 |
| soak | degenerateParagraph | 10000 | 7878708 | 4841584 | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | 6713375 | 860230458 | 1140 | 1140 | 0 | 1140 |
| soak | heavyLists | 10000 | 44938834 | 104653375 | 1376 | 1376 | 0 | 1376 |
| soak | heavyLists | 100000 | 113727458 | 872005041 | 1140 | 1140 | 0 | 1140 |
| soak | imageHeavy | 10000 | 32386166 | 60830750 | 1032 | 1032 | 0 | 1032 |
| soak | imageHeavy | 100000 | 45714667 | 878308833 | 1140 | 1140 | 0 | 1140 |
| soak | structuredProse | 10000 | 52271375 | 72582375 | 1032 | 1032 | 0 | 1032 |
| soak | structuredProse | 100000 | 100164708 | 730747375 | 1140 | 1140 | 0 | 1140 |
| soak | tableDense | 10000 | 36156125 | 72050875 | 1032 | 1032 | 0 | 1032 |
| soak | tableDense | 100000 | 170013458 | 930427250 | 760 | 760 | 0 | 760 |
| toggleModes | codeHeavy | 10000 | 10595625 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | codeHeavy | 100000 | 30984500 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | degenerateParagraph | 10000 | 397292 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | 32843542 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | heavyLists | 10000 | 7167875 | n/a | 480 | 480 | 0 | 480 |
| toggleModes | heavyLists | 100000 | n/a | n/a | 200 | 200 | 0 | 200 |
| toggleModes | imageHeavy | 10000 | 6873375 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | imageHeavy | 100000 | 50446875 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | structuredProse | 10000 | 27770958 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | structuredProse | 100000 | 49987375 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | tableDense | 10000 | 11254834 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | tableDense | 100000 | 139130542 | n/a | 360 | 360 | 0 | 360 |
| typeAdjacentMarkup | codeHeavy | 10000 | 123418000 | 42423375 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | codeHeavy | 100000 | 122765250 | 198476625 | 80 | 80 | 0 | 80 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 13002333 | 3904542 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | 1928542 | 377581250 | 320 | 320 | 0 | 320 |
| typeAdjacentMarkup | heavyLists | 10000 | 51345875 | 111450750 | 48 | 48 | 0 | 48 |
| typeAdjacentMarkup | heavyLists | 100000 | 139966542 | 89261958 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | imageHeavy | 10000 | 17391291 | 63176250 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | 47219708 | 1319441167 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | structuredProse | 10000 | 105606500 | 51214875 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | structuredProse | 100000 | 97134167 | 968903750 | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | tableDense | 10000 | 35019791 | 74890250 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | tableDense | 100000 | 147572625 | 994215208 | 320 | 320 | 0 | 320 |
| typeInTable | codeHeavy | 10000 | 112686667 | 153781625 | 24 | 24 | 0 | 24 |
| typeInTable | codeHeavy | 100000 | 34088208 | 252677875 | 200 | 200 | 0 | 200 |
| typeInTable | degenerateParagraph | 10000 | 6682500 | 134053792 | 60 | 60 | 0 | 60 |
| typeInTable | degenerateParagraph | 100000 | 1648375 | 9013042 | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 31805500 | 223130875 | 32 | 32 | 0 | 32 |
| typeInTable | heavyLists | 100000 | 79061292 | 321495292 | 80 | 80 | 0 | 80 |
| typeInTable | imageHeavy | 10000 | 11844583 | 192792333 | 28 | 28 | 0 | 28 |
| typeInTable | imageHeavy | 100000 | 38616500 | 915060208 | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 60946208 | 334396166 | 32 | 32 | 0 | 32 |
| typeInTable | structuredProse | 100000 | 80753625 | 1002728166 | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 74162625 | 189480959 | 36 | 36 | 0 | 36 |
| typeInTable | tableDense | 100000 | 111778333 | 110902250 | 120 | 120 | 0 | 120 |
| typeProse | codeHeavy | 10000 | 31507875 | 46204666 | 40 | 40 | 0 | 40 |
| typeProse | codeHeavy | 100000 | 58332417 | 511073875 | 160 | 160 | 0 | 160 |
| typeProse | degenerateParagraph | 10000 | 12265000 | 4947750 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 3991042 | 27844250 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 49682209 | 74982542 | 44 | 44 | 0 | 44 |
| typeProse | heavyLists | 100000 | n/a | 12320417 | 240 | 240 | 0 | 240 |
| typeProse | imageHeavy | 10000 | 29886833 | 95008000 | 36 | 36 | 0 | 36 |
| typeProse | imageHeavy | 100000 | n/a | 398100791 | 240 | 240 | 0 | 240 |
| typeProse | structuredProse | 10000 | 19537375 | 152699125 | 40 | 40 | 0 | 40 |
| typeProse | structuredProse | 100000 | 92758208 | 385306667 | 240 | 240 | 0 | 240 |
| typeProse | tableDense | 10000 | 67166916 | 144977125 | 44 | 44 | 0 | 44 |
| typeProse | tableDense | 100000 | 181410875 | 34127292 | 280 | 280 | 0 | 280 |
| undoRedoStorm | codeHeavy | 10000 | 49069667 | 549175167 | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | 55012958 | 104337667 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 714791 | 12195334 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | 8473250 | 1300126334 | 900 | 900 | 0 | 900 |
| undoRedoStorm | heavyLists | 10000 | 16904250 | 6955959 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | heavyLists | 100000 | 112442166 | 668334916 | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 10000 | 12758375 | 40557542 | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 100000 | 21676417 | 59959666 | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 26427292 | 85492084 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | structuredProse | 100000 | 47417375 | 454611625 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | tableDense | 10000 | 17981833 | 10102625 | 900 | 900 | 0 | 900 |
| undoRedoStorm | tableDense | 100000 | 167434375 | 766268416 | 900 | 900 | 0 | 900 |
