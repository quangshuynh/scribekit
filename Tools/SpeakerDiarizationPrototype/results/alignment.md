# Transcript alignment

Recognised words are traced to the script turn they came from by word-level edit-distance alignment, independent of timestamps. A *mixed final* is one finalised SpeechTranscriber result — one ScribeKit passage — containing aligned words from more than one speaker. Timing errors compare the recogniser's word ranges with where each turn's audio was placed (negative = early).

| Fixture | Finals | Mixed finals | Words in mixed finals | Finals starting ≥0.3 s before their speech | Turn start error, median (max) | Turn end error, median (min) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| one-speaker | 8 | 0 | 0 of 94 | 8 | -0.89 s (-0.66) | -0.35 s (-0.50) |
| two-alternating | 12 | 0 | 0 of 136 | 12 | -0.92 s (+0.22) | -0.38 s (-0.48) |
| three-speakers | 12 | 0 | 0 of 140 | 12 | -0.82 s (-0.45) | -0.28 s (-0.52) |
| same-speaker-returns | 10 | 0 | 0 of 115 | 10 | -0.75 s (-0.51) | -0.21 s (-0.44) |
| long-silences | 9 | 0 | 0 of 92 | 7 | -0.90 s (-0.30) | -0.20 s (-0.49) |
| background-noise | 11 | 0 | 0 of 108 | 10 | -0.80 s (-0.45) | -0.24 s (-0.43) |
| tonal-background | 12 | 0 | 0 of 106 | 10 | -0.80 s (-0.56) | -0.25 s (-0.36) |
| short-interjections | 22 | 0 | 0 of 192 | 13 | -0.75 s (-0.23) | -0.22 s (-0.54) |
| unequal-volume | 12 | 0 | 0 of 137 | 12 | -0.85 s (-0.58) | -0.24 s (-0.53) |
| distance-change | 10 | 0 | 0 of 105 | 8 | -0.53 s (-0.04) | +0.01 s (-0.21) |
| similar-voices | 11 | 0 | 0 of 109 | 10 | -0.65 s (+0.07) | -0.13 s (-0.31) |
| narrowband | 11 | 0 | 0 of 111 | 10 | -0.86 s (-0.51) | -0.32 s (-0.53) |
| overlap | 6 | 3 | 56 of 82 | 1 | +0.62 s (+0.89) | -0.27 s (-0.69) |
| rapid-turns | 13 | 0 | 0 of 133 | 8 | -0.38 s (+0.32) | -0.36 s (-0.57) |
| six-speakers | 13 | 0 | 0 of 138 | 12 | -0.87 s (-0.40) | -0.25 s (-0.52) |
| **all** | 172 | 3 | 56 of 1798 | 143 | -0.78 s (+0.89) | -0.25 s (-0.69) |
