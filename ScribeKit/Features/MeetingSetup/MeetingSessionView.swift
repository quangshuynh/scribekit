//
//  MeetingSessionView.swift
//  ScribeKit
//

import AppKit
import SwiftUI

/// The Meeting screen while a meeting runs, and after it ends until the user
/// moves on.
///
/// Three bands: a status header naming the meeting, what it is doing and for
/// how long, with the controls that change that; the transcript, which takes
/// every point of height the header and footer leave; and a footer saying
/// where the transcript is being written. The subsystem detail the setup form
/// used to list — capture and recognition states, audio format, buffer counts
/// — is one click away in Details rather than competing with the speech.
///
/// It observes the application's ``MeetingRuntime`` and owns nothing about the
/// meeting. The fast-changing values — the elapsed clock, the capture
/// activity summary, the partial hypothesis — are each read in a small view of
/// their own, so a tick invalidates a label rather than this whole screen.
struct MeetingSessionView: View {

    /// The application's meeting owner, shared with the menu bar.
    let runtime: MeetingRuntime

    /// The application's diagnostics owner, for the export a failed meeting
    /// offers.
    let diagnostics: MeetingDiagnostics

    @State private var isShowingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.large) {
                header
                notices
            }
            .readableColumn()
            .padding(.top, Spacing.xLarge)
            .padding(.bottom, Spacing.large)

            Divider()

            LiveTranscriptPanel(runtime: runtime)

            Divider()

            footer
                .readableColumn()
                .padding(.vertical, Spacing.small)
        }
    }

    // MARK: - Header

    /// The meeting, its state and its controls.
    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.large) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    StatusBadge(
                        title: sessionStatus.title,
                        symbolName: sessionStatus.symbolName,
                        tone: sessionStatus.tone,
                        role: .emphasizedBody
                    )
                    .accessibilityLabel("Meeting status")
                    .accessibilityValue(sessionStatus.title)
                    Text("·")
                        .textRole(.metadata)
                        .accessibilityHidden(true)
                    SessionElapsedText(runtime: runtime)
                }

                Text(runtime.meeting?.title ?? MeetingSession.untitledPlaceholder)
                    .textRole(.pageTitle)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .accessibilityAddTraits(.isHeader)

                if let meeting = runtime.meeting {
                    Label(sourceLine(for: meeting), systemImage: meeting.captureMode.symbolName)
                        .textRole(.metadata)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityLabel("Source")
                        .accessibilityValue(sourceLine(for: meeting))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            controls
                .padding(.top, Spacing.xSmall)
        }
    }

    /// Pause or Resume and Stop while the meeting runs; New Meeting once it
    /// has ended.
    ///
    /// Stop is drawn as an ordinary button with a stop symbol rather than a
    /// red one. It is always in the same place and always says what it does;
    /// a meeting is not an emergency, and a screen that is red for an hour
    /// stops meaning anything by being red.
    @ViewBuilder
    private var controls: some View {
        if runtime.isRunning {
            HStack(spacing: Spacing.small) {
                if runtime.canResume {
                    Button {
                        Task { await runtime.resume() }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                    }
                    .accessibilityHint(runtime.meeting?.captureMode == .microphone
                        ? "Listen to the same microphone again and continue this meeting"
                        : "Capture the same applications again and continue this meeting")
                } else {
                    Button {
                        Task { await runtime.pause() }
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                    }
                    .disabled(!runtime.canPause)
                    .accessibilityHint("Stop capturing without ending the meeting")
                }

                Button {
                    Task { await runtime.stop() }
                } label: {
                    Label {
                        Text("Stop")
                    } icon: {
                        Image(systemName: "stop.fill")
                            .foregroundStyle(runtime.canStop ? StatusTone.live.color : .secondary)
                    }
                }
                .disabled(!runtime.canStop)
                .accessibilityHint("Stop capturing, finish the transcript and close it")
            }
            .controlSize(.large)
            .labelStyle(.titleAndIcon)
        } else {
            Button("New Meeting") { runtime.dismissOutcome() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .accessibilityHint("Return to setup for the next meeting. Nothing on disk changes.")
        }
    }

    /// The meeting's source and recognition language, on one line.
    ///
    /// - Parameter meeting: The meeting.
    /// - Returns: The line, such as `Microphone · MacBook Air Microphone · English (United States)`.
    private func sourceLine(for meeting: MeetingSnapshot) -> String {
        var parts = [meeting.captureMode.displayName]
        let names = meeting.sources.map(\.displayName)
        if !names.isEmpty { parts.append(names.formatted(.list(type: .and))) }
        parts.append(languageName(for: meeting.localeIdentifier))
        return parts.joined(separator: " · ")
    }

    /// A recognition locale's name as the language picker shows it.
    ///
    /// - Parameter identifier: The locale identifier.
    /// - Returns: The display name, or the identifier when none is known.
    private func languageName(for identifier: String) -> String {
        runtime.availableLocales.first { $0.id == identifier }?.displayName
            ?? Locale.current.localizedString(forIdentifier: identifier)
            ?? identifier
    }

    private var sessionStatus: MeetingSessionStatus {
        MeetingSessionStatus(
            status: runtime.status,
            isRecovering: runtime.transcriptionState == .recovering,
            captureMode: runtime.meeting?.captureMode ?? .applications,
            outcome: runtime.outcome?.category
        )
    }

    // MARK: - Notices

    /// What the user needs to know that the status word cannot say: how the
    /// meeting ended, and a pause that did not take.
    @ViewBuilder
    private var notices: some View {
        if !runtime.isRunning, let outcome = runtime.outcome {
            NoticeView(
                tone: outcome.isFailure ? .critical : .positive,
                symbolName: outcome.isFailure ? "exclamationmark.triangle" : "checkmark.circle",
                title: outcome.headline,
                message: [outcome.meaning, outcome.nextStep, outcome.detail]
                    .compactMap { $0 }
                    .joined(separator: " ")
            ) {
                // The transcript's own Show in Finder is in the footer, which
                // stays in the same place before and after the meeting ends.
                HStack(spacing: Spacing.small) {
                    if let url = runtime.audioRetentionState.url {
                        Button("Show Audio in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .accessibilityHint("Reveal the meeting's audio file in the Finder")
                    }
                    if outcome.isFailure {
                        // Secondary, and deliberately last: the sentences
                        // above already say what happened and what to do,
                        // and a report is for the conversation that starts
                        // when following them did not work.
                        Button("Export Diagnostics…") { diagnostics.export() }
                            .accessibilityHint(
                                "Save a technical report about this Mac and this meeting. "
                                    + "It contains no transcript text or audio."
                            )
                    }
                }
            }
            .accessibilityLabel("Last meeting")
            .accessibilityValue(outcome.accessibilityDescription)
        }

        if let message = runtime.pauseFailureMessage {
            NoticeView(tone: .warning, symbolName: "exclamationmark.triangle", message: message)
        }
    }

    // MARK: - Footer

    /// Where the transcript is going, with the rest of the subsystem detail
    /// behind a button.
    private var footer: some View {
        HStack(spacing: Spacing.small) {
            Label {
                Text(fileLine)
                    .lineLimit(1)
                    .truncationMode(.middle)
            } icon: {
                Image(systemName: runtime.persistenceState.failureMessage == nil
                      ? "doc.text" : "exclamationmark.triangle")
                    .foregroundStyle(runtime.persistenceState.failureMessage == nil
                                     ? StatusTone.neutral.color : StatusTone.critical.color)
            }
            .textRole(.metadata)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Transcript file")
            .accessibilityValue(fileLine)

            Spacer(minLength: Spacing.small)

            if let layout = runtime.persistenceState.layout {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([layout.transcriptURL])
                }
                .accessibilityHint("Reveal the transcript in the Finder")
            }

            Button {
                isShowingDetails.toggle()
            } label: {
                Label("Details", systemImage: "info.circle")
            }
            .help("Capture, recognition and file details")
            .accessibilityHint("Show the state of capture, recognition and the files this meeting writes")
            .popover(isPresented: $isShowingDetails, arrowEdge: .top) {
                MeetingDetailsPopover(runtime: runtime)
            }
        }
        .controlSize(.small)
    }

    /// One line saying what is happening to the transcript file, naming it by
    /// its meeting folder rather than its whole path.
    private var fileLine: String {
        let state = runtime.persistenceState
        let name = state.layout.map { layout in
            let url = layout.transcriptURL
            return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
        }
        return switch state {
        case .idle: "No transcript yet."
        case .preparing: "Creating the meeting folder…"
        case .saving: name.map { "Saving to \($0)" } ?? "Saving the transcript."
        case .saved: name.map { "Saved to \($0)" } ?? "Transcript saved and closed."
        case .failed: "The transcript is not being saved."
        }
    }
}

