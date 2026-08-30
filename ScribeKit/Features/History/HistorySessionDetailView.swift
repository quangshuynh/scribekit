//
//  HistorySessionDetailView.swift
//  ScribeKit
//

import SwiftUI

/// One past meeting, described from its own artifacts.
///
/// Everything describing the meeting is read from the session record, the
/// transcript's header or the filesystem, and none of it is editable: the
/// transcript preview is text and the actions hand a file to the Finder or to
/// another application.
///
/// Two things here are the user's own and are written: the notes they type and
/// the review passages they mark as dealt with. Both go to
/// `.scribekit/derived.json` through ``DerivedSessionModel`` and reach nothing
/// else, so the transcript, the recording, the session record and the review
/// sidecar stay byte-identical however much is written in this pane.
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

    private var derived: DerivedSessionModel { model.derived }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heading
                Divider()
                facts
                Divider()
                actions
                Divider()
                review
                Divider()
                notes
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

    // MARK: - Review

    /// The passages this meeting flagged for a second listen.
    ///
    /// Review is a view over what the meeting recorded about itself. It shows
    /// the recognised wording exactly as the transcript has it, says why the
    /// passage was flagged, and offers to play the audio around it. It never
    /// proposes a replacement, and there is no editor here or anywhere else.
    @ViewBuilder
    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review")
                .font(.headline)

            let candidates = document.reviewCandidates
            if document.review == nil {
                Text("This meeting has no review information. ScribeKit records it while a meeting runs, "
                     + "so meetings recorded before that existed do not have any. The transcript is unaffected.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if candidates.isEmpty {
                Text(noCandidatesDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(reviewSummary(for: candidates.map(\.candidate.spanIndex)))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(candidates, id: \.candidate.spanIndex) { pair in
                    candidateRow(pair.candidate, span: pair.span)
                }

                if let message = derived.failureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = model.player.failureMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What to say when the meeting recorded review information and flagged
    /// nothing.
    ///
    /// The two cases are not the same. A meeting whose recogniser reported no
    /// confidence at all had less to go on than one whose recogniser was
    /// consistently sure, and saying so avoids implying a judgement nothing
    /// made.
    private var noCandidatesDescription: String {
        if document.review?.recognizerConfidenceAvailable == true {
            return "Nothing in this meeting was flagged for review."
        }
        return "Nothing in this meeting was flagged for review. The recogniser reported no confidence of "
            + "its own for this meeting, so only ScribeKit's own observations were available."
    }

    /// One review candidate: what was recognised, when, why it is here, and
    /// the audio around it.
    ///
    /// - Parameters:
    ///   - candidate: The flagged span's evidence.
    ///   - span: The span as the transcript wrote it.
    /// - Returns: The row view.
    private func candidateRow(_ candidate: TranscriptReviewCandidate, span: TranscriptSpan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(candidate.priority.displayName)
                    .font(.caption.weight(.semibold))
                Text(span.timestampDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(derived.isReviewed(spanIndex: candidate.spanIndex) ? "Reviewed" : "Needs Review")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(span.text)
                .textSelection(.enabled)

            ForEach(candidate.reasons, id: \.rawValue) { reason in
                Text(reason.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            playbackControls(for: candidate)
            reviewedControl(for: candidate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// How many of this meeting's flagged passages the user has dealt with.
    ///
    /// - Parameter spanIndexes: The span indexes the meeting has candidates
    ///   for.
    /// - Returns: The summary sentence.
    private func reviewSummary(for spanIndexes: [Int]) -> String {
        let count = spanIndexes.count
        let passages = "\(count) passage\(count == 1 ? "" : "s") worth a second listen, "
            + "in the order they were spoken."
        guard derived.isEditable else { return passages }
        return passages + " \(derived.reviewedCount(among: spanIndexes)) of \(count) marked reviewed."
    }

    /// The control that records whether a passage has been dealt with.
    ///
    /// The mark is the user's own disposition and is written to the derived
    /// sidecar as soon as it is made. `review.json` is not touched: what the
    /// recogniser observed is not revised by the user having looked at it.
    ///
    /// - Parameter candidate: The flagged span.
    /// - Returns: The control view.
    @ViewBuilder
    private func reviewedControl(for candidate: TranscriptReviewCandidate) -> some View {
        if derived.isEditable {
            let reviewed = derived.isReviewed(spanIndex: candidate.spanIndex)
            Button(reviewed ? "Mark Unreviewed" : "Mark Reviewed") {
                Task { await derived.setReviewed(!reviewed, spanIndex: candidate.spanIndex) }
            }
            .font(.caption)
            .disabled(derived.isSaving)
            .accessibilityHint(reviewed
                ? "Record that this passage still needs a second listen"
                : "Record that you have dealt with this passage")
        }
    }

    // MARK: - Notes

    /// The user's own notes about the meeting.
    ///
    /// Plain Markdown source, typed by the user and stored verbatim beside the
    /// transcript rather than in it. Nothing generates it, nothing rewrites it,
    /// and it never reaches `transcript.md`.
    @ViewBuilder
    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Notes")
                    .font(.headline)
                Spacer()
                if derived.isEditable {
                    Button("Save") {
                        Task { await derived.saveNotes() }
                    }
                    .disabled(derived.isSaving || !derived.hasUnsavedNotes)
                    .accessibilityHint("Write these notes beside the transcript. The transcript is unchanged.")
                }
            }

            switch derived.state {
            case let .refused(message), let .unsupported(message):
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .idle, .loading:
                Text("Reading this meeting's notes…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            case .ready:
                TextEditor(text: Bindable(derived).notesDraft)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .accessibilityLabel("Notes about this meeting")

                Text(derived.statusDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text("Your notes are Markdown source, kept in this meeting's folder beside the "
                     + "transcript and never written into it. They stay on this Mac. Unsaved text is "
                     + "discarded if you leave this meeting before saving.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The playback controls for one candidate, or a sentence saying why there
    /// are none.
    ///
    /// - Parameter candidate: The flagged span.
    /// - Returns: The controls view.
    @ViewBuilder
    private func playbackControls(for candidate: TranscriptReviewCandidate) -> some View {
        if session.audio == nil {
            Text("This meeting kept no recording, so there is no audio to play.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 8) {
                if model.player.loadedSpanIndex == candidate.spanIndex, model.player.isPlaying {
                    Button("Pause") { model.player.pause() }
                    Button("Stop") { model.stopPlayback() }
                } else if model.player.loadedSpanIndex == candidate.spanIndex,
                          case .paused = model.player.playback {
                    Button("Resume") { model.player.resume() }
                    Button("Stop") { model.stopPlayback() }
                } else {
                    Button("Play Audio") {
                        Task { await model.play(candidate, of: session) }
                    }
                    .accessibilityHint("Play the retained recording around this passage")
                }
            }
            .font(.caption)
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
