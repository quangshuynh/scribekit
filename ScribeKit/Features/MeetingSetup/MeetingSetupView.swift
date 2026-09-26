//
//  MeetingSetupView.swift
//  ScribeKit
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The screen that configures a meeting and shows the one that is running.
///
/// The screen collects the settings a session needs — title, where the audio
/// comes from (the selected applications or the microphone), audio retention
/// and save location — and displays the meeting: capture, on-device
/// recognition and a timestamped Markdown transcript written to the chosen
/// folder while the meeting is under way.
///
/// It does not own the meeting. ``MeetingRuntime`` is handed in and belongs to
/// the application, so this screen can be closed, hidden or built again
/// without starting, stopping or duplicating anything. What the screen does
/// own is the configuration for the *next* meeting, which is exactly the state
/// that should disappear with it.
struct MeetingSetupView: View {
    /// The application's meeting owner, shared with the menu bar.
    let runtime: MeetingRuntime

    /// The application's diagnostics owner. This screen is the only place that
    /// derives readiness, the save location's standing and what the last
    /// recovery scan found, so it publishes them where a report can still read
    /// them after the window has closed.
    let diagnostics: MeetingDiagnostics

    @State private var sources: MeetingSetupSourcesModel
    @State private var microphone: MeetingSetupMicrophoneModel
    @State private var captureMode: CaptureMode
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
    ///   - diagnostics: The application's diagnostics owner.
    ///   - sourceProvider: Discovery used to populate the application list. The
    ///     default talks to ScreenCaptureKit; previews and tests can substitute
    ///     their own.
    ///   - microphoneAccess: The system's answers about the microphone. The
    ///     default asks macOS, without prompting until the user starts a
    ///     Microphone meeting or asks to allow access.
    ///   - saveLocation: Storage for the chosen save folder. The default keeps
    ///     a security-scoped bookmark in the local preference store.
    ///   - preferences: Store for the setup choices remembered between
    ///     launches.
    init(
        runtime: MeetingRuntime,
        diagnostics: MeetingDiagnostics,
        sourceProvider: CaptureSourceProviding = ScreenCaptureKitSourceProvider(),
        microphoneAccess: any MicrophoneAccessProviding = SystemMicrophoneAccess(),
        saveLocation: SaveLocationPersisting = SecurityScopedSaveLocationStore(),
        preferences: MeetingSetupPreferencesStoring = UserDefaultsMeetingSetupPreferences()
    ) {
        self.runtime = runtime
        self.diagnostics = diagnostics
        self.preferences = preferences
        _sources = State(initialValue: MeetingSetupSourcesModel(provider: sourceProvider, preferences: preferences))
        _microphone = State(initialValue: MeetingSetupMicrophoneModel(access: microphoneAccess, preferences: preferences))
        // A running meeting's mode wins over the remembered one, so a window
        // rebuilt during a meeting shows the meeting it is watching.
        _captureMode = State(initialValue: runtime.isRunning
            ? runtime.meeting?.captureMode ?? preferences.captureMode
            : preferences.captureMode)
        _destination = State(initialValue: MeetingSetupDestinationModel(persistence: saveLocation))
        _audioRetention = State(initialValue: preferences.audioRetention)
    }