// MARK: - Details

/// The subsystem detail behind the session footer's Details button.
///
/// Everything here was on the setup form before. It is exact and it matters
/// when something is wrong, but during a meeting it is secondary to what is
/// being said, so it is shown on request. Being inside a popover also means
/// the twice-a-second activity summary is observed only while someone is
/// looking at it.
private struct MeetingDetailsPopover: View {

    /// The meeting being described.
    let runtime: MeetingRuntime

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text("Meeting Details")
                .textRole(.groupTitle)
                .accessibilityAddTraits(.isHeader)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.medium,
                 verticalSpacing: Spacing.small) {
                FactRow(label: "Audio", value: captureStatusDescription)
                if case let .failed(message) = runtime.captureState {
                    FactRow(label: "Error", value: message)
                }
                FactRow(label: "Recognition", value: recognitionStatusDescription)
                if case let .failed(message) = runtime.transcriptionState {
                    FactRow(label: "Error", value: message)
                }
                if let identifier = runtime.meeting?.localeIdentifier {
                    FactRow(label: "Language", value: identifier, isTechnical: true)
                }
                FactRow(label: "Transcript", value: persistenceStatusDescription)
                if let layout = runtime.persistenceState.layout {
                    FactRow(
                        label: "File",
                        value: DisplayPath.abbreviated(layout.transcriptURL),
                        isTechnical: true,
                        truncatesMiddle: true
                    )
                }
                if let message = runtime.persistenceState.failureMessage {
                    FactRow(label: "Error", value: message)
                }
                if runtime.meeting?.captureMode != .microphone {
                    FactRow(label: "Recording", value: audioStatusDescription)
                    if let url = runtime.audioRetentionState.url {
                        FactRow(label: "Audio File", value: DisplayPath.abbreviated(url), isTechnical: true,
                                truncatesMiddle: true)
                    }
                    if let message = runtime.audioRetentionState.failureMessage {
                        FactRow(label: "Error", value: message)
                    }
                }
                CaptureActivityRow(runtime: runtime)
            }

            Text("Speech is recognised on this Mac, using an installed language model. "
                 + "No audio leaves your machine.")
                .textRole(.caption)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.large)
        .frame(width: 420, alignment: .leading)
    }

    /// A short description of what capture is doing.
    ///
    /// "Listening" rather than "capturing" or "recording" for the microphone:
    /// that audio is transcribed and released, and nothing of it is kept.
    private var captureStatusDescription: String {
        let sources = runtime.meeting?.sources ?? []
        if runtime.meeting?.captureMode == .microphone {
            let input = sources.first?.displayName ?? "Microphone"
            return switch runtime.captureState {
            case .idle: "Not listening."
            case .preparing: "Starting…"
            case .capturing: "Listening to \(input) for transcription."
            case .paused: "Paused. The microphone is not being listened to."
            case .stopping: "Stopping…"
            case .failed: "Listening stopped."
            }
        }
        return switch runtime.captureState {
        case .idle: "Not capturing."
        case .preparing: "Starting…"
        case .capturing: "Capturing \(sources.count) application(s)."
        case .paused: "Paused. Nothing is being captured."
        case .stopping: "Stopping…"
        case .failed: "Capture failed."
        }
    }

    /// A short description of what recognition is doing.
    private var recognitionStatusDescription: String {
        switch runtime.transcriptionState {
        case .idle: runtime.availability.canTranscribe ? "Ready, on this Mac." : "Unavailable."
        case .preparing: "Preparing the recogniser…"
        case .transcribing: "Transcribing on device."
        case .recovering: "Recognition stopped; restarting…"
        case .stopping: "Finalising…"
        case .failed: "Recognition failed."
        }
    }

    /// A short description of what the audio file is doing.
    private var audioStatusDescription: String {
        switch runtime.audioRetentionState {
        case .idle: "No audio file. Only the transcript is kept."
        case .preparing: "Creating the audio file…"
        case .retaining: "Recording audio as it is captured."
        case .retained: "Saved and closed."
        case .failed: "Not being recorded."
        }
    }

    /// A short description of what the durable transcript is doing.
    private var persistenceStatusDescription: String {
        switch runtime.persistenceState {
        case .idle: "No transcript yet."
        case .preparing: "Creating the meeting folder…"
        case .saving: "Saving finalised speech as it is recognised."
        case .saved: "Saved and closed."
        case .failed: "Not being saved."
        }
    }
}

