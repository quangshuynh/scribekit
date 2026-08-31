//
//  MeetingSetupView.swift
//  ScribeKit
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The screen that configures a meeting and shows the one that is running.
///
/// The screen collects the settings a session needs — title, audio sources,
/// audio retention and save location — and displays the meeting: capture,
/// on-device recognition and a timestamped Markdown transcript written to the
/// chosen folder while the meeting is under way.
///
/// It does not own the meeting. ``MeetingRuntime`` is handed in and belongs to
/// the application, so this screen can be closed, hidden or built again
/// without starting, stopping or duplicating anything. What the screen does
/// own is the configuration for the *next* meeting, which is exactly the state
/// that should disappear with it.
struct MeetingSetupView: View {
    /// The application's meeting owner, shared with the menu bar.
    let runtime: MeetingRuntime

    @State private var sources: MeetingSetupSourcesModel
    @State private var destination: MeetingSetupDestinationModel
    @State private var recovery = SessionRecoveryModel()
    @State private var title = ""
    @State private var audioRetention: AudioRetentionMode
    @State private var isChoosingDestination = false

    private let preferences: MeetingSetupPreferencesStoring

    /// Creates the setup screen.
    ///
    /// - Parameters:
    ///   - runtime: The application's meeting owner.
    ///   - sourceProvider: Discovery used to populate the application list. The
    ///     default talks to ScreenCaptureKit; previews and tests can substitute
    ///     their own.
    ///   - saveLocation: Storage for the chosen save folder. The default keeps
    ///     a security-scoped bookmark in the local preference store.
    ///   - preferences: Store for the setup choices remembered between
    ///     launches.
    init(
        runtime: MeetingRuntime,
        sourceProvider: CaptureSourceProviding = ScreenCaptureKitSourceProvider(),
        saveLocation: SaveLocationPersisting = SecurityScopedSaveLocationStore(),
        preferences: MeetingSetupPreferencesStoring = UserDefaultsMeetingSetupPreferences()
    ) {
        self.runtime = runtime
        self.preferences = preferences
        _sources = State(initialValue: MeetingSetupSourcesModel(provider: sourceProvider, preferences: preferences))
        _destination = State(initialValue: MeetingSetupDestinationModel(persistence: saveLocation))
        _audioRetention = State(initialValue: preferences.audioRetention)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Form {
                readinessSection
                if runtime.outcome != nil { outcomeSection }
                if recovery.isVisible { recoverySection }
                meetingSection
                sourcesSection
                captureSection
                transcriptSection
                transcriptFileSection
                audioRetentionSection
                destinationSection
            }
            .formStyle(.grouped)
            footer
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .task {
            destination.restore()
            await checkForUnfinishedSessions()
            await runtime.prepare()
            await sources.refresh()
        }
        .onChange(of: audioRetention) { _, mode in
            preferences.audioRetention = mode
        }
        .fileImporter(
            isPresented: $isChoosingDestination,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                destination.choose(url)
                Task { await checkForUnfinishedSessions() }
            }
        }
    }

    /// Looks in the current save folder for meetings that never finished.
    ///
    /// Only ever a file scan, and never while a meeting is running: the
    /// session being written right now is legitimately marked in progress, and
    /// offering it as an interrupted meeting would be nonsense. It runs when
    /// the screen appears and when a folder is chosen — never on a timer, and
    /// never because the menu bar changed.
    private func checkForUnfinishedSessions() async {
        guard runtime.allowsRecovery else { return }
        if let url = destination.url {
            await recovery.check(url)
        } else if let warning = destination.warningMessage {
            recovery.reportDestinationUnavailable(warning)
        }
    }

    /// What ScribeKit found from a previous launch, and the two things the
    /// user can do about it.
    ///
    /// Neither action resumes anything. The transcript is already on disk with
    /// everything that reached it; recovery's job is to say so, confirm it is
    /// readable, and close the record honestly.
    @ViewBuilder
    private var recoverySection: some View {
        Section("Previous Meetings") {
            if case .checking = recovery.state {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking the save folder…").foregroundStyle(.secondary)
                }
            }

            if case let .unavailable(message) = recovery.state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Unfinished meeting check failed. \(message)")
            }

            ForEach(recovery.candidates) { candidate in
                candidateRow(for: candidate)
            }

            ForEach(recovery.problems) { problem in
                Label(
                    "\(problem.name): \(problem.error.errorDescription ?? "")",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Damaged session record. \(problem.name). "
                                    + (problem.error.errorDescription ?? ""))
            }

            if let message = recovery.actionMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if recovery.hasFindings {
                Text("ScribeKit does not resume a meeting it did not finish. "
                     + "Nothing is recorded again, and no transcript is deleted or rewritten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// One unfinished meeting, stated in terms of what is actually known.
    ///
    /// The times shown are the meeting's start, which its record holds, and
    /// when the transcript was last written, which the filesystem holds. When
    /// ScribeKit stopped is not shown, because nothing measured it.
    ///
    /// - Parameter candidate: The unfinished session.
    /// - Returns: The row view.
    private func candidateRow(for candidate: SessionRecoveryCandidate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(candidate.metadata.title) did not finish")
                .font(.headline)
            Text("Started \(candidate.metadata.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if candidate.metadata.wasPausedWhenInterrupted, let pausedAt = candidate.metadata.pausedAt {
                Text("This meeting was paused at "
                     + "\(pausedAt.formatted(date: .omitted, time: .standard)) and ScribeKit stopped before it "
                     + "was resumed or finished. Nothing was captured after the pause.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let modified = candidate.transcript.modifiedAt {
                Text("Transcript last written \(modified.formatted(date: .abbreviated, time: .shortened))"
                     + " · \(candidate.transcript.byteCount) bytes")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let audio = candidate.retainedAudio, let url = candidate.retainedAudioURL {
                Text("Audio \(url.lastPathComponent) · \(audio.byteCount) bytes. "
                     + "It was still being written, so whether it plays depends on how far it got.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Text(candidate.transcriptURL.path(percentEncoded: false))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([candidate.transcriptURL])
                }
                .accessibilityHint("Reveal this meeting's transcript in the Finder")

                Button("Mark as Interrupted") {
                    Task { await recovery.recordInterruption(for: candidate) }
                }
                .disabled(!runtime.allowsRecovery)
                .accessibilityHint("Record the interruption in this meeting's transcript and session record")

                Button("Dismiss") { recovery.dismiss(candidate) }
                    .accessibilityHint("Hide this until the next launch, changing nothing on disk")
            }

            if !runtime.allowsRecovery {
                Text("Available once the current meeting has finished.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    /// Whether a meeting can be started right now, and why not when it cannot.
    ///
    /// Derived here and read by every control that depends on it, so the
    /// readiness rows, the Start button's availability and the sentence beside
    /// it are three renderings of one answer rather than three checks that can
    /// disagree.
    private var readiness: MeetingStartReadiness {
        MeetingStartReadiness(
            saveLocation: destination.readiness,
            captureSources: sources.readiness,
            speech: runtime.availability,
            meetingIsActive: runtime.isRunning
        )
    }

    /// What a first-time user needs before they can start, in one place.
    ///
    /// Four compact rows rather than a wizard: everything below configures the
    /// same four prerequisites in detail, and this says at a glance which of
    /// them are satisfied. Each row states its status in words as well as an
    /// icon, so nothing depends on colour.
    private var readinessSection: some View {
        Section("Before You Start") {
            ForEach(readiness.rows) { row in
                readinessRow(row)
            }
        }
    }

    /// One prerequisite, with the action that resolves it when there is one.
    ///
    /// - Parameter row: The prerequisite to present.
    /// - Returns: The row view.
    @ViewBuilder
    private func readinessRow(_ row: MeetingStartReadiness.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Label(row.status.label, systemImage: row.status.symbolName)
                        .labelStyle(.iconOnly)
                    Text(row.prerequisite.title)
                        .font(.headline)
                    Text(row.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(row.accessibilityDescription)

            readinessAction(for: row)
        }
    }

    /// The control that resolves one prerequisite, when a control can.
    ///
    /// - Parameter row: The prerequisite being presented.
    /// - Returns: A button, or nothing for a row that is already satisfied.
    @ViewBuilder
    private func readinessAction(for row: MeetingStartReadiness.Row) -> some View {
        if row.status == .satisfied {
            EmptyView()
        } else {
            switch row.prerequisite {
            case .saveLocation:
                Button("Choose Folder…") { isChoosingDestination = true }
                    .disabled(runtime.isRunning)
                    .accessibilityHint("Choose the folder meetings are saved to")
            case .captureAccess, .captureSource:
                Button("Refresh") { Task { await sources.refresh() } }
                    .disabled(sources.isDiscovering)
                    .accessibilityHint("Look for applications ScribeKit can record again")
            case .speechRecognition:
                Button("Check Again") { Task { await runtime.prepare() } }
                    .disabled(runtime.isRunning)
                    .accessibilityHint("Check which speech models are installed again")
            }
        }
    }

    /// What the meeting that ended means for its files, and what to do next.
    ///
    /// Shown inline rather than as an alert: it describes something that has
    /// already finished, the artifacts it names are still there, and an alert
    /// would have to be dismissed before the folder it points at could be
    /// opened. A finished meeting and a failed one use the same panel, so
    /// nothing has to decide which shape of announcement an ending deserves.
    @ViewBuilder
    private var outcomeSection: some View {
        if let outcome = runtime.outcome {
            Section("Last Meeting") {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        outcome.headline,
                        systemImage: outcome.isFailure ? "exclamationmark.triangle" : "checkmark.circle"
                    )
                    .font(.headline)
                    Text(outcome.meaning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text(outcome.nextStep)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let detail = outcome.detail {
                        Text(detail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        if let layout = runtime.persistenceState.layout {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([layout.transcriptURL])
                            }
                            .accessibilityHint("Reveal this meeting's transcript in the Finder")
                        }
                        Button("Dismiss") { runtime.dismissOutcome() }
                            .accessibilityHint("Hide this summary; nothing on disk changes")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Last meeting")
                .accessibilityValue(outcome.accessibilityDescription)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ScribeKit")
                .font(.largeTitle.weight(.semibold))
            Text("Local-first meeting transcription for macOS.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The meeting being configured, and the one that is running.
    ///
    /// The title field configures the *next* meeting. A running meeting keeps
    /// the title it was started with — it is already in the transcript header
    /// — so the field is disabled while one runs and the running meeting is
    /// named separately, rather than letting one text field appear to be two
    /// different things.
    private var meetingSection: some View {
        Section("Meeting") {
            TextField("Title", text: $title, prompt: Text(MeetingSession.untitledPlaceholder))
                .disabled(runtime.isRunning)
                .accessibilityLabel("Meeting title")

            RunningMeetingLabel(runtime: runtime)
        }
    }

    private var sourcesSection: some View {
        Section {
            switch sources.discoveryState {
            case .idle, .loading:
                LabeledContent("Applications") {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking for applications…")
                            .foregroundStyle(.secondary)
                    }
                }
            case let .loaded(discovered) where discovered.isEmpty:
                Text("No applications are available to capture.")
                    .foregroundStyle(.secondary)
            case let .loaded(discovered):
                ForEach(discovered) { source in
                    sourceRow(for: source)
                }
                selectionSummary
            case let .accessUnavailable(message):
                Label(message, systemImage: "lock")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Screen and System Audio Recording access unavailable. \(message)")
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Application discovery failed. \(message)")
            }

            if !sources.unavailableSelectionNames.isEmpty {
                Text("No longer running, so removed from your selection: "
                     + sources.unavailableSelectionNames.formatted(.list(type: .and)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Selected applications are the ones audio capture records.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } header: {
            HStack {
                Text("Audio Sources")
                Spacer()
                Button("Refresh") {
                    Task { await sources.refresh() }
                }
                .disabled(sources.isDiscovering)
                .accessibilityHint("Look for running applications again")
            }
        }
    }

    /// A selectable row for one discovered application.
    ///
    /// A checkbox carries the selection state, so it is exposed to
    /// accessibility and visible without relying on colour.
    ///
    /// - Parameter source: The application to present.
    /// - Returns: The row view.
    private func sourceRow(for source: CaptureSource) -> some View {
        Toggle(source.displayName, isOn: Binding(
            get: { sources.isSelected(source) },
            set: { sources.setSelection($0, for: source) }
        ))
        .toggleStyle(.checkbox)
        .disabled(runtime.isRunning)
        .accessibilityHint("Include this application as a meeting audio source")
    }

    private var selectionSummary: some View {
        Text(sources.selectedSources.isEmpty
             ? "No applications selected."
             : "\(sources.selectedSources.count) selected: "
               + sources.selectedSources.map(\.displayName).formatted(.list(type: .and)))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var captureSection: some View {
        Section("Capture & Transcription") {
            LabeledContent("Audio") {
                Text(captureStatusDescription)
                    .foregroundStyle(runtime.captureState == .idle ? .secondary : .primary)
            }
            .accessibilityLabel("Capture status")
            .accessibilityValue(captureStatusDescription)

            if case let .failed(message) = runtime.captureState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            LabeledContent("Recognition") {
                Text(recognitionStatusDescription)
                    .foregroundStyle(runtime.transcriptionState == .idle ? .secondary : .primary)
            }
            .accessibilityLabel("Recognition status")
            .accessibilityValue(recognitionStatusDescription)

            if case let .failed(message) = runtime.transcriptionState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            localePicker

            CaptureActivityLabel(runtime: runtime)

            Text("Speech is recognised on this Mac, using an installed language model. "
                 + "No audio leaves your machine.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Where finalised speech is being written, and whether it still is.
    ///
    /// One status line, no per-segment feedback: the transcript is either
    /// being saved to a named file or it is not, and the second case is the
    /// only one worth an alarm.
    private var transcriptFileSection: some View {
        Section("Transcript File") {
            LabeledContent("Status") {
                Text(persistenceStatusDescription)
                    .foregroundStyle(runtime.persistenceState == .idle ? .secondary : .primary)
            }
            .accessibilityLabel("Transcript file status")
            .accessibilityValue(persistenceStatusDescription)

            if let layout = runtime.persistenceState.layout {
                LabeledContent("File") {
                    Text(layout.transcriptURL.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityLabel("Transcript file")
                .accessibilityValue(layout.transcriptURL.path(percentEncoded: false))

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([layout.transcriptURL])
                }
                .accessibilityHint("Reveal the transcript in the Finder")
            }

            if let message = runtime.persistenceState.failureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text("The transcript is Markdown and is written as speech is finalised, "
                 + "so it stays readable in any editor while the meeting runs.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// What the meeting would start with, or `nil` when it could not start.
    private var startRequest: MeetingStartRequest? {
        guard let url = destination.url else { return nil }
        return MeetingStartRequest(
            title: title,
            sources: sources.selectedSources,
            destination: url,
            audioRetention: audioRetention
        )
    }

    /// A short description of what the durable transcript is doing.
    private var persistenceStatusDescription: String {
        switch runtime.persistenceState {
        case .idle: destination.url == nil
            ? "No transcript. Choose a save folder first."
            : "No transcript yet. Start a meeting to write one."
        case .preparing: "Creating the meeting folder…"
        case .saving: "Saving finalised speech as it is recognised."
        case .saved: "Saved and closed."
        case .failed: "Not being saved."
        }
    }

    /// The recognition language, chosen explicitly and fixed for a run.
    ///
    /// Only locales whose on-device model is installed can be selected;
    /// supported but uninstalled ones are listed and disabled, so the reason a
    /// language is unavailable is visible rather than implied by its absence.
    @ViewBuilder
    private var localePicker: some View {
        if runtime.availableLocales.isEmpty {
            LabeledContent("Language") {
                Text("No recognition languages are available.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("Language", selection: Binding(
                get: { runtime.localeIdentifier },
                set: { identifier in Task { await runtime.selectLocale(identifier) } }
            )) {
                ForEach(runtime.availableLocales) { locale in
                    Text(locale.isInstalled ? locale.displayName : "\(locale.displayName) (not installed)")
                        .tag(locale.id)
                }
            }
            .disabled(runtime.isRunning)
            .accessibilityLabel("Recognition language")

            if let message = runtime.availability.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if !runtime.availability.canTranscribe {
                Button("Check Again") { Task { await runtime.prepare() } }
                    .disabled(runtime.isRunning)
                    .accessibilityHint("Check which speech models are installed again")
            }
        }
    }

    /// A short description of what capture is doing.
    private var captureStatusDescription: String {
        switch runtime.captureState {
        case .idle: sources.selectedSources.isEmpty
            ? "Not capturing. Select at least one application."
            : "Not capturing. \(sources.selectedSources.count) application(s) selected."
        case .preparing: "Starting…"
        case .capturing: "Capturing \(sources.selectedSources.count) application(s)."
        case .paused: "Paused. Nothing is being captured."
        case .stopping: "Stopping…"
        case .failed: "Capture failed."
        }
    }

    /// A short description of what recognition is doing.
    private var recognitionStatusDescription: String {
        switch runtime.transcriptionState {
        case .idle: runtime.availability.canTranscribe
            ? "Ready, on this Mac."
            : "Unavailable."
        case .preparing: "Preparing the recogniser…"
        case .transcribing: "Transcribing on device."
        case .recovering: "Recognition stopped; restarting…"
        case .stopping: "Finalising…"
        case .failed: "Recognition failed."
        }
    }

    /// The live transcript, in a view of its own.
    ///
    /// See ``LiveTranscriptSection`` for why it is not written inline here.
    private var transcriptSection: some View {
        LiveTranscriptSection(runtime: runtime)
    }

    /// What the meeting keeps of its audio, and — once it is keeping some —
    /// where that file is.
    ///
    /// The choice is fixed for a run, so the picker is disabled while a meeting
    /// is under way rather than accepting a change that would not take effect
    /// until the next one.
    private var audioRetentionSection: some View {
        Section("Audio Retention") {
            Picker("Keep audio", selection: $audioRetention) {
                ForEach(AudioRetentionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(runtime.isRunning)
            .accessibilityLabel("Audio retention mode")

            LabeledContent("Status") {
                Text(audioStatusDescription)
                    .foregroundStyle(runtime.audioRetentionState == .idle ? .secondary : .primary)
            }
            .accessibilityLabel("Audio file status")
            .accessibilityValue(audioStatusDescription)

            if let url = runtime.audioRetentionState.url {
                LabeledContent("File") {
                    Text(url.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .accessibilityLabel("Audio file")
                .accessibilityValue(url.path(percentEncoded: false))

                Button("Show Audio in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityHint("Reveal the meeting's audio file in the Finder")
            }

            if let message = runtime.audioRetentionState.failureMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(audioRetentionExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// A short description of what the audio file is doing.
    private var audioStatusDescription: String {
        switch runtime.audioRetentionState {
        case .idle: audioRetention.retainsAudio
            ? "No audio file yet. Start a meeting to record one."
            : "No audio file. Only the transcript is kept."
        case .preparing: "Creating the audio file…"
        case .retaining: "Recording audio as it is captured."
        case .retained: "Saved and closed."
        case .failed: "Not being recorded."
        }
    }

    /// What the selected mode will actually write, said in terms of the file
    /// the user will find in the folder.
    private var audioRetentionExplanation: String {
        switch audioRetention {
        case .none:
            "Only the transcript is kept. No audio is written to disk."
        case .raw:
            "audio.caf is written beside the transcript as the meeting runs, in the audio exactly as it "
            + "was captured. It is large: roughly 690 MB an hour. The file stays on this Mac."
        case .compressed:
            "audio.m4a is written beside the transcript as the meeting runs, encoded as AAC at "
            + "64 kbit/s — roughly 31 MB an hour. The file stays on this Mac."
        }
    }

    private var destinationSection: some View {
        Section("Save Location") {
            LabeledContent("Folder") {
                Text(destination.pathDescription)
                    .foregroundStyle(destination.url == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .accessibilityLabel("Save location")
            .accessibilityValue(destination.statusDescription)

            if let warning = destination.warningMessage {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            HStack {
                Button(destination.url == nil ? "Choose Folder…" : "Change Folder…") {
                    isChoosingDestination = true
                }
                .disabled(runtime.isRunning)
                .accessibilityHint("Choose where transcripts are saved")

                Button("Forget Folder") { destination.clear() }
                    .disabled(!destination.canClear || runtime.isRunning)
                    .accessibilityHint("Stop remembering the saved folder")

                if destination.warningMessage != nil {
                    Button("Try Again") { destination.restore() }
                        .disabled(runtime.isRunning)
                        .accessibilityHint("Resolve the remembered folder again, for a disk that has come back")
                }
            }

            Text(destination.isRestored
                 ? "Restored from your last launch. Each meeting is written to its own dated folder here."
                 : "Each meeting is written to its own dated folder here.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text(meetingStatusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            if runtime.canResume {
                Button("Resume") {
                    Task { await runtime.resume() }
                }
                .accessibilityHint("Capture the same applications again and continue this meeting")
            } else {
                Button("Pause") {
                    Task { await runtime.pause() }
                }
                .disabled(!runtime.canPause)
                .accessibilityHint("Stop capturing without ending the meeting")
            }

            Button("Stop") {
                Task { await runtime.stop() }
            }
            .disabled(!runtime.canStop)
            .accessibilityHint("Stop capturing, finish the transcript and close it")

            Button("Start Meeting") {
                guard let request = startRequest else { return }
                Task { await runtime.start(request) }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!readiness.canStart || !runtime.canStart(startRequest))
            .help(readiness.startExplanation)
            .accessibilityHint(readiness.startExplanation)
        }
    }

    /// One sentence describing the meeting as a whole, derived from the
    /// subsystems rather than tracked separately.
    private var meetingStatusDescription: String {
        if !runtime.isRunning, let outcome = runtime.outcome { return outcome.headline }
        if let message = runtime.persistenceState.failureMessage { return message }
        if let message = runtime.audioRetentionState.failureMessage { return message }
        if let message = runtime.pauseFailureMessage { return message }
        if runtime.canResume {
            return "Meeting paused. Nothing is being captured; the transcript and any recording stay open until "
                + "you resume or stop."
        }
        if runtime.isRunning {
            return "Meeting in progress. It keeps running if you hide or close this window; the menu bar item "
                + "shows it and can stop it."
        }
        return readiness.startExplanation
    }
}

/// The running meeting's name and how long it has been running.
///
/// A view of its own because ``MeetingElapsedClock`` advances once a second.
/// Read inside ``MeetingSetupView``'s own body, that tick would invalidate the
/// whole setup form — every section, the transcript list included — once a
/// second for the length of the meeting. Read here, it invalidates one label.
private struct RunningMeetingLabel: View {

    /// The meeting being watched.
    let runtime: MeetingRuntime

    var body: some View {
        if let meeting = runtime.meeting, runtime.status.isActive {
            LabeledContent("Running") {
                Text("\(meeting.title) · \(MeetingElapsedClock.description(of: runtime.elapsed.elapsed))")
                    .monospacedDigit()
            }
            .accessibilityLabel("Running meeting")
            .accessibilityValue("\(meeting.title), running for "
                                + MeetingElapsedClock.description(of: runtime.elapsed.elapsed))

            Text("Settings on this screen apply to the next meeting. This one keeps what it started with.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// What capture has delivered so far.
///
/// A view of its own for the same reason as ``RunningMeetingLabel``: the
/// activity summary is published twice a second for the length of a meeting,
/// and it is one line of text.
private struct CaptureActivityLabel: View {

    /// The meeting being watched.
    let runtime: MeetingRuntime

    var body: some View {
        if let description {
            Text(description)
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("Captured audio: \(description)")
        }
    }

    /// What capture has delivered so far, or `nil` before anything arrives.
    ///
    /// The figures are aggregates published a few times a second; no audio is
    /// drawn, played back or retained.
    private var description: String? {
        let activity = runtime.activity
        guard activity.sampleCount > 0 || activity.unreadableSampleCount > 0 else { return nil }
        var parts = ["\(activity.sampleCount) buffers"]
        if let seconds = activity.capturedDuration {
            parts.append(String(format: "%.1f s", seconds))
        }
        if let format = activity.format {
            parts.append(format.summary)
        }
        if let peak = activity.peakAmplitude {
            parts.append(String(format: "peak %.0f%%", min(peak, 1) * 100))
        }
        if activity.unreadableSampleCount > 0 {
            parts.append("\(activity.unreadableSampleCount) unreadable")
        }
        return parts.joined(separator: " · ")
    }
}

/// The live transcript: finalised spans, then the hypothesis for what is being
/// said now.
///
/// Finalised segments are rendered lazily, because a long meeting produces many
/// of them, and the partial is one row that is replaced rather than appended.
///
/// It is a view of its own because the recogniser replaces the partial several
/// times a second. Every one of those replacements invalidates whatever body
/// read it, so reading it here keeps the churn inside this section instead of
/// rebuilding the entire setup form — its pickers, its source list and its
/// status sections — at recognition rate.
private struct LiveTranscriptSection: View {

    /// The meeting being watched.
    let runtime: MeetingRuntime

    var body: some View {
        Section("Live Transcript") {
            if runtime.transcript.isEmpty {
                Text(runtime.transcriptionState == .transcribing
                     ? "Listening…"
                     : "Nothing transcribed yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(runtime.transcript.finalizedSegments) { segment in
                            row(for: segment)
                        }
                        if let partial = runtime.transcript.partialSegment {
                            Text(partial.displayText)
                                .foregroundStyle(.secondary)
                                .italic()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("In progress: \(partial.displayText)")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .defaultScrollAnchor(.bottom)
                .frame(minHeight: 160, maxHeight: 320)
            }

            if runtime.transcript.untranscribedSeconds > 0 {
                Label(
                    String(
                        format: "%.1f s of audio was not transcribed, so the transcript has gaps.",
                        runtime.transcript.untranscribedSeconds
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Text("Text in grey is a live guess, is replaced as you speak and is never saved. "
                 + "Only finalised speech is written to the transcript.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// One finalised span, with the time it began measured from the start of
    /// the run.
    ///
    /// - Parameter segment: The span to present.
    /// - Returns: The row view.
    private func row(for segment: TranscriptSegment) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.offset(segment.startTime))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(segment.displayText)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Formats a time measured from the start of the run.
    ///
    /// - Parameter seconds: Seconds since the first captured frame.
    /// - Returns: A `mm:ss` string.
    private static func offset(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

#Preview {
    MeetingSetupView(runtime: MeetingRuntime())
}
