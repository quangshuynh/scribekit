//
//  HistoryView.swift
//  ScribeKit
//

import SwiftUI

/// The screen that lists past meetings and searches what was said in them.
///
/// History is a read-only view over the files in the user's save folder. It
/// opens nothing for writing, changes no session record, and owns no meeting:
/// the runtime is handed in only so the list can refresh itself when a meeting
/// finishes, and switching to this screen while one is running leaves capture,
/// recognition and transcript writing exactly as they were.
struct HistoryView: View {

    /// The application's meeting owner, observed so the list refreshes when a
    /// meeting finishes. Never started, stopped or replaced from here.
    let runtime: MeetingRuntime

    @State private var model: HistoryModel
    @State private var selection: URL?
    @State private var searchFocus = HistorySearchFocus()
    @FocusState private var searchFieldFocused: Bool

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - runtime: The application's meeting owner.
    ///   - model: The History state, or `nil` to build one that reads the
    ///     real save folder. Previews and tests substitute their own.
    ///   - initialSelection: The meeting to show first, for a preview that
    ///     opens on one; `nil` shows none until the user chooses.
    init(runtime: MeetingRuntime, model: HistoryModel? = nil, initialSelection: URL? = nil) {
        self.runtime = runtime
        _model = State(initialValue: model ?? HistoryModel())
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(
                    min: LayoutMetrics.sidebarMinWidth,
                    ideal: LayoutMetrics.sidebarIdealWidth,
                    max: LayoutMetrics.sidebarMaxWidth
                )
        } detail: {
            detail
        }
        .task { await model.load() }
        .focusedSceneValue(\.historySearchFocus, searchFocus)
        .onChange(of: searchFocus.requestCount) { _, _ in
            searchFieldFocused = true
        }
        .onDisappear { model.stopPlayback() }
        .onChange(of: selection, initial: selection != nil) { _, newValue in
            model.stopPlayback()
            Task { await model.selectSession(newValue) }
        }
        .onChange(of: runtime.status.isActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            Task { await model.load() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            filterPicker
            Divider()
            listContent
            Divider()
            sidebarFooter
        }
    }

