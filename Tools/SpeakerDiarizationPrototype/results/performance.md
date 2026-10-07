# Performance

Host: 8 cores, macOS Version 26.6.2 (Build 25G83), 16 GB. Release build. 10 minutes of corpus audio.

| Phase | Wall (s) | CPU (s) | Real-time factor (CPU s / audio s) | Peak footprint (MB) | Note |
| --- | ---: | ---: | ---: | ---: | --- |
| baseline footprint | 0.000 | 0.000 | – | 194.5 | process idle with 10 min of audio in memory |
| AudioFeaturePrint cold start | 0.176 | 0.099 | – | 204.8 | first call on 2 s of audio, includes model load |
| energy activity, 10 min | 0.011 | 0.012 | 0.0000 | 204.8 |  |
| MFCC-stats embedding, 10 min | 0.134 | 0.134 | 0.0002 | 211.4 | 705 windows |
| AudioFeaturePrint embedding, 10 min | 3.258 | 3.322 | 0.0055 | 254.3 | 705 windows, warm |
| post-meeting clustering, 10 min | 0.146 | 0.146 | 0.0002 | 254.5 | agglomerative, 705 windows |
| live clustering, 10 min | 0.004 | 0.004 | 0.0000 | 254.6 | leader, 705 windows |
| agglomerative worst case, n=400 | 0.030 | 0.030 | – | 254.6 | every window merged; ≈ 5 min of continuous speech; distance matrix 1 MB |
| agglomerative worst case, n=800 | 0.227 | 0.226 | – | 254.8 | every window merged; ≈ 10 min of continuous speech; distance matrix 2 MB |
| agglomerative worst case, n=1600 | 1.776 | 1.774 | – | 257.0 | every window merged; ≈ 20 min of continuous speech; distance matrix 10 MB |
| transcription alone, 10 min | 10.606 | 1.069 | 0.0018 | 258.5 | SpeechTranscriber from file; this process's CPU only — the model's own inference is not attributed to it (standalone: 0.93 s CPU, 8 MB peak) |
| transcription + live diarization concurrently, 10 min | 10.488 | 1.222 | 0.0020 | 258.6 | MFCC-stats + leader in a parallel task |
