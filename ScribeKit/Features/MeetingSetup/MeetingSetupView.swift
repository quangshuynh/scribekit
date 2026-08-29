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

    @State private var sources: MeetingSetupSourcesModel
    @State private var title = ""
    @State private var audioRetention = AudioRetentionMode.default
    @State private var destination: URL?
    @State private var isChoosingDestination = false

    /// Creates the setup screen.
    ///
    /// - Parameter sourceProvider: Discovery used to populate the application
    ///   list. The default talks to ScreenCaptureKit; previews and tests can
    ///   substitute their own.
    init(sourceProvider: CaptureSourceProviding = ScreenCaptureKitSourceProvider()) {
        _sources = State(initialValue: MeetingSetupSourcesModel(provider: sourceProvider))
    }

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
        .task { await sources.refresh() }
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

            Text("Selected applications are not captured yet; audio capture arrives in a later release.")
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