    /// The search field, drawn as a field so it reads as one on the sidebar's
    /// translucent background.
    private var searchField: some View {
        HStack(spacing: Spacing.xSmall + Spacing.hairline) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search meetings", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .accessibilityLabel("Search past meetings")
                .accessibilityHint("Searches meeting titles, sources and the speech in their transcripts")
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Spacing.small)
        .padding(.vertical, Spacing.xSmall + Spacing.hairline)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
        .padding(.horizontal, Spacing.medium)
        .padding(.top, Spacing.small)
        .padding(.bottom, Spacing.small)
    }

    /// Which meetings are listed, by where their audio came from.
    ///
    /// A segmented control: three mutually exclusive choices, each of which
    /// assistive technology reports as selected or not. It narrows the list
    /// the search runs over, so the two compose.
    private var filterPicker: some View {
        Picker("Source", selection: Bindable(model).filter) {
            ForEach(HistoryCaptureFilter.allCases) { filter in
                Text(filter.displayName).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Spacing.medium)
        .padding(.bottom, Spacing.small)
        .accessibilityLabel("Show meetings from")
        .accessibilityHint("Lists all meetings, or only App Audio or Microphone meetings")
    }

    @ViewBuilder
    private var listContent: some View {
        if model.isLoading {
            centred {
                ProgressView()
                    .controlSize(.small)
                Text("Reading the save folder…")
                    .textRole(.secondaryBody)
            }
        } else if let message = model.unavailableMessage {
            ContentUnavailableView {
                Label("History Unavailable", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("History unavailable. \(message)")
        } else if model.results.isEmpty {
            VStack(spacing: 0) {
                problemsList
                ContentUnavailableView {
                    Label(isNarrowed ? "No Results" : "No Meetings",
                          systemImage: isNarrowed ? "magnifyingglass" : "tray")
                } description: {
                    Text(emptyListDescription)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                problemsList
                List(model.results, selection: $selection) { result in
                    row(for: result)
                }
                .listStyle(.sidebar)
            }
        }
    }

    /// The damaged session directories, above the meetings that did load.
    ///
    /// They sit outside the selectable list because there is nothing to select:
    /// ScribeKit could not describe them, so it has no detail to show. They are
    /// shown rather than dropped, because silently omitting a session ScribeKit
    /// clearly wrote would tell the user their history is complete when it is
    /// not.
    @ViewBuilder
    private var problemsList: some View {
        if !model.problems.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    StatusBadge(title: "Could Not Be Read", symbolName: "exclamationmark.triangle",
                                tone: .warning, role: .metadata)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(model.problems) { problem in
                        problemRow(for: problem)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
            }
            .frame(maxHeight: LayoutMetrics.problemsListMaxHeight)
            Divider()
        }
    }

    /// One session directory ScribeKit could not describe.
    ///
    /// Nothing here offers to repair one. The record was left exactly as it
    /// was found.
    ///
    /// - Parameter problem: What was wrong, and where.
    /// - Returns: The row view.
    private func problemRow(for problem: HistoryProblem) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            Text(problem.name)
                .textRole(.strongTechnical)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(problem.error.errorDescription ?? "")
                .textRole(.metadata)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// One matching meeting.
    ///
    /// The title leads; the date and capture mode sit under it in the
    /// metadata style; a search match is quoted with the matched words marked,
    /// and the time it was said is set as a timestamp. A status is stated only
    /// when it is not the ordinary one, so the meetings that ended some other
    /// way stand out in a long list instead of every row carrying a badge.
    ///
    /// - Parameter result: The match to present.
    /// - Returns: The row view.
    private func row(for result: HistorySearchResult) -> some View {
        VStack(alignment: .leading, spacing: Spacing.hairline) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                Text(result.session.title)
                    .textRole(.groupTitle)
                    .lineLimit(1)
                Spacer(minLength: Spacing.xSmall)
                if result.session.status.isNoteworthy {
                    statusLabel(result.session.status)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                if let mode = result.session.knownCaptureMode {
                    Image(systemName: mode.symbolName)
                        .imageScale(.small)
                }
                Text(Self.dateAndSourceDescription(for: result.session))
                    .lineLimit(1)
            }
            .textRole(.metadata)
            if let excerpt = result.excerpt {
                Text(Self.highlighted(excerpt))
                    .textRole(.secondaryBody)
                    .lineLimit(3)
                    .padding(.top, Spacing.xSmall)
                Text(excerpt.timestampDescription
                     + (result.transcriptMatchCount > 1 ? " · \(result.transcriptMatchCount) matches" : ""))
                    .textRole(.timestamp)
            }
        }
        .padding(.vertical, Spacing.xSmall)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(result.accessibilityDescription(date: Self.dateDescription(for: result.session)))
    }

    /// A meeting's status as a word, with a symbol in its tone.
    ///
    /// - Parameter status: Where the session stands.
    /// - Returns: The label view.
    private func statusLabel(_ status: HistorySessionStatus) -> some View {
        StatusBadge(title: status.displayName, symbolName: status.symbolName, tone: status.tone, role: .caption)
            .fixedSize()
    }

    private var sidebarFooter: some View {
        HStack {
            Text(countDescription)
                .textRole(.metadata)
            Spacer()
            Button {
                Task { await model.load() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help("Refresh")
            .disabled(model.isLoading)
            .accessibilityHint("Read the save folder again")
        }
        .padding(.horizontal, Spacing.medium)
        .padding(.vertical, Spacing.small)
    }

    /// How many meetings are listed, and how many the folder holds.
    private var countDescription: String {
        guard model.unavailableMessage == nil, !model.isLoading else { return "" }
        return Self.countDescription(
            listed: model.results.count,
            total: model.sessionCount,
            isNarrowed: isNarrowed
        )
    }

    /// Whether a query or a filter is narrowing the list.
    private var isNarrowed: Bool {
        !TranscriptSearch.normalized(model.query).isEmpty || model.filter != .all
    }

    /// What the list says when it has nothing to show.
    private var emptyListDescription: String {
        Self.emptyListDescription(
            query: TranscriptSearch.normalized(model.query),
            filter: model.filter,
            sessionCount: model.sessionCount
        )
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if let selection, let document = model.document(for: selection) {
            HistorySessionDetailView(model: model, document: document)
        } else if model.results.isEmpty {
            ContentUnavailableView(
                "No Meeting Selected",
                systemImage: "text.book.closed",
                description: Text("Past meetings in your save folder appear here. "
                                  + "ScribeKit reads them; it never changes them.")
            )
        } else {
            ContentUnavailableView(
                "No Meeting Selected",
                systemImage: "text.book.closed",
                description: Text("Select a meeting to see its details and a preview of its transcript.")
            )
        }
    }

    // MARK: - Helpers

    /// Centres a small piece of status text in the sidebar.
    ///
    /// - Parameter content: What to centre.
    /// - Returns: The centred view.
    private func centred<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: Spacing.small) {
            content()
        }
        .padding(Spacing.xLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What a row says about when the meeting happened.
    ///
    /// A recorded session has a start; a session with no record has only the
    /// moment its transcript was last written, and that is what is shown
    /// rather than a date derived from the folder's name.
    ///
    /// - Parameter session: The meeting.
    /// - Returns: The description.
    static func dateDescription(for session: HistorySession) -> String {
        if let startedAt = session.startedAt {
            return startedAt.formatted(date: .abbreviated, time: .shortened)
        }
        if let modified = session.transcript.modifiedAt {
            return "Transcript last written \(modified.formatted(date: .abbreviated, time: .shortened))"
        }
        return "Date not recorded"
    }

    /// A row's date, followed by its capture mode when that is known.
    ///
    /// - Parameter session: The meeting.
    /// - Returns: The description.
    static func dateAndSourceDescription(for session: HistorySession) -> String {
        let date = dateDescription(for: session)
        guard let mode = session.knownCaptureMode else { return date }
        return "\(date) · \(mode.displayName)"
    }

    /// The footer's count.
    ///
    /// - Parameters:
    ///   - listed: How many meetings the list shows.
    ///   - total: How many the folder holds.
    ///   - isNarrowed: Whether a query or a filter is narrowing the list.
    /// - Returns: `12 meetings`, or `3 of 12` while the list is narrowed.
    static func countDescription(listed: Int, total: Int, isNarrowed: Bool) -> String {
        guard isNarrowed else { return total == 1 ? "1 meeting" : "\(total) meetings" }
        return "\(listed) of \(total)"
    }

    /// What an empty list says, naming whatever is narrowing it.
    ///
    /// - Parameters:
    ///   - query: The normalised query.
    ///   - filter: The capture filter.
    ///   - sessionCount: How many meetings the folder holds.
    /// - Returns: The sentence.
    static func emptyListDescription(query: String, filter: HistoryCaptureFilter, sessionCount: Int) -> String {
        if sessionCount == 0 { return "No meetings in the save folder yet." }
        switch (query.isEmpty, filter) {
        case (true, .all): return "No meetings in the save folder yet."
        case (true, _): return "No \(filter.displayName) meetings in the save folder."
        case (false, .all): return "No meeting matches “\(query)”."
        case (false, _): return "No \(filter.displayName) meeting matches “\(query)”."
        }
    }

    /// An excerpt with its matched range emphasised.
    ///
    /// The highlight is an attribute applied to a copy for display. The
    /// excerpt's own text is the user's words, unchanged; the ellipses added
    /// here mark where it was cut and are not written to anything.
    ///
    /// - Parameter excerpt: The match to present.
    /// - Returns: The attributed text.
    static func highlighted(_ excerpt: TranscriptExcerpt) -> AttributedString {
        var text = AttributedString(excerpt.text)
        let count = excerpt.text.count
        if excerpt.matchLength > 0, excerpt.matchOffset >= 0, excerpt.matchOffset + excerpt.matchLength <= count {
            let start = text.index(text.startIndex, offsetByCharacters: excerpt.matchOffset)
            let end = text.index(start, offsetByCharacters: excerpt.matchLength)
            text[start..<end].inlinePresentationIntent = .stronglyEmphasized
            text[start..<end].foregroundColor = .primary
            text[start..<end].backgroundColor = Color(nsColor: .findHighlightColor).opacity(TintOpacity.findMatch)
        }
        if excerpt.isTruncatedAtStart { text.insert(AttributedString("… "), at: text.startIndex) }
        if excerpt.isTruncatedAtEnd { text.append(AttributedString(" …")) }
        return text
    }
}

#Preview {
    HistoryView(runtime: MeetingRuntime())
}