/// What capture has delivered so far, as one row of the details.
///
/// A view of its own because the activity summary is published twice a second
/// for the length of a meeting and is one line of text.
private struct CaptureActivityRow: View {

    /// The meeting being watched.
    let runtime: MeetingRuntime

    var body: some View {
        if let description {
            FactRow(label: "Captured", value: description, isTechnical: true)
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

// MARK: - Elapsed

/// How long the meeting has been running.
///
/// A view of its own because ``MeetingElapsedClock`` advances once a second.
/// Read inside the session view's body, that tick would invalidate the header,
/// the notices and the footer once a second for the length of the meeting.
/// Read here, it invalidates one label.
private struct SessionElapsedText: View {

    /// The meeting being watched.
    let runtime: MeetingRuntime

    var body: some View {
        let elapsed = MeetingElapsedClock.description(of: runtime.elapsed.elapsed)
        Text(elapsed)
            .textRole(.timestamp)
            .accessibilityLabel("Elapsed time")
            .accessibilityValue(elapsed)
    }
}

// MARK: - Transcript

/// The live transcript: finalised spans, then the hypothesis for what is being
/// said now.
///
/// Finalised segments are rendered lazily, because a long meeting produces many
/// of them, and the partial is one row that is replaced rather than appended.
///
/// It is a view of its own because the recogniser replaces the partial several
/// times a second. Every one of those replacements invalidates whatever body
/// read it, so reading it here keeps the churn inside the transcript instead of
/// rebuilding the header and footer at recognition rate.
private struct LiveTranscriptPanel: View {

    /// The meeting being watched.
    let runtime: MeetingRuntime

    var body: some View {
        VStack(spacing: 0) {
            if runtime.transcript.untranscribedSeconds > 0 {
                NoticeView(
                    tone: .warning,
                    symbolName: "exclamationmark.triangle",
                    message: String(
                        format: "%.1f s of audio was not transcribed, so the transcript has gaps.",
                        runtime.transcript.untranscribedSeconds
                    )
                )
                .readableColumn()
                .padding(.top, Spacing.medium)
            }

            if runtime.transcript.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: LayoutMetrics.transcriptPassageSpacing) {
                        ForEach(runtime.transcript.finalizedSegments) { segment in
                            TranscriptPassageRow(
                                timestamp: Self.offset(segment.startTime),
                                text: AttributedString(segment.displayText),
                                timestampWidth: LayoutMetrics.offsetColumnWidth
                            )
                            .accessibilityElement(children: .combine)
                        }
                        // A partial is a guess about speech still being
                        // recognised. Once the meeting has ended there is
                        // nothing left to recognise, so it is not shown.
                        if runtime.isRunning, let partial = runtime.transcript.partialSegment {
                            TranscriptPassageRow(
                                timestamp: "",
                                text: AttributedString(partial.displayText),
                                timestampWidth: LayoutMetrics.offsetColumnWidth,
                                isProvisional: true
                            )
                            .help("A live guess. It is replaced as you speak and is never saved.")
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("In progress: \(partial.displayText)")
                        }
                    }
                    .readableColumn()
                    .padding(.vertical, Spacing.large)
                }
                .defaultScrollAnchor(.bottom)
            }

            if runtime.isRunning {
                Text("Grey italic text is a live guess: it is replaced as you speak and never saved. "
                     + "Only finalised speech is written to the transcript.")
                    .textRole(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .readableColumn()
                    .padding(.vertical, Spacing.small)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What the transcript area says before anything has been recognised.
    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: "waveform")
        } description: {
            Text(emptyDescription)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyTitle: String {
        switch runtime.status {
        case .transcribing: "Listening"
        case .preparing: "Starting"
        case .paused: "Paused"
        default: "Nothing Transcribed"
        }
    }

    private var emptyDescription: String {
        switch runtime.status {
        case .transcribing, .preparing: "Speech appears here as it is recognised."
        case .paused: "Nothing is captured while the meeting is paused."
        default: "No speech was recognised in this meeting."
        }
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

// MARK: - Layout

extension View {

    /// Centres this content in a column no wider than comfortable reading
    /// allows, with the pane's side margins.
    func readableColumn() -> some View {
        self
            .frame(maxWidth: LayoutMetrics.readableWidth, alignment: .leading)
            .padding(.horizontal, Spacing.xLarge)
            .frame(maxWidth: .infinity)
    }
}
