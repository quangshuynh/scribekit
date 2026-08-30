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

    /// Creates the screen.
    ///
    /// - Parameters:
    ///   - runtime: The application's meeting owner.
    ///   - model: The History state, or `nil` to build one that reads the
    ///     real save folder. Previews and tests substitute their own.
    init(runtime: MeetingRuntime, model: HistoryModel? = nil) {
        self.runtime = runtime
        _model = State(initialValue: model ?? HistoryModel())
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 420)
        } detail: {
            detail
        }
        .task { await model.load() }
        .onDisappear { model.stopPlayback() }
        .onChange(of: selection) { _, _ in model.stopPlayback() }
        .onChange(of: runtime.status.isActive) { wasActive, isActive in
            guard wasActive, !isActive else { return }
            Task { await model.load() }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            listContent
            Divider()
            sidebarFooter
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search meetings", text: Bindable(model).query)
                .textFieldStyle(.plain)
                .accessibilityLabel("Search past meetings")
                .accessibilityHint("Searches meeting titles and the speech in their transcripts")
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var listContent: some View {
        if model.isLoading {
            centred {
                ProgressView()
                    .controlSize(.small)
                Text("Reading the save folder…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let message = model.unavailableMessage {
            centred {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("History unavailable. \(message)")
            }
        } else if model.results.isEmpty {
            VStack(spacing: 0) {
                problemsList
                centred {
                    Text(model.sessionCount == 0
                         ? "No meetings in the save folder yet."
                         : "No meeting matches “\(model.query)”.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
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
                VStack(alignment: .leading, spacing: 8) {
                    Text("Could Not Be Read")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(model.problems) { problem in
                        problemRow(for: problem)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(maxHeight: 160)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(problem.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(problem.error.errorDescription ?? "")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// One matching meeting.
    ///
    /// - Parameter result: The match to present.
    /// - Returns: The row view.
    private func row(for result: HistorySearchResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(result.session.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 4)
                statusLabel(result.session.status)
            }
            Text(Self.dateDescription(for: result.session))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let excerpt = result.excerpt {
                Text(Self.highlighted(excerpt))
                    .font(.caption)
                    .lineLimit(3)
                Text("at \(excerpt.timestampDescription)"
                     + (result.transcriptMatchCount > 1 ? " · \(result.transcriptMatchCount) matches" : ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    /// A meeting's status as a word rather than a colour.
    ///
    /// - Parameter status: Where the session stands.
    /// - Returns: The label view.
    private func statusLabel(_ status: HistorySessionStatus) -> some View {
        Text(status.displayName)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary, in: Capsule())
            .foregroundStyle(.secondary)
    }

    private var sidebarFooter: some View {
        HStack {
            Text(countDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Refresh") {
                Task { await model.load() }
            }
            .controlSize(.small)
            .disabled(model.isLoading)
            .accessibilityHint("Read the save folder again")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    /// How many meetings are listed, and how many the folder holds.
    private var countDescription: String {
        guard model.unavailableMessage == nil, !model.isLoading else { return "" }
        if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return model.sessionCount == 1 ? "1 meeting" : "\(model.sessionCount) meetings"
        }
        return "\(model.results.count) of \(model.sessionCount)"
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
        VStack(spacing: 8) {
            content()
        }
        .padding(20)
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
        }
        if excerpt.isTruncatedAtStart { text.insert(AttributedString("… "), at: text.startIndex) }
        if excerpt.isTruncatedAtEnd { text.append(AttributedString(" …")) }
        return text
    }
}

#Preview {
    HistoryView(runtime: MeetingRuntime())
}
