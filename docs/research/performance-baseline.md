# Performance baseline

- **Authority:** Evidence only
- **First researched:** 2026-08-11
- **Last verified:** 2026-08-11
- **Refresh when:** app, OS, architecture, corpus, scenario, or benchmark-driver changes.
Host: Tonis-MacBook-Pro.local
OS: macOS 27.0
OS build: 26A5406e
Architecture: arm64
Configuration: Release
Xcode: Xcode 27.0; Build version 27A5228h
Corpus digest: 06196eca6dd05d6b63dc39555992561a278fd74a392be61734b09655d089c1fb
Warmup: 0
Samples: 6067
Interval: 120 ms
Commit: b27cf1964d1d3dc5163f247be65d886068b05a09
Run ID: 787e8cbf-56ea-4298-b0f1-91c561fc1874

| scenario | corpus | size | nativeInput p95 | mainActorLatency p95 | hitch ms/s | parses | bytes read | peak MB |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| typeProse | degenerateParagraph | 10000 | n/a | 10.747 ms | n/a | 1 | 0 | 83.94 |
| typeProse | degenerateParagraph | 100000 | n/a | 57.471 ms | n/a | 1 | 0 | 95.74 |
| typeProse | structuredProse | 10000 | n/a | 3.560 ms | n/a | 2 | 0 | 84.05 |
| typeProse | structuredProse | 100000 | n/a | 94.098 ms | n/a | 1 | 0 | 81.94 |
| typeProse | heavyLists | 10000 | n/a | 3.858 ms | n/a | 3 | 0 | 90.47 |
| typeProse | heavyLists | 100000 | n/a | 3.206 ms | n/a | 1 | 0 | 115.30 |
| typeProse | tableDense | 10000 | n/a | 3.173 ms | n/a | 2 | 0 | 76.28 |
| typeProse | tableDense | 100000 | n/a | 7.951 ms | n/a | 2 | 0 | 139.27 |
| typeProse | codeHeavy | 10000 | n/a | 1.350 ms | n/a | 2 | 0 | 82.89 |
| typeProse | codeHeavy | 100000 | n/a | 5.172 ms | n/a | 2 | 0 | 83.36 |
| typeProse | imageHeavy | 10000 | n/a | 6.549 ms | n/a | 4 | 0 | 72.55 |
| typeProse | imageHeavy | 100000 | n/a | 10.063 ms | n/a | 2 | 0 | 114.31 |
| typeInTable | degenerateParagraph | 10000 | n/a | 1.616 ms | n/a | 3 | 0 | 83.70 |
| typeInTable | degenerateParagraph | 100000 | n/a | 65.586 ms | n/a | 1 | 0 | 94.30 |
| typeInTable | structuredProse | 10000 | n/a | 2.697 ms | n/a | 3 | 0 | 83.89 |
| typeInTable | structuredProse | 100000 | n/a | 93.446 ms | n/a | 1 | 0 | 73.41 |
| typeInTable | heavyLists | 10000 | n/a | 3.193 ms | n/a | 3 | 0 | 89.83 |
| typeInTable | heavyLists | 100000 | n/a | 4.715 ms | n/a | 1 | 0 | 105.80 |
| typeInTable | tableDense | 10000 | n/a | 2.858 ms | n/a | 3 | 0 | 89.41 |
| typeInTable | tableDense | 100000 | n/a | 259.891 ms | n/a | 1 | 0 | 142.08 |
| typeInTable | codeHeavy | 10000 | n/a | 1.723 ms | n/a | 2 | 0 | 82.31 |
| typeInTable | codeHeavy | 100000 | n/a | 4.218 ms | n/a | 2 | 0 | 84.59 |
| typeInTable | imageHeavy | 10000 | n/a | 7.262 ms | n/a | 2 | 0 | 84.00 |
| typeInTable | imageHeavy | 100000 | n/a | 65.004 ms | n/a | 2 | 0 | 84.47 |
| typeAdjacentMarkup | degenerateParagraph | 10000 | n/a | 0.971 ms | n/a | 2 | 0 | 84.44 |
| typeAdjacentMarkup | degenerateParagraph | 100000 | n/a | 60.024 ms | n/a | 1 | 0 | 99.55 |
| typeAdjacentMarkup | structuredProse | 10000 | n/a | 2.956 ms | n/a | 3 | 0 | 84.84 |
| typeAdjacentMarkup | structuredProse | 100000 | n/a | 93.560 ms | n/a | 1 | 0 | 83.27 |
| typeAdjacentMarkup | heavyLists | 10000 | n/a | 1.587 ms | n/a | 2 | 0 | 89.44 |
| typeAdjacentMarkup | heavyLists | 100000 | n/a | 14.631 ms | n/a | 1 | 0 | 101.36 |
| typeAdjacentMarkup | tableDense | 10000 | n/a | 3.428 ms | n/a | 2 | 0 | 90.88 |
| typeAdjacentMarkup | tableDense | 100000 | n/a | 4.762 ms | n/a | 1 | 0 | 127.03 |
| typeAdjacentMarkup | codeHeavy | 10000 | n/a | 0.829 ms | n/a | 3 | 0 | 70.67 |
| typeAdjacentMarkup | codeHeavy | 100000 | n/a | 6.014 ms | n/a | 2 | 0 | 83.84 |
| typeAdjacentMarkup | imageHeavy | 10000 | n/a | 10.106 ms | n/a | 3 | 0 | 83.81 |
| typeAdjacentMarkup | imageHeavy | 100000 | n/a | 65.121 ms | n/a | 1 | 0 | 95.84 |
| applyCommands | degenerateParagraph | 10000 | n/a | 0.582 ms | n/a | 71 | 0 | 54.02 |
| applyCommands | degenerateParagraph | 100000 | n/a | 1.012 ms | n/a | 71 | 0 | 66.92 |
| applyCommands | structuredProse | 10000 | n/a | 0.256 ms | n/a | 71 | 0 | 58.42 |
| applyCommands | structuredProse | 100000 | n/a | 9.725 ms | n/a | 71 | 0 | 91.80 |
| applyCommands | heavyLists | 10000 | n/a | 2.311 ms | n/a | 71 | 0 | 62.33 |
| applyCommands | heavyLists | 100000 | n/a | 33.323 ms | n/a | 71 | 0 | 125.47 |
| applyCommands | tableDense | 10000 | n/a | 5.594 ms | n/a | 21 | 0 | 94.67 |
| applyCommands | tableDense | 100000 | n/a | 485.799 ms | n/a | 21 | 0 | 165.63 |
| applyCommands | codeHeavy | 10000 | n/a | 0.172 ms | n/a | 69 | 0 | 52.99 |
| applyCommands | codeHeavy | 100000 | n/a | 3.683 ms | n/a | 69 | 0 | 68.13 |
| applyCommands | imageHeavy | 10000 | n/a | 1.290 ms | n/a | 69 | 0 | 57.34 |
| applyCommands | imageHeavy | 100000 | n/a | 2.594 ms | n/a | 71 | 0 | 94.16 |
| toggleModes | degenerateParagraph | 10000 | n/a | 0.081 ms | n/a | 1 | 0 | 52.70 |
| toggleModes | degenerateParagraph | 100000 | n/a | 1.048 ms | n/a | 1 | 0 | 58.45 |
| toggleModes | structuredProse | 10000 | n/a | 0.130 ms | n/a | 1 | 0 | 53.11 |
| toggleModes | structuredProse | 100000 | n/a | 0.142 ms | n/a | 1 | 0 | 72.53 |
| toggleModes | heavyLists | 10000 | n/a | 0.106 ms | n/a | 1 | 0 | 55.44 |
| toggleModes | heavyLists | 100000 | n/a | 0.956 ms | n/a | 1 | 0 | 72.08 |
| toggleModes | tableDense | 10000 | n/a | 4.182 ms | n/a | 1 | 0 | 58.05 |
| toggleModes | tableDense | 100000 | n/a | 1.452 ms | n/a | 1 | 0 | 89.06 |
| toggleModes | codeHeavy | 10000 | n/a | 0.072 ms | n/a | 1 | 0 | 52.77 |
| toggleModes | codeHeavy | 100000 | n/a | 0.097 ms | n/a | 1 | 0 | 60.80 |
| toggleModes | imageHeavy | 10000 | n/a | 0.080 ms | n/a | 1 | 0 | 53.47 |
| toggleModes | imageHeavy | 100000 | n/a | 0.870 ms | n/a | 1 | 0 | 68.61 |
| scrollDocument | degenerateParagraph | 10000 | n/a | 0.068 ms | n/a | 1 | 0 | 52.69 |
| scrollDocument | degenerateParagraph | 100000 | n/a | 0.109 ms | n/a | 1 | 0 | 63.95 |
| scrollDocument | structuredProse | 10000 | n/a | 0.112 ms | n/a | 1 | 0 | 52.97 |
| scrollDocument | structuredProse | 100000 | n/a | 0.160 ms | n/a | 1 | 0 | 67.16 |
| scrollDocument | heavyLists | 10000 | n/a | 0.152 ms | n/a | 1 | 0 | 56.63 |
| scrollDocument | heavyLists | 100000 | n/a | 0.964 ms | n/a | 1 | 0 | 71.31 |
| scrollDocument | tableDense | 10000 | n/a | 1.498 ms | n/a | 1 | 0 | 57.56 |
| scrollDocument | tableDense | 100000 | n/a | 1.450 ms | n/a | 1 | 0 | 90.34 |
| scrollDocument | codeHeavy | 10000 | n/a | 0.060 ms | n/a | 1 | 0 | 56.47 |
| scrollDocument | codeHeavy | 100000 | n/a | 0.876 ms | n/a | 1 | 0 | 64.95 |
| scrollDocument | imageHeavy | 10000 | n/a | 0.089 ms | n/a | 1 | 0 | 57.56 |
| scrollDocument | imageHeavy | 100000 | n/a | 3.346 ms | n/a | 1 | 0 | 72.67 |
| undoRedoStorm | degenerateParagraph | 10000 | n/a | 8.754 ms | n/a | 2 | 0 | 98.47 |
| undoRedoStorm | degenerateParagraph | 100000 | n/a | 122.056 ms | n/a | 2 | 0 | 109.78 |
| undoRedoStorm | structuredProse | 10000 | n/a | 19.588 ms | n/a | 3 | 0 | 99.00 |
| undoRedoStorm | structuredProse | 100000 | n/a | 82.703 ms | n/a | 1 | 0 | 77.30 |
| undoRedoStorm | heavyLists | 10000 | n/a | 15.088 ms | n/a | 3 | 0 | 103.14 |
| undoRedoStorm | heavyLists | 100000 | n/a | 117.133 ms | n/a | 1 | 0 | 108.83 |
| undoRedoStorm | tableDense | 10000 | n/a | 15.421 ms | n/a | 2 | 0 | 103.77 |
| undoRedoStorm | tableDense | 100000 | n/a | 121.085 ms | n/a | 1 | 0 | 146.55 |
| undoRedoStorm | codeHeavy | 10000 | n/a | 30.680 ms | n/a | 3 | 0 | 96.45 |
| undoRedoStorm | codeHeavy | 100000 | n/a | 7.521 ms | n/a | 2 | 0 | 103.83 |
| undoRedoStorm | imageHeavy | 10000 | n/a | 7.579 ms | n/a | 2 | 0 | 98.42 |
| undoRedoStorm | imageHeavy | 100000 | n/a | 105.683 ms | n/a | 1 | 0 | 97.09 |
| openAndIdle | degenerateParagraph | 10000 | n/a | 0.069 ms | n/a | 1 | 0 | 56.99 |
| openAndIdle | degenerateParagraph | 100000 | n/a | 1.062 ms | n/a | 1 | 0 | 67.81 |
| openAndIdle | structuredProse | 10000 | n/a | 0.059 ms | n/a | 1 | 0 | 57.13 |
| openAndIdle | structuredProse | 100000 | n/a | 0.345 ms | n/a | 1 | 0 | 76.77 |
| openAndIdle | heavyLists | 10000 | n/a | 0.074 ms | n/a | 1 | 0 | 60.70 |
| openAndIdle | heavyLists | 100000 | n/a | 0.803 ms | n/a | 1 | 0 | 77.83 |
| openAndIdle | tableDense | 10000 | n/a | 0.088 ms | n/a | 1 | 0 | 61.47 |
| openAndIdle | tableDense | 100000 | n/a | 1.283 ms | n/a | 1 | 0 | 95.25 |
| openAndIdle | codeHeavy | 10000 | n/a | 0.114 ms | n/a | 1 | 0 | 56.70 |
| openAndIdle | codeHeavy | 100000 | n/a | 2.314 ms | n/a | 1 | 0 | 66.99 |
| openAndIdle | imageHeavy | 10000 | n/a | 0.071 ms | n/a | 1 | 0 | 57.72 |
| openAndIdle | imageHeavy | 100000 | n/a | 3.057 ms | n/a | 1 | 0 | 74.02 |
| soak | degenerateParagraph | 10000 | n/a | 11.694 ms | n/a | 2 | 0 | 101.94 |
| soak | degenerateParagraph | 100000 | n/a | 115.141 ms | n/a | 1 | 0 | 108.69 |
| soak | structuredProse | 10000 | n/a | 15.404 ms | n/a | 2 | 0 | 103.31 |
| soak | structuredProse | 100000 | n/a | 109.350 ms | n/a | 1 | 0 | 89.47 |
| soak | heavyLists | 10000 | n/a | 21.186 ms | n/a | 4 | 0 | 99.91 |
| soak | heavyLists | 100000 | n/a | 127.881 ms | n/a | 2 | 0 | 110.89 |
| soak | tableDense | 10000 | n/a | 19.390 ms | n/a | 1 | 0 | 103.34 |
| soak | tableDense | 100000 | n/a | 127.385 ms | n/a | 1 | 0 | 147.30 |
| soak | codeHeavy | 10000 | n/a | 17.204 ms | n/a | 2 | 0 | 101.00 |
| soak | codeHeavy | 100000 | n/a | 10.426 ms | n/a | 2 | 0 | 96.45 |
| soak | imageHeavy | 10000 | n/a | 11.763 ms | n/a | 4 | 0 | 101.61 |
| soak | imageHeavy | 100000 | n/a | 109.000 ms | n/a | 1 | 0 | 99.91 |
