# Soak validation

Developer tooling for real-time reliability and performance checks. It is not
part of the shipping application: the Swift sources under `Sources/` belong to
the `ScribeKitTests` target only, and every soak is skipped unless
`SCRIBEKIT_SOAK` is set in the environment. Launching ScribeKit normally cannot
reach any of it, and there is no simulation or debug mode in the app.

## Running one

```
Tools/SoakValidation/run-soak.sh sustainedCapture 60
Tools/SoakValidation/run-soak.sh presentationCost 15
Tools/SoakValidation/run-soak.sh pausedBaseline 9
```

The first argument is the case, the second the total minutes of capture, and
the third an optional bundle identifier to capture. `presentationCost` and
`pausedBaseline` split their minutes into three equal phases.

A soak is requested through `~/Library/Containers/quang.ScribeKit/Data/.scribekit-soak-run`,
which the script writes before the run and deletes when it exits. `xcodebuild`
does not carry its own environment into a Release-configured test host, so the
file is what reaches the sandboxed process; the harness reads nothing else, and
the file never exists during ordinary use.

Output goes to a fresh directory inside the sandbox container's own temporary
directory, whose exact path the run prints before it starts. Set
`SCRIBEKIT_SOAK_OUTPUT` to a path the sandbox can write to override it. That
directory holds the session ScribeKit produced *and* the run's own JSON report,
which is written beside the session directory and never inside it: measurements
are not meeting artifacts. Delete the directory when you are done with it.

`SCRIBEKIT_SOAK_RETENTION` (`none`, `raw`, `compressed`) and
`SCRIBEKIT_SOAK_SAMPLE_SECONDS` are the remaining knobs.

## What is real and what is not

Real: the `SCStream`, `ScreenCaptureKitAudioCapturer`, `AppleSpeechTranscriber`
over Apple's on-device recogniser, `MarkdownTranscriptStore`,
`RetainedAudioRecorder`, and `MeetingRuntime` driven through the same start,
pause, resume and stop the interface calls. Buffer cadence, format, frame
counts and presentation times are the framework's.

Synthetic: the sample values inside those buffers. This machine has no
capturable application that produces speech on demand, so
`SyntheticSpeechInjector` replaces each buffer's samples with a loop of
`AVSpeechSynthesizer` speech before the pipeline sees it. **No run here shows
that the captured application said anything.**

Substituted: security-scoped access to the disposable output directory, which
carries no bookmark because a bookmark can only come from a system panel. The
harness grants nothing the process did not already have, and the sandbox and
entitlements are untouched. Screen Recording permission is still required, from
the system, in the ordinary way.

## Permissions

The runs need Screen Recording granted to the test host, and at least one
running application to capture. A run that finds neither fails with the reason
rather than measuring nothing.
