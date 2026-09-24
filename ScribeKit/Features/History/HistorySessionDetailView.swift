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

    /// How many spans the preview shows at once.
    ///
    /// A preview, not a reader: a multi-hour meeting has thousands of spans,
    /// and laying them all out would cost the screen what it costs to open.
    /// The window moves to whichever span find or Review points at, so every
    /// part of the transcript can be reached.
    static let previewSpanLimit = 50

    /// A passage revealed from Review, for VoiceOver to move to.
    @AccessibilityFocusState private var focusedSpan: Int?

    private var session: HistorySession { document.session }

    private var derived: DerivedSessionModel { model.derived }

    var body: some View {
        ScrollViewReader { proxy in
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
            .onChange(of: model.previewAnchor) { _, anchor in
                guard let anchor else { return }
                // On the next turn, once the preview window has moved and the
                // row exists to scroll to.
                Task { @MainActor in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(Self.rowID(anchor), anchor: .center)
                    }
                }
            }
        }
    }

    /// The scroll identity of one span's row in the preview.
    ///
    /// - Parameter spanIndex: The span's position.
    private static func rowID(_ spanIndex: Int) -> String {
        "span-\(spanIndex)"
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
                // A Microphone meeting's source is not an application. A
                // session whose record predates the distinction captured
                // applications, which is all ScribeKit could capture then.
                fact(
                    session.captureMode == .microphone ? "Source" : "Applications",
                    session.sourceNames.formatted(.list(type: .and))
                )
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
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(candidate.reasons, id: \.rawValue) { reason in
                    Text(reason.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(candidateDescription(candidate, span: span))

            HStack(spacing: 8) {
                Button("Show in Transcript") {
                    model.reveal(spanIndex: candidate.spanIndex)
                    Task { @MainActor in focusedSpan = candidate.spanIndex }
                }
                .font(.caption)
                .accessibilityHint("Move the transcript preview to this passage")
                playbackControls(for: candidate)
            }
            reviewedControl(for: candidate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flagged passage at \(span.timestampDescription)")
    }

    /// What one flagged passage is, without the words that were recognised.
    ///
    /// - Parameters:
    ///   - candidate: The flagged span's evidence.
    ///   - span: The span as the transcript wrote it.
    /// - Returns: The description.
    private func candidateDescription(_ candidate: TranscriptReviewCandidate, span: TranscriptSpan) -> String {
        candidate.accessibilityDescription(
            timestamp: span.timestampDescription,
            text: span.text,
            isReviewed: derived.isReviewed(spanIndex: candidate.spanIndex),
            hasAudio: session.audio != nil
        )
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
                     + "discarded if you select another meeting before saving.")
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
                findBar

                let window = TranscriptPreviewWindow.range(
                    count: document.spans.count,
                    anchor: model.previewAnchor,
                    limit: Self.previewSpanLimit
                )
                if window.count < document.spans.count {
                    Text("Showing passages \(window.lowerBound + 1)–\(window.upperBound) of "
                         + "\(document.spans.count). Find a phrase or open the transcript to reach the rest.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                ForEach(document.spans[window]) { span in
                    spanRow(span)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finding a phrase within this transcript.
    ///
    /// Return in the field and ⌘G move to the next match, ⇧⌘G to the
    /// previous one, and both wrap; Escape clears the field. The field keeps
    /// the keyboard while the user steps through matches, and each step is
    /// announced, so the preview moving is not something only a sighted user
    /// learns about.
    private var findBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Find in transcript", text: Bindable(model).findQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit { step(forward: true) }
                .onExitCommand { model.findQuery = "" }
                .accessibilityLabel("Find in this transcript")
                .accessibilityHint("Finds text in the recognised speech. Press Return for the next match.")

            if model.find.isActive {
                Text(model.find.positionDescription)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(model.find.accessibilityPosition)
            }

            Button {
                step(forward: false)
            } label: {
                Image(systemName: "chevron.up")
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .help("Previous Match (⇧⌘G)")
            .accessibilityLabel("Previous match")
            .disabled(model.find.matches.isEmpty)

            Button {
                step(forward: true)
            } label: {
                Image(systemName: "chevron.down")
            }
            .keyboardShortcut("g", modifiers: .command)
            .help("Next Match (⌘G)")
            .accessibilityLabel("Next match")
            .disabled(model.find.matches.isEmpty)
        }
    }

    /// Moves to the next or previous match and says where it is.
    ///
    /// - Parameter forward: Whether to move to the next match.
    private func step(forward: Bool) {
        guard !model.find.matches.isEmpty else { return }
        if forward { model.findNext() } else { model.findPrevious() }
        guard let current = model.find.current, current.spanIndex < document.spans.count else { return }
        let span = document.spans[current.spanIndex]
        AccessibilityNotification.Announcement(
            "\(model.find.accessibilityPosition), at \(span.timestampDescription)"
        ).post()
    }

    /// One span of the preview, with any find matches in it highlighted.
    ///
    /// - Parameter span: The span.
    /// - Returns: The row view.
    private func spanRow(_ span: TranscriptSpan) -> some View {
        let matches = model.find.matches(inSpan: span.index)
        let current = model.find.current.flatMap { $0.spanIndex == span.index ? $0 : nil }
        let isRevealed = model.revealedSpanIndex == span.index
        return VStack(alignment: .leading, spacing: 2) {
            Text(span.timestampDescription)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Text(Self.highlighted(span.text, matches: matches, current: current))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isRevealed ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .id(Self.rowID(span.index))
        .accessibilityElement(children: .combine)
        .accessibilityValue(Self.matchAccessibilityValue(matchCount: matches.count, hasCurrent: current != nil))
        .accessibilityFocused($focusedSpan, equals: span.index)
    }

    /// What a preview row adds for assistive technology about find matches in
    /// it.
    ///
    /// - Parameters:
    ///   - matchCount: How many matches the span holds.
    ///   - hasCurrent: Whether one of them is the current match.
    /// - Returns: The value, empty for a span with no matches.
    static func matchAccessibilityValue(matchCount: Int, hasCurrent: Bool) -> String {
        guard matchCount > 0 else { return "" }
        if hasCurrent { return matchCount == 1 ? "Current match" : "Current match, \(matchCount) matches" }
        return matchCount == 1 ? "1 match" : "\(matchCount) matches"
    }

    /// A span's words with its find matches highlighted.
    ///
    /// The highlight is an attribute on a copy made for display. The words
    /// are the transcript's own, unchanged; nothing is inserted and nothing is
    /// written. The current match is drawn in the system's find highlight and
    /// in bold, so it is told apart from the others by more than colour.
    ///
    /// - Parameters:
    ///   - text: The span's recognised text.
    ///   - matches: The matches within it.
    ///   - current: The current match, when it is in this span.
    /// - Returns: The attributed text.
    static func highlighted(
        _ text: String,
        matches: [TranscriptFindMatch],
        current: TranscriptFindMatch?
    ) -> AttributedString {
        var attributed = AttributedString(text)
        let count = text.count
        for match in matches where match.length > 0 && match.offset >= 0 && match.offset + match.length <= count {
            let start = attributed.index(attributed.startIndex, offsetByCharacters: match.offset)
            let end = attributed.index(start, offsetByCharacters: match.length)
            if match == current {
                attributed[start..<end].backgroundColor = Color(nsColor: .findHighlightColor)
                attributed[start..<end].foregroundColor = .black
                attributed[start..<end].inlinePresentationIntent = .stronglyEmphasized
            } else {
                attributed[start..<end].backgroundColor = Color.accentColor.opacity(0.25)
            }
        }
        return attributed
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
