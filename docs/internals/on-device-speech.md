# On-device Speech

Speech recognition uses `SpeechAnalyzer` and `SpeechTranscriber`, Apple's
on-device speech APIs, against a language model installed on this Mac.

ScribeKit checks that the model for the selected language is installed and
refuses to start when it is not. It never downloads one on your behalf and
never falls back to network recognition. It does not use `SFSpeechRecognizer`,
the older API that can send audio to Apple's servers. The app ships without the
network client entitlement, so the sandbox does not permit it to open a network
connection at all. See [Network Policy](../privacy/network-policy.md).

## A run is not the meeting

A recognition run counts its offsets from its own first frame, and a meeting
outlives any number of runs. What a run reports is therefore put back on the
meeting's own media timeline before it is displayed or written:
`MeetingRuntime` holds one accumulator, `mediaOffsetBase`, set from a captured
media clock and added to every offset a run reports — segments, and the
position of dropped audio alike.

The base is read from captured frames rather than from the wall clock, so
nothing a pause spends can leak into it. An offset in the transcript therefore
names the same second of the recording however many times the recogniser was
rebuilt.

The origin that mapping uses changes only when every event the previous run
published has been handled: the boundary a pause reaches by draining, and the
one a self-restart has to schedule, because it happens inside the handler for
the event that caused it.

## Restarts

A recogniser that stops by itself is restarted at most twice. Audio arriving
during a restart is not transcribed and is counted as a gap, and a restarted
run's spans keep the meeting's own offsets rather than starting again at zero.

A recogniser that cannot be brought back ends the meeting rather than becoming
a state to sit in: capture stops, the durable artifacts are closed and kept,
the session is recorded as the failure it was, and every hold on the process is
released.

## Honest reporting

A missing model, an unsupported language, a recogniser that stops by itself,
and audio that recognition fell too far behind to transcribe are all reported
rather than absorbed. Transcription uncertainty is surfaced, not hidden.
