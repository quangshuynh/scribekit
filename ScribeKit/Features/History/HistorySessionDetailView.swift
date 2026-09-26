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
///
/// The pane reads top to bottom in the order of attention: what the meeting
/// was, anything in it that may need a second listen, the user's notes, then
/// the transcript itself. Facts about the files are grouped and set quieter
/// than the words that were said.
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
                VStack(alignment: .leading, spacing: Spacing.xxLarge) {
                    VStack(alignment: .leading, spacing: Spacing.large) {
                        heading
                        actions
                    }
                    facts
                    review
                    notes
                    preview
                }
                .readableColumn()
                .padding(.vertical, Spacing.xLarge)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // Pinned above the scrolling content, so the field and its
                // count stay in view while the preview scrolls to a match.
                if !document.spans.isEmpty {
                    VStack(spacing: 0) {
                        findBar
                            .padding(.horizontal, Spacing.large)
                            .padding(.vertical, Spacing.small)
                        Divider()
                    }
                    .background(.bar)
                }
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

    // MARK: - Heading

    /// The meeting's name, when it happened and how it came to end.
    ///
    /// An ordinary ending is stated once, in the facts below. Any other
    /// ending is stated here as well, in a notice, because it changes how the
    /// transcript should be read.
    private var heading: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(session.title)
                .textRole(.pageTitle)
                .textSelection(.enabled)
                .accessibilityAddTraits(.isHeader)

            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                if let mode = session.knownCaptureMode {
                    Image(systemName: mode.symbolName)
                        .accessibilityHidden(true)
                }
                Text(subtitle)
            }
            .textRole(.metadata)
            .accessibilityElement(children: .combine)

            if session.status.isNoteworthy {
                NoticeView(
                    tone: session.status.tone,
                    symbolName: session.status.symbolName,
                    title: session.status.displayName,
                    message: session.status.explanation
                )
                .padding(.top, Spacing.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The capture mode, date and length of the meeting on one line.
    private var subtitle: String {
        var parts: [String] = []
        if let mode = session.knownCaptureMode { parts.append(mode.displayName) }
        parts.append(HistoryView.dateDescription(for: session))
        if let duration = session.duration {
            parts.append(TranscriptMarkdownFormatter.durationDescription(duration))
        }
        return parts.joined(separator: " · ")
    }

    /// The file actions, titled when the pane is wide enough and reduced to
    /// their symbols — with the same names as tooltips and for VoiceOver —
    /// when it is not, so no title is ever cut short.
    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            actionButtons.labelStyle(.titleAndIcon)
            actionButtons.labelStyle(.iconOnly)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: Spacing.small) {
            Button {
                model.openTranscript(session.transcriptURL)
            } label: {
                Label("Open Transcript", systemImage: "doc.text")
            }
            .help("Open Transcript")
            .accessibilityHint("Open the transcript in your Markdown application. ScribeKit does not edit it.")

            Button {
                model.showInFinder(session.transcriptURL)
            } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .help("Show Transcript in Finder")
            .accessibilityLabel("Show Transcript in Finder")
            .accessibilityHint("Reveal this meeting's transcript in the Finder")

            if let audio = session.audio {
                Button {
                    model.showInFinder(audio.url)
                } label: {
                    Label("Show Audio in Finder", systemImage: "waveform")
                }
                .help("Show Audio in Finder")
                .accessibilityHint("Reveal this meeting's audio file in the Finder")
            }
        }
        .fixedSize()
    }

    // MARK: - Facts

    /// What ScribeKit knows about the meeting's files, as label and value
    /// pairs. Identifiers — a locale, a size, a path — are set in the
    /// monospaced face so they read as values rather than prose.
    private var facts: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeading("Details")

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.medium,
                 verticalSpacing: Spacing.small) {
                FactRow(label: "Status", value: session.status.displayName)

                if let startedAt = session.startedAt {
                    FactRow(label: "Started", value: startedAt.formatted(date: .abbreviated, time: .standard))
                }
                if let endedAt = session.endedAt {
                    FactRow(label: "Ended", value: endedAt.formatted(date: .abbreviated, time: .standard))
                }
                if let duration = session.duration {
                    FactRow(label: "Duration", value: TranscriptMarkdownFormatter.durationDescription(duration))
                }
                if session.startedAt == nil, let modified = session.transcript.modifiedAt {
                    FactRow(label: "Transcript last written",
                            value: modified.formatted(date: .abbreviated, time: .standard))
                }

                if !session.sourceNames.isEmpty {
                    // A Microphone meeting's source is not an application. A
                    // session whose record predates the distinction captured
                    // applications, which is all ScribeKit could capture then.
                    FactRow(
                        label: session.captureMode == .microphone ? "Source" : "Applications",
                        value: session.sourceNames.formatted(.list(type: .and))
                    )
                }
                if let locale = session.localeIdentifier {
                    FactRow(label: "Language", value: locale, isTechnical: true)
                }
                FactRow(label: "Transcript", value: Self.byteDescription(session.transcript.byteCount))
                FactRow(label: "Audio", value: audioDescription)
                FactRow(label: "Folder", value: DisplayPath.abbreviated(session.directory), isTechnical: true,
                        truncatesMiddle: true)
            }

            if session.isLegacy {
                Text("This meeting has no ScribeKit session record, so its start and end times, "
                     + "its identity and what it kept of its audio are not known. "
                     + "Its transcript is unaffected.")
                    .textRole(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// A file size in the units the Finder uses.
    ///
    /// - Parameter count: The size in bytes.
    /// - Returns: The description, such as `810 bytes` or `12.3 MB`.
    private static func byteDescription(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file))
    }

    /// What the folder holds of the meeting's audio.
    ///
    /// A retention mode with no file beside it is stated as such: a meeting
    /// that was keeping audio and stopped before its first captured buffer
    /// leaves exactly that, and calling it "no audio" would lose the
    /// difference.
    private var audioDescription: String {
        if let audio = session.audio {
            return "\(audio.format.displayName) · \(Self.byteDescription(audio.file.byteCount))"
        }
        if session.isMissingExpectedAudio {
            return "None in the folder, though the record says audio was being kept"
        }
        if session.isLegacy {
            return "No audio file beside the transcript"
        }
        return "None. This meeting kept only its transcript."
    }

    // MARK: - Review

    /// The passages this meeting flagged for a second listen.
    ///
    /// Review is a view over what the meeting recorded about itself. It shows
    /// the recognised wording exactly as the transcript has it, says why the
    /// passage was flagged, and offers to play the audio around it. It never
    /// proposes a replacement, and there is no editor here or anywhere else.
    ///
    /// Emphasis follows priority: a high-priority passage is marked in the
    /// warning colour, a low one carries no colour at all, and nothing here is
    /// drawn as an error, because a passage worth another listen is not one.
    @ViewBuilder
    private var review: some View {
        let candidates = document.reviewCandidates
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeading("Review") {
                if !candidates.isEmpty, derived.isEditable {
                    let indexes = candidates.map(\.candidate.spanIndex)
                    Text("\(derived.reviewedCount(among: indexes)) of \(indexes.count) reviewed")
                        .textRole(.metadata)
                }
            }

            if document.review == nil {
                Text("This meeting has no review information. ScribeKit records it while a meeting runs, "
                     + "so meetings recorded before that existed do not have any. The transcript is unaffected.")
                    .textRole(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
            } else if candidates.isEmpty {
                StatusBadge(title: noCandidatesDescription, symbolName: "checkmark.circle", tone: .positive,
                            role: .secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(reviewSummary(for: candidates.map(\.candidate.spanIndex)))
                    .textRole(.secondaryBody)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(candidates, id: \.candidate.spanIndex) { pair in
                    candidateRow(pair.candidate, span: pair.span)
                }

                if let message = derived.failureMessage {
                    NoticeView(tone: .warning, symbolName: "exclamationmark.triangle", message: message)
                }

                if let message = model.player.failureMessage {
                    NoticeView(tone: .warning, symbolName: "exclamationmark.triangle", message: message)
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
        let reviewed = derived.isReviewed(spanIndex: candidate.spanIndex)
        return VStack(alignment: .leading, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    StatusBadge(
                        title: "\(candidate.priority.displayName) Priority",
                        symbolName: candidate.priority.symbolName,
                        tone: candidate.priority.tone,
                        role: .metadata
                    )
                    Text(span.timestampDescription)
                        .textRole(.timestamp)
                    Spacer(minLength: Spacing.small)
                    if reviewed {
                        StatusBadge(title: "Reviewed", symbolName: "checkmark.circle.fill", tone: .positive)
                    } else {
                        Text("Needs Review")
                            .textRole(.metadata)
                    }
                }

                Text(span.text)
                    .textRole(.body)
                    .lineSpacing(LayoutMetrics.transcriptLineSpacing)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(candidate.reasons, id: \.rawValue) { reason in
                    Label(reason.explanation, systemImage: reason.symbolName)
                        .textRole(.secondaryBody)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityLabel(candidateDescription(candidate, span: span))

            HStack(spacing: Spacing.small) {
                Button("Show in Transcript") {
                    model.reveal(spanIndex: candidate.spanIndex)
                    Task { @MainActor in focusedSpan = candidate.spanIndex }
                }
                .accessibilityHint("Move the transcript preview to this passage")

                playbackControls(for: candidate)

                Spacer(minLength: 0)

                reviewedControl(for: candidate)
            }
            .controlSize(.small)
        }
        .padding(Spacing.medium)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
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

    /// How many passages were flagged, and — once — whether there is audio to
    /// play for them.
    ///
    /// - Parameter spanIndexes: The span indexes the meeting has candidates
    ///   for.
    /// - Returns: The summary sentence.
    private func reviewSummary(for spanIndexes: [Int]) -> String {
        let count = spanIndexes.count
        let passages = "\(count) passage\(count == 1 ? "" : "s") worth a second listen, "
            + "in the order they were spoken."
        guard session.audio == nil else { return passages }
        return passages + " This meeting kept no recording, so there is no audio to play."
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
            .disabled(derived.isSaving)
            .accessibilityHint(reviewed
                ? "Record that this passage still needs a second listen"
                : "Record that you have dealt with this passage")
        }
    }

    /// The playback controls for one candidate. A meeting with no recording
    /// has none, which the summary above says once rather than on every row.
    ///
    /// - Parameter candidate: The flagged span.
    /// - Returns: The controls view.
    @ViewBuilder
    private func playbackControls(for candidate: TranscriptReviewCandidate) -> some View {
        if session.audio != nil {
            if model.player.loadedSpanIndex == candidate.spanIndex, model.player.isPlaying {
                Button("Pause") { model.player.pause() }
                Button("Stop") { model.stopPlayback() }
            } else if model.player.loadedSpanIndex == candidate.spanIndex,
                      case .paused = model.player.playback {
                Button("Resume") { model.player.resume() }
                Button("Stop") { model.stopPlayback() }
            } else {
                Button {
                    Task { await model.play(candidate, of: session) }
                } label: {
                    Label("Play Audio", systemImage: "play.fill")
                }
                .accessibilityHint("Play the retained recording around this passage")
            }
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
        VStack(alignment: .leading, spacing: Spacing.medium) {
            SectionHeading("Notes") {
                if derived.isEditable {
                    Button("Save") {
                        Task { await derived.saveNotes() }
                    }
                    .controlSize(.small)
                    .disabled(derived.isSaving || !derived.hasUnsavedNotes)
                    .accessibilityHint("Write these notes beside the transcript. The transcript is unchanged.")
                }
            }

            switch derived.state {
            case let .refused(message), let .unsupported(message):
                NoticeView(tone: .warning, symbolName: "exclamationmark.triangle", message: message)
            case .idle, .loading:
                Text("Reading this meeting's notes…")
                    .textRole(.secondaryBody)
            case .ready:
                TextEditor(text: Bindable(derived).notesDraft)
                    .textRole(.editor)
                    .scrollContentBackground(.hidden)
                    .padding(Spacing.small)
                    .frame(minHeight: LayoutMetrics.notesEditorMinHeight)
                    .background(Color(nsColor: .textBackgroundColor),
                                in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                            .strokeBorder(Color(nsColor: .separatorColor))
                    }
                    .accessibilityLabel("Notes about this meeting")

                VStack(alignment: .leading, spacing: Spacing.xSmall) {
                    Text(derived.statusDescription)
                        .textRole(.metadata)
                    Text("Your notes are Markdown source, kept in this meeting's folder beside the "
                         + "transcript and never written into it. They stay on this Mac. Unsaved text is "
                         + "discarded if you select another meeting before saving.")
                        .textRole(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Transcript

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            let window = TranscriptPreviewWindow.range(
                count: document.spans.count,
                anchor: model.previewAnchor,
                limit: Self.previewSpanLimit
            )
            SectionHeading("Transcript") {
                if window.count < document.spans.count {
                    Text("Passages \(window.lowerBound + 1)–\(window.upperBound) of \(document.spans.count)")
                        .textRole(.metadata)
                }
            }

            if document.spans.isEmpty {
                Text("Nothing was transcribed in this meeting.")
                    .textRole(.secondaryBody)
            } else {
                if window.count < document.spans.count {
                    Text("Find a phrase or open the transcript to reach the rest.")
                        .textRole(.secondaryBody)
                }

                LazyVStack(alignment: .leading, spacing: LayoutMetrics.transcriptPassageSpacing) {
                    ForEach(document.spans[window]) { span in
                        spanRow(span)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Finding a phrase within this transcript, pinned above the details.
    ///
    /// Return in the field and ⌘G move to the next match, ⇧⌘G to the
    /// previous one, and both wrap; Escape clears the field. The field keeps
    /// the keyboard while the user steps through matches, and each step is
    /// announced, so the preview moving is not something only a sighted user
    /// learns about.
    private var findBar: some View {
        HStack(spacing: Spacing.small) {
            TextField("Find in transcript", text: Bindable(model).findQuery,
                      prompt: Text("Find in Transcript"))
                .textFieldStyle(.roundedBorder)
                .onSubmit { step(forward: true) }
                .onExitCommand { model.findQuery = "" }
                .accessibilityLabel("Find in this transcript")
                .accessibilityHint("Finds text in the recognised speech. Press Return for the next match.")

            if model.find.isActive {
                Text(model.find.positionDescription)
                    .textRole(.timestamp)
                    .fixedSize()
                    .accessibilityLabel(model.find.accessibilityPosition)
            }

            ControlGroup {
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
            .fixedSize()
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
    /// A passage revealed from Review is marked by a bar at its leading edge
    /// as well as a tint, so it is found by shape and not only by colour, and
    /// VoiceOver is moved to it.
    ///
    /// - Parameter span: The span.
    /// - Returns: The row view.
    private func spanRow(_ span: TranscriptSpan) -> some View {
        let matches = model.find.matches(inSpan: span.index)
        let current = model.find.current.flatMap { $0.spanIndex == span.index ? $0 : nil }
        let isRevealed = model.revealedSpanIndex == span.index
        return TranscriptPassageRow(
            timestamp: span.timestampDescription,
            text: Self.highlighted(span.text, matches: matches, current: current),
            timestampWidth: LayoutMetrics.clockColumnWidth
        )
        .padding(.vertical, Spacing.xSmall)
        .padding(.horizontal, Spacing.small)
        .background {
            if isRevealed {
                RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous)
                    .fill(Color.accentColor.opacity(TintOpacity.revealedPassage))
            }
        }
        .overlay(alignment: .leading) {
            if isRevealed {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, Spacing.xSmall)
            }
        }
        .padding(.horizontal, -Spacing.small)
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
                attributed[start..<end].backgroundColor = Color(nsColor: .findHighlightColor)
                    .opacity(TintOpacity.findMatch)
            }
        }
        return attributed
    }
}
