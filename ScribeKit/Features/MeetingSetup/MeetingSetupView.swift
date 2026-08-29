//
//  MeetingSetupView.swift
//  ScribeKit
//

import SwiftUI
import UniformTypeIdentifiers

/// The configuration screen shown before a meeting starts.
///
/// The screen collects the settings a session needs — title, audio sources,
/// audio retention and save location — but does not start anything: capture
/// and transcription are not implemented yet, so the start control is
/// deliberately unavailable rather than simulated.
struct MeetingSetupView: View {
    /// Whether a meeting can be started.
    ///
    /// Fixed to `false` until the capture and transcription pipeline exists.
    private static let isStartAvailable = false

    @State private var title = ""
    @State private var audioRetention = AudioRetentionMode.default
    @State private var destination: URL?
    @State private var isChoosingDestination = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Form {
                meetingSection
                sourcesSection
                audioRetentionSection
                destinationSection
            }
            .formStyle(.grouped)
            footer
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 520)
        .fileImporter(
            isPresented: $isChoosingDestination,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                destination = url
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
        Section("Audio Sources") {
            LabeledContent("Applications") {
                Text("Not available yet")
                    .foregroundStyle(.secondary)
            }
            Text("Choosing which applications to capture arrives in a later release.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
                Text(destination?.path(percentEncoded: false) ?? "No folder selected")
                    .foregroundStyle(destination == nil ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Button("Choose Folder…") { isChoosingDestination = true }
                .accessibilityHint("Choose where transcripts are saved")
        }
    }

    private var footer: some View {
        HStack {
            Text("Transcription is not implemented yet.")
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
