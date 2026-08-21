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
Commit: 414bd62ae5d3feca5665046d6395aa7cc8163398
Run ID: a854aa56-b786-4489-ae4e-0f6c1276019c

| scenario | corpus | size | parseProjection p95 ns | sourceHighlightCompute p95 ns | actions | accepted | refused | progress |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| applyCommands | codeHeavy | 10000 | 122484333 | 15631292 | 336 | 160 | 8 | 176 |
| applyCommands | codeHeavy | 100000 | 47323958 | 170851875 | 210 | 100 | 5 | 110 |
| applyCommands | degenerateParagraph | 10000 | 545042 | 1451167 | 546 | 260 | 13 | 286 |
| applyCommands | degenerateParagraph | 100000 | 29815000 | 43715000 | 168 | 80 | 4 | 88 |
| applyCommands | heavyLists | 10000 | 24494625 | 33421000 | 126 | 60 | 3 | 66 |
| applyCommands | heavyLists | 100000 | 132422500 | 23398417 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 10000 | 8893167 | 29162208 | 84 | 40 | 2 | 44 |
| applyCommands | imageHeavy | 100000 | 25875458 | 314443458 | 210 | 100 | 5 | 110 |
| applyCommands | structuredProse | 10000 | 7495208 | n/a | 168 | 80 | 4 | 88 |
| applyCommands | structuredProse | 100000 | 108299709 | 313326042 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 10000 | 30697459 | 36133875 | 84 | 40 | 2 | 44 |
| applyCommands | tableDense | 100000 | 184619250 | 21251417 | 42 | 20 | 1 | 22 |
| openAndIdle | codeHeavy | 10000 | 23458000 | 3702125 | 9 | 9 | 0 | 9 |
| openAndIdle | codeHeavy | 100000 | 43552375 | 29157875 | 12 | 12 | 0 | 12 |
| openAndIdle | degenerateParagraph | 10000 | 332750 | 1109750 | 16 | 16 | 0 | 16 |
| openAndIdle | degenerateParagraph | 100000 | 16953750 | 48626000 | 9 | 9 | 0 | 9 |
| openAndIdle | heavyLists | 10000 | 36992084 | 1539459 | 9 | 9 | 0 | 9 |
| openAndIdle | heavyLists | 100000 | 79187416 | 13740500 | 9 | 9 | 0 | 9 |
| openAndIdle | imageHeavy | 10000 | 19837666 | 1779792 | 11 | 11 | 0 | 11 |
| openAndIdle | imageHeavy | 100000 | 57849750 | 17037583 | 9 | 9 | 0 | 9 |
| openAndIdle | structuredProse | 10000 | 3603416 | 7575542 | 9 | 9 | 0 | 9 |
| openAndIdle | structuredProse | 100000 | 51637292 | 8141000 | 11 | 11 | 0 | 11 |
| openAndIdle | tableDense | 10000 | 31020709 | 2049958 | 9 | 9 | 0 | 9 |
| openAndIdle | tableDense | 100000 | 95958125 | 11805084 | 9 | 9 | 0 | 9 |
| scrollDocument | codeHeavy | 10000 | 2997375 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | codeHeavy | 100000 | 33942042 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | degenerateParagraph | 10000 | 659166 | n/a | 16 | 16 | 0 | 32 |
| scrollDocument | degenerateParagraph | 100000 | 14271375 | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | heavyLists | 10000 | 6923291 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | heavyLists | 100000 | 142906708 | n/a | 10 | 10 | 0 | 20 |
| scrollDocument | imageHeavy | 10000 | 5530875 | n/a | 11 | 11 | 0 | 22 |
| scrollDocument | imageHeavy | 100000 | 33539084 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | structuredProse | 10000 | 7005250 | n/a | 9 | 9 | 0 | 18 |
| scrollDocument | structuredProse | 100000 | 32933958 | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | tableDense | 10000 | 17210833 | n/a | 8 | 8 | 0 | 16 |
| scrollDocument | tableDense | 100000 | 287601375 | n/a | 8 | 8 | 0 | 16 |
| soak | codeHeavy | 10000 | 18826125 | 23313125 | 688 | 688 | 0 | 688 |
| soak | codeHeavy | 100000 | 42690625 | 131866625 | 1140 | 1140 | 0 | 1140 |
| soak | degenerateParagraph | 10000 | 7589334 | 1813084 | 3096 | 3096 | 0 | 3096 |
| soak | degenerateParagraph | 100000 | 12109583 | 46169958 | 760 | 760 | 0 | 760 |
| soak | heavyLists | 10000 | 36637917 | 76986625 | 1376 | 1376 | 0 | 1376 |
| soak | heavyLists | 100000 | 136321292 | 426641125 | 1140 | 1140 | 0 | 1140 |
| soak | imageHeavy | 10000 | 21245000 | 106842709 | 1032 | 1032 | 0 | 1032 |
| soak | imageHeavy | 100000 | 50691291 | 345423750 | 1140 | 1140 | 0 | 1140 |
| soak | structuredProse | 10000 | 17476000 | 32437958 | 1376 | 1376 | 0 | 1376 |
| soak | structuredProse | 100000 | 107545833 | 403471875 | 1140 | 1140 | 0 | 1140 |
| soak | tableDense | 10000 | 23406375 | 61847000 | 1032 | 1032 | 0 | 1032 |
| soak | tableDense | 100000 | 191883417 | 421673209 | 760 | 760 | 0 | 760 |
| toggleModes | codeHeavy | 10000 | 12229375 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | codeHeavy | 100000 | 35154833 | n/a | 400 | 400 | 0 | 400 |
| toggleModes | degenerateParagraph | 10000 | 504291 | n/a | 640 | 640 | 0 | 640 |
| toggleModes | degenerateParagraph | 100000 | 20823084 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | heavyLists | 10000 | 20242333 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | heavyLists | 100000 | 71419958 | n/a | 200 | 200 | 0 | 200 |
| toggleModes | imageHeavy | 10000 | 3412875 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | imageHeavy | 100000 | 93275875 | n/a | 440 | 440 | 0 | 440 |
| toggleModes | structuredProse | 10000 | 35157417 | n/a | 320 | 320 | 0 | 320 |
| toggleModes | structuredProse | 100000 | n/a | n/a | 320 | 320 | 0 | 320 |
| toggleModes | tableDense | 10000 | 23440334 | n/a | 360 | 360 | 0 | 360 |
| toggleModes | tableDense | 100000 | 102682917 | n/a | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | codeHeavy | 10000 | 118404667 | 25671792 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | codeHeavy | 100000 | 46224250 | 124862125 | 120 | 120 | 0 | 120 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | 13464500 | 2547375 | 64 | 64 | 0 | 64 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | 3304541 | 58337167 | 200 | 200 | 0 | 200 |
| typeAdjacentMarkup | heavyLists | 10000 | 41955542 | 88592667 | 32 | 32 | 0 | 32 |
| typeAdjacentMarkup | heavyLists | 100000 | 131856542 | 488250833 | 240 | 240 | 0 | 240 |
| typeAdjacentMarkup | imageHeavy | 10000 | 17266667 | 139399209 | 36 | 36 | 0 | 36 |
| typeAdjacentMarkup | imageHeavy | 100000 | 34099959 | 351903250 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | structuredProse | 10000 | 31721542 | 39986125 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | structuredProse | 100000 | 114566125 | 314803917 | 280 | 280 | 0 | 280 |
| typeAdjacentMarkup | tableDense | 10000 | 81611792 | 70996083 | 40 | 40 | 0 | 40 |
| typeAdjacentMarkup | tableDense | 100000 | 145415833 | 20923750 | 240 | 240 | 0 | 240 |
| typeInTable | codeHeavy | 10000 | 29365583 | 151182875 | 28 | 28 | 0 | 28 |
| typeInTable | codeHeavy | 100000 | 33011833 | 101436459 | 200 | 200 | 0 | 200 |
| typeInTable | degenerateParagraph | 10000 | 19942167 | 27996958 | 60 | 60 | 0 | 60 |
| typeInTable | degenerateParagraph | 100000 | 1649333 | 8732125 | 240 | 240 | 0 | 240 |
| typeInTable | heavyLists | 10000 | 69201083 | 116467583 | 28 | 28 | 0 | 28 |
| typeInTable | heavyLists | 100000 | 79375125 | 280121375 | 120 | 120 | 0 | 120 |
| typeInTable | imageHeavy | 10000 | 2575750 | 145749125 | 28 | 28 | 0 | 28 |
| typeInTable | imageHeavy | 100000 | 30820750 | 387246375 | 120 | 120 | 0 | 120 |
| typeInTable | structuredProse | 10000 | 107572625 | 81408041 | 20 | 20 | 0 | 20 |
| typeInTable | structuredProse | 100000 | 99860000 | 778689167 | 120 | 120 | 0 | 120 |
| typeInTable | tableDense | 10000 | 38760500 | 103935417 | 36 | 36 | 0 | 36 |
| typeInTable | tableDense | 100000 | n/a | 454207500 | 160 | 160 | 0 | 160 |
| typeProse | codeHeavy | 10000 | 30353375 | 29971750 | 36 | 36 | 0 | 36 |
| typeProse | codeHeavy | 100000 | 41727125 | 145653250 | 320 | 320 | 0 | 320 |
| typeProse | degenerateParagraph | 10000 | 10929958 | 2975375 | 64 | 64 | 0 | 64 |
| typeProse | degenerateParagraph | 100000 | 4519625 | 18472667 | 520 | 520 | 0 | 520 |
| typeProse | heavyLists | 10000 | 43085291 | 48219208 | 32 | 32 | 0 | 32 |
| typeProse | heavyLists | 100000 | 179565708 | 464448167 | 200 | 200 | 0 | 200 |
| typeProse | imageHeavy | 10000 | 19399791 | 82717792 | 40 | 40 | 0 | 40 |
| typeProse | imageHeavy | 100000 | n/a | 336612458 | 280 | 280 | 0 | 280 |
| typeProse | structuredProse | 10000 | 19231792 | 50510042 | 36 | 36 | 0 | 36 |
| typeProse | structuredProse | 100000 | 134413834 | 319945959 | 240 | 240 | 0 | 240 |
| typeProse | tableDense | 10000 | 29037583 | 77735792 | 32 | 32 | 0 | 32 |
| typeProse | tableDense | 100000 | 165375167 | 29461458 | 280 | 280 | 0 | 280 |
| undoRedoStorm | codeHeavy | 10000 | 19053500 | 5448625 | 900 | 900 | 0 | 900 |
| undoRedoStorm | codeHeavy | 100000 | 56825459 | 20754250 | 900 | 900 | 0 | 900 |
| undoRedoStorm | degenerateParagraph | 10000 | 537792 | 1070292 | 2700 | 2700 | 0 | 2700 |
| undoRedoStorm | degenerateParagraph | 100000 | 12908334 | 42999750 | 600 | 600 | 0 | 600 |
| undoRedoStorm | heavyLists | 10000 | 23792042 | 2535125 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | heavyLists | 100000 | 113230083 | 30433834 | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 10000 | 18770584 | 3236666 | 900 | 900 | 0 | 900 |
| undoRedoStorm | imageHeavy | 100000 | 53180333 | 17078708 | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 10000 | 36916250 | 1557792 | 900 | 900 | 0 | 900 |
| undoRedoStorm | structuredProse | 100000 | 53418375 | 14092375 | 1200 | 1200 | 0 | 1200 |
| undoRedoStorm | tableDense | 10000 | 75907958 | 3207833 | 600 | 600 | 0 | 600 |
| undoRedoStorm | tableDense | 100000 | 177520584 | 78915917 | 900 | 900 | 0 | 900 |
