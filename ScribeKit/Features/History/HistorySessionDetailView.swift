//
//  HistorySessionDetailView.swift
//  ScribeKit
//

import SwiftUI

/// One past meeting, described from its own artifacts.
///
/// Everything shown is read from the session record, the transcript's header
/// or the filesystem. There is no editor: the transcript preview is text, the
/// actions hand a file to the Finder or to another application, and ScribeKit
/// writes nothing here.
struct HistorySessionDetailView: View {

    /// The History state, used for the file actions and their narrow
    /// security-scoped access.
    let model: HistoryModel

    /// The meeting and the words said in it.
    let document: TranscriptSearchDocument

    /// How many spans the preview shows before it stops.
    ///
    /// A preview, not a reader: a multi-hour meeting has thousands of spans,
    /// and the transcript itself is one click away in the Finder.
    static let previewSpanLimit = 50

    private var session: HistorySession { document.session }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heading
                Divider()
                facts
                Divider()
                actions
                Divider()
                preview
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.title2.weight(.semibold))
                .textSelection(.enabled)
            Text(session.status.explanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var facts: some View {
        VStack(alignment: .leading, spacing: 8) {
            fact("Status", session.status.displayName)

            if let startedAt = session.startedAt {
                fact("Started", startedAt.formatted(date: .abbreviated, time: .standard))
            }
            if let endedAt = session.endedAt {
                fact("Ended", endedAt.formatted(date: .abbreviated, time: .standard))
            }
            if let duration = session.duration {
                fact("Duration", TranscriptMarkdownFormatter.durationDescription(duration))
            }
            if session.startedAt == nil, let modified = session.transcript.modifiedAt {
                fact("Transcript last written", modified.formatted(date: .abbreviated, time: .standard))
            }

            if !session.sourceNames.isEmpty {
                fact("Applications", session.sourceNames.formatted(.list(type: .and)))
            }
            if let locale = session.localeIdentifier {
                fact("Language", locale)
            }
            fact("Transcript", "\(session.transcript.byteCount) bytes")
            fact("Audio", audioDescription)
            fact("Folder", session.directory.path(percentEncoded: false), truncatesPath: true)

            if session.isLegacy {
                Text("This meeting has no ScribeKit session record, so its start and end times, "
                     + "its identity and what it kept of its audio are not known. "
                     + "Its transcript is unaffected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// What the folder holds of the meeting's audio.
    ///
    /// A retention mode with no file beside it is stated as such: a meeting
    /// that was keeping audio and stopped before its first captured buffer
    /// leaves exactly that, and calling it "no audio" would lose the
    /// difference.
    private var audioDescription: String {
        if let audio = session.audio {
            return "\(audio.format.displayName) · \(audio.file.byteCount) bytes"
        }
        if session.isMissingExpectedAudio {
            return "None in the folder, though the record says audio was being kept"
        }
        if session.isLegacy {
            return "No audio file beside the transcript"
        }
        return "None. This meeting kept only its transcript."
    }

    private var actions: some View {
        HStack {
            Button("Show Transcript in Finder") {
                model.showInFinder(session.transcriptURL)
            }
            .accessibilityHint("Reveal this meeting's transcript in the Finder")

            Button("Open Transcript") {
                model.openTranscript(session.transcriptURL)
            }
            .accessibilityHint("Open the transcript in your Markdown application. ScribeKit does not edit it.")

            if let audio = session.audio {
                Button("Show Audio in Finder") {
                    model.showInFinder(audio.url)
                }
                .accessibilityHint("Reveal this meeting's audio file in the Finder")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Transcript")
                .font(.headline)

            if document.spans.isEmpty {
                Text("Nothing was transcribed in this meeting.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(document.spans.prefix(Self.previewSpanLimit)) { span in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(span.timestampDescription)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(span.text)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }

                if document.spans.count > Self.previewSpanLimit {
                    Text("Showing the first \(Self.previewSpanLimit) of \(document.spans.count) "
                         + "transcribed passages. Open the transcript to read all of it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One labelled fact about the meeting.
    ///
    /// - Parameters:
    ///   - label: What the value is.
    ///   - value: The value itself.
    ///   - truncatesPath: Whether to truncate in the middle, as a path should.
    /// - Returns: The row view.
    private func fact(_ label: String, _ value: String, truncatesPath: Bool = false) -> some View {
        LabeledContent(label) {
            Text(value)
                .lineLimit(truncatesPath ? 1 : nil)
                .truncationMode(truncatesPath ? .middle : .tail)
                .textSelection(.enabled)
        }
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
