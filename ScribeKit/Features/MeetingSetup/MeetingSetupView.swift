//
//  MeetingSetupView.swift
//  ScribeKit
//

import SwiftUI
import UniformTypeIdentifiers

/// The configuration screen shown before a meeting starts.
///
/// The screen collects the settings a session needs — title, audio sources,
/// audio retention and save location — and can capture and transcribe the
/// selected applications live. Starting a *meeting* would imply a written
/// transcript, which is not implemented, so that control stays deliberately
/// unavailable rather than simulated.
struct MeetingSetupView: View {
    /// Whether a meeting can be started.
    ///
    /// Fixed to `false` until transcript writing exists. Live capture and
    /// transcription are offered under their own control, so nothing here
    /// claims a session that ScribeKit cannot yet complete.
    private static let isStartAvailable = false

    @State private var sources: MeetingSetupSourcesModel
    @State private var destination: MeetingSetupDestinationModel
    @State private var capture = MeetingSetupCaptureModel()
    @State private var title = ""
    @State private var audioRetention: AudioRetentionMode
    @State private var isChoosingDestination = false

    private let preferences: MeetingSetupPreferencesStoring

    /// Creates the setup screen.
    ///
    /// - Parameters:
    ///   - sourceProvider: Discovery used to populate the application list. The
    ///     default talks to ScreenCaptureKit; previews and tests can substitute
    ///     their own.
    ///   - saveLocation: Storage for the chosen save folder. The default keeps
    ///     a security-scoped bookmark in the local preference store.
    ///   - preferences: Store for the setup choices remembered between
    ///     launches.
    init(
        sourceProvider: CaptureSourceProviding = ScreenCaptureKitSourceProvider(),
        saveLocation: SaveLocationPersisting = SecurityScopedSaveLocationStore(),
        preferences: MeetingSetupPreferencesStoring = UserDefaultsMeetingSetupPreferences()
    ) {
        self.preferences = preferences
        _sources = State(initialValue: MeetingSetupSourcesModel(provider: sourceProvider, preferences: preferences))
        _destination = State(initialValue: MeetingSetupDestinationModel(persistence: saveLocation))
        _audioRetention = State(initialValue: preferences.audioRetention)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Form {
                meetingSection
                sourcesSection
                captureSection
                transcriptSection
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
            await capture.prepare()
            await sources.refresh()
        }
        .onDisappear {
            Task { await capture.stop() }
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

    private var meetingSection: some View {
        Section("Meeting") {
            TextField("Title", text: $title, prompt: Text(MeetingSession.untitledPlaceholder))
                .accessibilityLabel("Meeting title")
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
                    .foregroundStyle(capture.captureState == .idle ? .secondary : .primary)
            }
            .accessibilityLabel("Capture status")
            .accessibilityValue(captureStatusDescription)

            if case let .failed(message) = capture.captureState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            LabeledContent("Recognition") {
                Text(recognitionStatusDescription)
                    .foregroundStyle(capture.transcriptionState == .idle ? .secondary : .primary)
            }
            .accessibilityLabel("Recognition status")
            .accessibilityValue(recognitionStatusDescription)

            if case let .failed(message) = capture.transcriptionState {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            localePicker

            HStack {
                Button("Start Transcribing") {
                    Task { await capture.start(sources: sources.selectedSources) }
                }
                .disabled(!capture.canStart(sources: sources.selectedSources))
                .accessibilityHint("Capture and transcribe audio from the selected applications")

                Button("Stop") {
                    Task { await capture.stop() }
                }
                .disabled(!capture.canStop)
                .accessibilityHint("Stop capturing and transcribing")
            }

            if let activity = captureActivityDescription {
                Text(activity)
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Captured audio: \(activity)")
            }

            Text("Speech is recognised on this Mac, using an installed language model. "
                 + "No audio leaves your machine, and nothing is written to disk.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The recognition language, chosen explicitly and fixed for a run.
    ///
    /// Only locales whose on-device model is installed can be selected;
    /// supported but uninstalled ones are listed and disabled, so the reason a
    /// language is unavailable is visible rather than implied by its absence.
    @ViewBuilder
    private var localePicker: some View {
        if capture.availableLocales.isEmpty {
            LabeledContent("Language") {
                Text("No recognition languages are available.")
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("Language", selection: Binding(
                get: { capture.localeIdentifier },
                set: { identifier in Task { await capture.selectLocale(identifier) } }
            )) {
                ForEach(capture.availableLocales) { locale in
                    Text(locale.isInstalled ? locale.displayName : "\(locale.displayName) (not installed)")
                        .tag(locale.id)
                }
            }
            .disabled(capture.isRunning)
            .accessibilityLabel("Recognition language")

            if let message = capture.availability.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// A short description of what capture is doing.
    private var captureStatusDescription: String {
        switch capture.captureState {
        case .idle: sources.selectedSources.isEmpty
            ? "Not capturing. Select at least one application."
            : "Not capturing. \(sources.selectedSources.count) application(s) selected."
        case .preparing: "Starting…"
        case .capturing: "Capturing \(sources.selectedSources.count) application(s)."
        case .stopping: "Stopping…"
        case .failed: "Capture failed."
        }
    }

    /// A short description of what recognition is doing.
    private var recognitionStatusDescription: String {
        switch capture.transcriptionState {
        case .idle: capture.availability.canTranscribe
            ? "Ready, on this Mac."
            : "Unavailable."
        case .preparing: "Preparing the recogniser…"
        case .transcribing: "Transcribing on device."
        case .recovering: "Recognition stopped; restarting…"
        case .stopping: "Finalising…"
        case .failed: "Recognition failed."
        }
    }

    /// What capture has delivered so far, or `nil` before anything arrives.
    ///
    /// The figures are aggregates published a few times a second; no audio is
    /// drawn, played back or retained.
    private var captureActivityDescription: String? {
        let activity = capture.activity
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

    /// The live transcript: finalised spans, then the hypothesis for what is
    /// being said now.
    ///
    /// Finalised segments are rendered lazily, because a long meeting produces
    /// many of them, and the partial is one row that is replaced rather than
    /// appended.
    private var transcriptSection: some View {
        Section("Live Transcript") {
            if capture.transcript.isEmpty {
                Text(capture.transcriptionState == .transcribing
                     ? "Listening…"
                     : "Nothing transcribed yet.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(capture.transcript.finalizedSegments) { segment in
                            transcriptRow(for: segment)
                        }
                        if let partial = capture.transcript.partialSegment {
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
                .frame(height: 160)
            }

            if capture.transcript.untranscribedSeconds > 0 {
                Label(
                    String(
                        format: "%.1f s of audio was not transcribed, so the transcript has gaps.",
                        capture.transcript.untranscribedSeconds
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Text("Text in grey is a live guess and is replaced as you speak. "
                 + "The transcript is not saved anywhere yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// One finalised span, with the time it began measured from the start of
    /// the run.
    ///
    /// - Parameter segment: The span to present.
    /// - Returns: The row view.
    private func transcriptRow(for segment: TranscriptSegment) -> some View {
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

    private var audioRetentionSection: some View {
        Section("Audio Retention") {
            Picker("Keep audio", selection: $audioRetention) {
                ForEach(AudioRetentionMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .accessibilityLabel("Audio retention mode")
            Text(audioRetention.retainsAudio
                 ? "An audio file is kept alongside the transcript."
                 : "Only the transcript is kept. No audio is written to disk.")
                .font(.footnote)
                .foregroundStyle(.secondary)
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
                .accessibilityHint("Choose where transcripts are saved")

                Button("Forget Folder") { destination.clear() }
                    .disabled(!destination.canClear)
                    .accessibilityHint("Stop remembering the saved folder")
            }

            Text(destination.isRestored
                 ? "Restored from your last launch. Nothing is written there yet; transcript files arrive in a later release."
                 : "Nothing is written there yet; transcript files arrive in a later release.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Text("Transcripts are not written to disk yet.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Start Meeting") {}
                .keyboardShortcut(.defaultAction)
                .disabled(!Self.isStartAvailable)
                .help("Starting a meeting is not available yet.")
        }
    }
}

#Preview {
    MeetingSetupView()
}