    var body: some View {
        Group {
            switch layout {
            case .setup: setup
            case .session: MeetingSessionView(runtime: runtime, diagnostics: diagnostics)
            }
        }
        .task {
            destination.restore()
            await checkForUnfinishedSessions()
            await runtime.prepare()
            await refreshCaptureSource()
        }
        .task(id: captureMode) {
            // Core Audio is listened to only while the Microphone section is
            // on screen, and the task ends with the screen.
            guard captureMode == .microphone else { return }
            await microphone.observeInputChanges()
        }
        .onChange(of: audioRetention) { _, mode in
            preferences.audioRetention = mode
        }
        .onChange(of: captureMode) { _, mode in
            preferences.captureMode = mode
            Task { await refreshCaptureSource(onlyIfUnchecked: true) }
        }
        .onChange(of: setupDiagnostics, initial: true) { _, state in
            diagnostics.publish(state)
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

    /// Which arrangement the screen shows, derived from the runtime.
    private var layout: MeetingScreenLayout {
        MeetingScreenLayout(isRunning: runtime.isRunning, outcome: runtime.outcome?.category)
    }


    /// The form that configures the next meeting, in the order the choices
    /// are made: where the audio comes from, anything that still stops a
    /// start, the meeting itself, then where its files go.
    private var setup: some View {
        VStack(spacing: 0) {
            Form {
                lastAttemptSection
                sourceSection
                readinessSection
                if recovery.isVisible { recoverySection }
                meetingSection
                if captureMode == .applications { audioRetentionSection }
                destinationSection
            }
            .formStyle(.grouped)
            .frame(maxWidth: LayoutMetrics.formMaxWidth)
            .frame(maxWidth: .infinity)

            Divider()

            footer
                .frame(maxWidth: LayoutMetrics.formMaxWidth - 2 * Spacing.xLarge)
                .padding(.horizontal, Spacing.xLarge)
                .padding(.vertical, Spacing.medium)
                .frame(maxWidth: .infinity)
        }
    }

    /// Reads what the chosen capture mode needs: the application list for App
    /// Audio, the microphone's permission and input for Microphone.
    ///
    /// Only the chosen mode is asked about. Listing applications is what makes
    /// macOS ask for Screen & System Audio Recording, and a Microphone meeting
    /// does not need it; reading the microphone's state never prompts at all.
    ///
    /// - Parameter onlyIfUnchecked: Leave a mode that has already been read
    ///   alone, for a switch between modes rather than a screen appearing.
    private func refreshCaptureSource(onlyIfUnchecked: Bool = false) async {
        switch captureMode {
        case .applications:
            guard !onlyIfUnchecked || sources.discoveryState == .idle else { return }
            await sources.refresh()
        case .microphone:
            guard !onlyIfUnchecked || microphone.readiness == .notChecked else { return }
            microphone.refresh()
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

    // MARK: - Last attempt

    /// A start that failed, reported where it can be corrected.
    ///
    /// A meeting that captured something is shown as a finished session with
    /// its transcript. One that never started has nothing to show but the
    /// reason, and the reason is usually a setting on this form, so it is
    /// stated at the top of it. A failure the runtime reports before a meeting
    /// is recorded at all — a capture that could not be prepared — is stated
    /// the same way.
    @ViewBuilder
    private var lastAttemptSection: some View {
        if let outcome = runtime.outcome, outcome.category == .startFailure {
            Section {
                NoticeView(
                    tone: .critical,
                    symbolName: "exclamationmark.triangle",
                    title: outcome.headline,
                    message: [outcome.meaning, outcome.nextStep, outcome.detail]
                        .compactMap { $0 }
                        .joined(separator: " ")
                ) {
                    HStack(spacing: Spacing.small) {
                        if let layout = runtime.persistenceState.layout {
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([layout.transcriptURL])
                            }
                            .accessibilityHint("Reveal this meeting's transcript in the Finder")
                        }
                        Button("Dismiss") { runtime.dismissOutcome() }
                            .accessibilityHint("Hide this summary; nothing on disk changes")
                        // Secondary, and deliberately last: the sentences above
                        // already say what happened and what to do.
                        Button("Export Diagnostics…") { diagnostics.export() }
                            .accessibilityHint(
                                "Save a technical report about this Mac and this meeting. "
                                    + "It contains no transcript text or audio."
                            )
                    }
                }
                .accessibilityLabel("Last meeting")
                .accessibilityValue(outcome.accessibilityDescription)
            }
        } else if runtime.outcome == nil, let message = runtime.status.failureMessage {
            Section {
                NoticeView(
                    tone: .critical,
                    symbolName: "exclamationmark.triangle",
                    title: "The meeting did not start",
                    message: message
                )
            }
        }
    }

    // MARK: - Source

    /// Where the next meeting's audio comes from, and exactly what that is.
    ///
    /// The mode and the source it selects are one section, so App Audio and
    /// Microphone read as two answers to one question rather than two forms.
    /// The mode is fixed while a meeting runs; this form is not shown then.
    private var sourceSection: some View {
        Section {
            captureModePicker

            switch captureMode {
            case .applications: applicationRows
            case .microphone: microphoneRows
            }
        } header: {
            HStack {
                Text("Source")
                Spacer()
                if captureMode == .applications {
                    Button {
                        Task { await sources.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .labelStyle(.titleAndIcon)
                    .controlSize(.small)
                    .disabled(sources.isDiscovering)
                    .accessibilityHint("Look for running applications again")
                }
            }
        } footer: {
            Text(sourceExplanation)
                .textRole(.secondaryBody)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The choice between App Audio and Microphone.
    private var captureModePicker: some View {
        Picker("Transcribe from", selection: $captureMode) {
            ForEach(CaptureMode.allCases) { mode in
                Text(mode.displayName).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .disabled(runtime.isRunning)
        .accessibilityLabel("Transcribe from")
        .accessibilityHint(
            "Choose whether the next meeting transcribes the selected applications or the microphone"
        )
    }

    /// What the chosen mode listens to, and what it keeps.
    private var sourceExplanation: String {
        switch captureMode {
        case .applications:
            "App Audio transcribes the sound the applications you select are playing."
        case .microphone:
            "Microphone transcribes what the Mac's microphone hears, while you use any other app. "
            + "ScribeKit listens to the input chosen here only while a Microphone meeting runs and leaves "
            + "the Mac's own input setting alone; System Default means the Mac's input when the meeting "
            + "starts. A meeting keeps its microphone until it ends — if that microphone is disconnected, "
            + "the meeting ends and its transcript is kept. No audio is saved and nothing is sent anywhere."
        }
    }

    /// The applications App Audio can capture, each with a checkbox.
    @ViewBuilder
    private var applicationRows: some View {
        switch sources.discoveryState {
        case .idle, .loading:
            HStack(spacing: Spacing.small) {
                ProgressView().controlSize(.small)
                Text("Looking for applications…")
                    .textRole(.secondaryBody)
            }
        case let .loaded(discovered) where discovered.isEmpty:
            Text("No applications are available to capture.")
                .textRole(.secondaryBody)
        case let .loaded(discovered):
            ForEach(discovered) { source in
                sourceRow(for: source)
            }
            selectionSummary
        case let .accessUnavailable(message):
            StatusBadge(title: message, symbolName: "lock", tone: .warning, role: .secondaryBody)
                .accessibilityLabel("Screen and System Audio Recording access unavailable. \(message)")
        case let .failed(message):
            StatusBadge(title: message, symbolName: "exclamationmark.triangle", tone: .warning, role: .secondaryBody)
                .accessibilityLabel("Application discovery failed. \(message)")
        }

        if !sources.unavailableSelectionNames.isEmpty {
            StatusBadge(
                title: "No longer running, so removed from your selection: "
                    + sources.unavailableSelectionNames.formatted(.list(type: .and)),
                symbolName: "info.circle",
                tone: .attention,
                role: .secondaryBody
            )
        }
    }

    /// A selectable row for one discovered application.
    ///
    /// A checkbox carries the selection state, so it is exposed to
    /// accessibility and visible without relying on colour. The application's
    /// own icon makes the list scannable the way the Dock and the Finder are.
    ///
    /// - Parameter source: The application to present.
    /// - Returns: The row view.
    private func sourceRow(for source: CaptureSource) -> some View {
        Toggle(isOn: Binding(
            get: { sources.isSelected(source) },
            set: { sources.setSelection($0, for: source) }
        )) {
            HStack(spacing: Spacing.small) {
                ApplicationIcon(source: source)
                Text(source.displayName)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(runtime.isRunning)
        .accessibilityLabel(source.displayName)
        .accessibilityHint("Include this application as a meeting audio source")
    }

    private var selectionSummary: some View {
        Text(sources.selectedSources.isEmpty
             ? "No applications selected."
             : "\(sources.selectedSources.count) selected: "
               + sources.selectedSources.map(\.displayName).formatted(.list(type: .and)))
            .textRole(.metadata)
    }

    /// The microphone a Microphone meeting listens to, and whether it may.
    ///
    /// The picker lists the inputs the Mac offers now, with System Default
    /// first and named for the device it stands for. A remembered device that
    /// is not connected stays in the list, marked as such and not selectable
    /// again, so the fallback to System Default is visible rather than silent.
    @ViewBuilder
    private var microphoneRows: some View {
        microphonePicker

        LabeledContent("Access") {
            StatusBadge(
                title: microphoneAccessDescription,
                symbolName: microphoneAccessSymbol,
                tone: microphoneAccessTone,
                role: .body
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Microphone access")
        .accessibilityValue(microphoneAccessDescription)
    }

    /// The choice of input for the next Microphone meeting.
    @ViewBuilder
    private var microphonePicker: some View {
        if microphone.readiness == .notChecked {
            LabeledContent("Input") {
                Text("Checking…")
                    .textRole(.secondaryBody)
            }
        } else {
            Picker("Input", selection: Binding(
                get: { microphone.selection.pickerID },
                set: { id in
                    if let option = microphoneOptions.first(where: { $0.selection.pickerID == id }) {
                        microphone.select(option.selection)
                    }
                }
            )) {
                ForEach(microphoneOptions, id: \.selection.pickerID) { option in
                    Text(option.label)
                        .tag(option.selection.pickerID)
                        .selectionDisabled(!option.isAvailable)
                }
            }
            .disabled(runtime.isRunning)
            .accessibilityLabel("Microphone input")
            .accessibilityHint("Choose the microphone the next meeting listens to. The Mac's own setting is unchanged.")
        }
    }

    /// The rows the microphone picker offers.
    ///
    /// System Default, each connected input, and — only when the remembered
    /// choice is not connected — that choice, so the picker still shows what
    /// was selected.
    private var microphoneOptions: [(selection: MicrophoneSelection, label: String, isAvailable: Bool)] {
        let defaultName = microphone.catalog.defaultInput?.name
        var options: [(selection: MicrophoneSelection, label: String, isAvailable: Bool)] = [(
            .systemDefault,
            defaultName.map { "System Default — \($0)" } ?? "System Default (no input)",
            true
        )]
        options += microphone.catalog.devices.map { (.device($0), $0.name, true) }
        if let missing = microphone.choice?.unavailableSelection {
            options.append((.device(missing), "\(missing.name) (not connected)", false))
        }
        return options
    }

    /// What macOS says about microphone access, in words.
    private var microphoneAccessDescription: String {
        switch microphone.authorization {
        case nil: "Checking…"
        case .notDetermined?: "Not asked yet. macOS asks when you start."
        case .authorized?: "Allowed"
        case .denied?: "Turned off in System Settings › Privacy & Security › Microphone."
        case .restricted?: "Restricted on this Mac."
        }
    }

    /// The symbol drawn beside ``microphoneAccessDescription``.
    private var microphoneAccessSymbol: String {
        switch microphone.authorization {
        case nil, .notDetermined?: "questionmark.circle"
        case .authorized?: "checkmark.circle"
        case .denied?, .restricted?: "exclamationmark.triangle"
        }
    }

    /// The tone of ``microphoneAccessDescription``.
    private var microphoneAccessTone: StatusTone {
        switch microphone.authorization {
        case nil, .notDetermined?: .neutral
        case .authorized?: .positive
        case .denied?, .restricted?: .warning
        }
    }

    // MARK: - Readiness

    /// Whether a meeting can be started right now, and why not when it cannot.
    ///
    /// Derived here and read by every control that depends on it, so the
    /// readiness rows, the Start button's availability and the sentence beside
    /// it are three renderings of one answer rather than three checks that can
    /// disagree.
    private var readiness: MeetingStartReadiness {
        switch captureMode {
        case .applications:
            MeetingStartReadiness(
                saveLocation: destination.readiness,
                captureSources: sources.readiness,
                speech: runtime.availability,
                meetingIsActive: runtime.isRunning
            )
        case .microphone:
            MeetingStartReadiness(
                saveLocation: destination.readiness,
                microphone: microphone.readiness,
                speech: runtime.availability,
                meetingIsActive: runtime.isRunning
            )
        }
    }

    /// Everything a diagnostic report needs from this screen, as one value so
    /// that publishing it is a single comparison rather than four.
    private var setupDiagnostics: MeetingDiagnostics.SetupState {
        MeetingDiagnostics.SetupState(
            readiness: readiness,
            saveLocation: destination.readiness,
            sources: sources.readiness,
            recovery: recovery.state
        )
    }

    /// The prerequisites that still need something, in one place.
    ///
    /// Only rows that are not yet satisfied are listed: a prerequisite that is
    /// met is stated where it is configured — the folder in Save Location, the
    /// input in Source — and by the footer saying the meeting is ready. When
    /// everything is met the section is not shown at all. Each row states its
    /// status in words as well as an icon, so nothing depends on colour.
    @ViewBuilder
    private var readinessSection: some View {
        let rows = readiness.rows.filter { $0.status != .satisfied }
        if !rows.isEmpty {
            Section("Before You Start") {
                ForEach(rows) { row in
                    readinessRow(row)
                }
            }
        }
    }

    /// One prerequisite, with the action that resolves it when there is one.
    ///
    /// - Parameter row: The prerequisite to present.
    /// - Returns: The row view.
    @ViewBuilder
    private func readinessRow(_ row: MeetingStartReadiness.Row) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: row.status.symbolName)
                .foregroundStyle(row.status.tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(row.title)
                        .textRole(.emphasizedBody)
                    Text(row.status.label)
                        .textRole(.metadata)
                }
                Text(row.detail)
                    .textRole(.secondaryBody)
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
                switch row.captureMode {
                case .applications:
                    Button("Refresh") { Task { await sources.refresh() } }
                        .disabled(sources.isDiscovering)
                        .accessibilityHint("Look for applications ScribeKit can record again")
                case .microphone:
                    microphoneAction(for: row.prerequisite)
                }
            case .speechRecognition:
                Button("Check Again") { Task { await runtime.prepare() } }
                    .disabled(runtime.isRunning)
                    .accessibilityHint("Check which speech models are installed again")
            }
        }
    }

    /// The control that resolves a microphone prerequisite.
    ///
    /// Asking for access is offered only while macOS has never been asked,
    /// because that is the only time it would show a prompt. After a refusal
    /// the answer lives in System Settings, which the row names, and Check
    /// Again reads it back.
    ///
    /// - Parameter prerequisite: The microphone prerequisite being presented.
    /// - Returns: A button.
    @ViewBuilder
    private func microphoneAction(for prerequisite: MeetingStartReadiness.Prerequisite) -> some View {
        if prerequisite == .captureAccess, microphone.authorization == .notDetermined {
            Button("Allow Microphone Access…") { Task { await microphone.requestAccess() } }
                .disabled(runtime.isRunning || microphone.isRequestingAccess)
                .accessibilityHint("Ask macOS to let ScribeKit use the microphone for Microphone meetings")
        } else {
            Button("Check Again") { microphone.refresh() }
                .disabled(runtime.isRunning)
                .accessibilityHint("Read microphone access and the Mac's sound inputs again")
        }
    }

    // MARK: - Recovery

    /// What ScribeKit found from a previous launch, and the two things the
    /// user can do about it.
    ///
    /// Neither action resumes anything. The transcript is already on disk with
    /// everything that reached it; recovery's job is to say so, confirm it is
    /// readable, and close the record honestly.
    @ViewBuilder
    private var recoverySection: some View {
        Section {
            if case .checking = recovery.state {
                HStack(spacing: Spacing.small) {
                    ProgressView().controlSize(.small)
                    Text("Checking the save folder…")
                        .textRole(.secondaryBody)
                }
            }

            if case let .unavailable(message) = recovery.state {
                StatusBadge(title: message, symbolName: "exclamationmark.triangle", tone: .warning,
                            role: .secondaryBody)
                    .accessibilityLabel("Unfinished meeting check failed. \(message)")
            }

            ForEach(recovery.candidates) { candidate in
                candidateRow(for: candidate)
            }

            ForEach(recovery.problems) { problem in
                StatusBadge(
                    title: "\(problem.name): \(problem.error.errorDescription ?? "")",
                    symbolName: "exclamationmark.triangle",
                    tone: .warning,
                    role: .secondaryBody
                )
                .accessibilityLabel("Damaged session record. \(problem.name). "
                                    + (problem.error.errorDescription ?? ""))
            }

            if let message = recovery.actionMessage {
                Text(message)
                    .textRole(.secondaryBody)
            }
        } header: {
            Text("Previous Meetings")
        } footer: {
            if recovery.hasFindings {
                Text("ScribeKit does not resume a meeting it did not finish. "
                     + "Nothing is recorded again, and no transcript is deleted or rewritten.")
                    .textRole(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
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
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            StatusBadge(
                title: "\(candidate.metadata.title) did not finish",
                symbolName: HistorySessionStatus.interrupted.symbolName,
                tone: .warning,
                role: .groupTitle
            )
            Text("Started \(candidate.metadata.startedAt.formatted(date: .abbreviated, time: .shortened))")
                .textRole(.metadata)
            if candidate.metadata.wasPausedWhenInterrupted, let pausedAt = candidate.metadata.pausedAt {
                Text("This meeting was paused at "
                     + "\(pausedAt.formatted(date: .omitted, time: .standard)) and ScribeKit stopped before it "
                     + "was resumed or finished. Nothing was captured after the pause.")
                    .textRole(.secondaryBody)
            }
            if let modified = candidate.transcript.modifiedAt {
                Text("Transcript last written \(modified.formatted(date: .abbreviated, time: .shortened))"
                     + " · \(candidate.transcript.byteCount) bytes")
                    .textRole(.secondaryBody)
            }
            if let audio = candidate.retainedAudio, let url = candidate.retainedAudioURL {
                Text("Audio \(url.lastPathComponent) · \(audio.byteCount) bytes. "
                     + "It was still being written, so whether it plays depends on how far it got.")
                    .textRole(.secondaryBody)
            }
            Text(DisplayPath.abbreviated(candidate.transcriptURL))
                .textRole(.technical)
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: Spacing.small) {
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
            .padding(.top, Spacing.xSmall)

            if !runtime.allowsRecovery {
                Text("Available once the current meeting has finished.")
                    .textRole(.secondaryBody)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Meeting

    /// What the next meeting is called and which language it is recognised in.
    ///
    /// Both are copied when the meeting starts and fixed for its run, so they
    /// configure the next meeting and never the one that is running.
    private var meetingSection: some View {
        Section("Meeting") {
            TextField("Title", text: $title, prompt: Text(MeetingSession.untitledPlaceholder))
                .disabled(runtime.isRunning)
                .accessibilityLabel("Meeting title")

            localePicker
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
                    .textRole(.secondaryBody)
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
                    .textRole(.secondaryBody)
            }

            if !runtime.availability.canTranscribe {
                Button("Check Again") { Task { await runtime.prepare() } }
                    .disabled(runtime.isRunning)
                    .accessibilityHint("Check which speech models are installed again")
            }
        }
    }

    // MARK: - Audio retention

    /// What an App Audio meeting keeps of its audio.
    ///
    /// The choice is fixed for a run. A Microphone meeting keeps no audio
    /// whatever this says, so the section is shown for App Audio only.
    private var audioRetentionSection: some View {
        Section {
            Picker("Keep audio", selection: $audioRetention) {
                ForEach(AudioRetentionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .disabled(runtime.isRunning)
            .accessibilityLabel("Audio retention mode")
        } header: {
            Text("Recording")
        } footer: {
            Text(audioRetentionExplanation)
                .textRole(.secondaryBody)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Save location

    private var destinationSection: some View {
        Section {
            LabeledContent("Folder") {
                VStack(alignment: .trailing, spacing: Spacing.hairline) {
                    Text(destination.url?.lastPathComponent ?? destination.pathDescription)
                        .foregroundStyle(destination.url == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let url = destination.url {
                        Text(DisplayPath.abbreviated(url.deletingLastPathComponent()))
                            .textRole(.technical)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Save location")
            .accessibilityValue(destination.statusDescription)

            if let warning = destination.warningMessage {
                StatusBadge(title: warning, symbolName: "exclamationmark.triangle", tone: .warning,
                            role: .secondaryBody)
                    .accessibilityHidden(true)
            }

            HStack(spacing: Spacing.small) {
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
        } header: {
            Text("Save Location")
        } footer: {
            Text(destination.isRestored
                 ? "Restored from your last launch. Each meeting is written to its own dated folder here."
                 : "Each meeting is written to its own dated folder here.")
                .textRole(.secondaryBody)
        }
    }

    // MARK: - Footer

    /// Whether the meeting can start, and the button that starts it.
    ///
    /// Pause and Stop are not here: nothing is running while this form is on
    /// screen, and they live with the meeting they act on.
    private var footer: some View {
        HStack(spacing: Spacing.medium) {
            footerStatus
                .frame(maxWidth: .infinity, alignment: .leading)

            Button("Start Meeting") {
                guard let request = startRequest else { return }
                Task { await runtime.start(request) }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            .disabled(!readiness.canStart || !runtime.canStart(startRequest))
            .help(readiness.startExplanation)
            .accessibilityHint(readiness.startExplanation)
        }
    }

    /// The sentence beside Start: what it will do, or what is in the way.
    private var footerStatus: some View {
        let canStart = readiness.canStart && runtime.canStart(startRequest)
        return StatusBadge(
            title: readiness.startExplanation,
            symbolName: canStart ? "checkmark.circle" : "exclamationmark.circle",
            tone: canStart ? .positive : .neutral,
            role: .secondaryBody
        )
        .fixedSize(horizontal: false, vertical: true)
    }

    /// What the meeting would start with, or `nil` when it could not start.
    ///
    /// A Microphone meeting captures the one input the screen last read and
    /// keeps no audio, whatever the App Audio retention setting says: that
    /// setting belongs to App Audio meetings and is not shown for this one.
    private var startRequest: MeetingStartRequest? {
        guard let url = destination.url else { return nil }
        switch captureMode {
        case .applications:
            return MeetingStartRequest(
                title: title,
                sources: sources.selectedSources,
                destination: url,
                audioRetention: audioRetention
            )
        case .microphone:
            return MeetingStartRequest(
                title: title,
                sources: microphone.source.map { [$0] } ?? [],
                destination: url,
                audioRetention: .none
            )
        }
    }
}

/// An application's own icon, or a symbol for a source that is not an
/// application.
///
/// The icon is looked up once per row from the application's bundle identifier
/// and drawn at list-row size. A source whose application cannot be found is
/// given a generic symbol rather than no image, so the list stays aligned.
private struct ApplicationIcon: View {

    /// The source to draw.
    let source: CaptureSource

    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 18

    var body: some View {
        Group {
            if source.kind == .application,
               let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.id) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path(percentEncoded: false)))
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: source.kind == .systemAudio ? "speaker.wave.2" : "app.dashed")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    let runtime = MeetingRuntime()
    MeetingSetupView(runtime: runtime, diagnostics: MeetingDiagnostics(runtime: runtime))
}
