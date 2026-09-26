//
//  Components.swift
//  ScribeKit
//

import SwiftUI

/// A state stated as a symbol and a word, the symbol in the state's colour.
///
/// Deliberately not a filled pill: the word carries the meaning, the tinted
/// symbol lets the eye find it, and a row of these stays quiet enough to sit
/// beside ordinary text.
struct StatusBadge: View {

    /// The word naming the state.
    let title: String

    /// The symbol drawn before the word.
    let symbolName: String

    /// The colour of the symbol.
    let tone: StatusTone

    /// The type role the word is set in.
    var role: TextRole = .metadata

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbolName)
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
        }
        .labelStyle(BadgeLabelStyle())
        .textRole(role)
    }
}

/// An icon and its title set close together on one baseline.
private struct BadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            configuration.icon
            configuration.title
        }
    }
}

/// A block of text that needs to be seen: a failure, a gap in the transcript,
/// something that has to be done before a meeting can start.
///
/// The symbol, the optional title and the message say what it is; the tinted
/// surface makes it findable. The fill is faint so a warning is noticed
/// without the screen around it reading as an error.
struct NoticeView<Actions: View>: View {

    /// How much attention the notice asks for.
    let tone: StatusTone

    /// The symbol that leads the notice.
    let symbolName: String

    /// A short statement of what happened, or `nil` for a one-sentence notice.
    let title: String?

    /// What it means, in a sentence or two.
    let message: String?

    /// Buttons that act on the notice.
    let actions: Actions

    /// Creates a notice.
    ///
    /// - Parameters:
    ///   - tone: How much attention it asks for.
    ///   - symbolName: The leading symbol.
    ///   - title: What happened, in a few words.
    ///   - message: What it means.
    ///   - actions: Buttons that act on it.
    init(
        tone: StatusTone,
        symbolName: String,
        title: String? = nil,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) {
        self.tone = tone
        self.symbolName = symbolName
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Image(systemName: symbolName)
                .font(.role(.notice))
                .foregroundStyle(tone.color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    if let title {
                        Text(title)
                            .textRole(.groupTitle)
                    }
                    if let message {
                        Text(message)
                            .textRole(title == nil ? .notice : .secondaryBody)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine)
                actions
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.medium)
        .background {
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .fill(tone.color.opacity(TintOpacity.noticeFill))
            RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                .strokeBorder(tone.color.opacity(TintOpacity.noticeStroke))
        }
        .accessibilityElement(children: .contain)
    }
}

extension NoticeView where Actions == EmptyView {

    /// Creates a notice with nothing to press.
    ///
    /// - Parameters:
    ///   - tone: How much attention it asks for.
    ///   - symbolName: The leading symbol.
    ///   - title: What happened, in a few words.
    ///   - message: What it means.
    init(tone: StatusTone, symbolName: String, title: String? = nil, message: String? = nil) {
        self.init(tone: tone, symbolName: symbolName, title: title, message: message) { EmptyView() }
    }
}

/// The heading over one block of a pane that is not a form.
///
/// Forms keep the system's own section headers; this is the same idea for the
/// scrolling panes, with room for a count or a button on the trailing side.
struct SectionHeading<Accessory: View>: View {

    /// The heading's text.
    let title: String

    /// What sits at the trailing edge.
    let accessory: Accessory

    /// Creates a heading.
    ///
    /// - Parameters:
    ///   - title: The heading's text.
    ///   - accessory: What sits at the trailing edge.
    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            Text(title)
                .textRole(.sectionTitle)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Spacing.small)
            accessory
        }
    }
}

extension SectionHeading where Accessory == EmptyView {

    /// Creates a heading with nothing beside it.
    ///
    /// - Parameter title: The heading's text.
    init(_ title: String) {
        self.init(title) { EmptyView() }
    }
}

/// One passage of a transcript: when it was said, and what was said.
///
/// Shared by the live transcript and History's preview, so a passage reads
/// the same during a meeting as it does afterwards. The time sits in a column
/// of its own at the leading edge, quieter than the speech and aligned on its
/// first line, so the words form one readable column and the times one
/// scannable one.
struct TranscriptPassageRow: View {

    /// The time the passage is labelled with.
    let timestamp: String

    /// The recognised words, possibly with find matches marked up.
    let text: AttributedString

    /// The width the time column keeps, before scaling for text size.
    let timestampWidth: CGFloat

    /// Whether the words are a live guess rather than finalised speech.
    var isProvisional = false

    @ScaledMetric(relativeTo: .subheadline) private var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
            Text(timestamp)
                .textRole(.timestamp)
                .frame(minWidth: timestampWidth * scale, alignment: .leading)
            Text(text)
                .textRole(.transcript)
                .foregroundStyle(isProvisional ? .secondary : .primary)
                .italic(isProvisional)
                .lineSpacing(LayoutMetrics.transcriptLineSpacing)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A labelled fact in a two-column list: the label quiet, the value readable.
struct FactRow: View {

    /// What the value is.
    let label: String

    /// The value.
    let value: String

    /// Whether the value is an identifier to be set in the monospaced face.
    var isTechnical = false

    /// Whether to truncate in the middle, as a path should be.
    var truncatesMiddle = false

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label)
                .textRole(.metadata)
                .gridColumnAlignment(.trailing)
                .accessibilityHidden(true)
            Text(value)
                .textRole(isTechnical ? .technicalValue : .body)
                .lineLimit(truncatesMiddle ? 1 : nil)
                .truncationMode(truncatesMiddle ? .middle : .tail)
                .fixedSize(horizontal: false, vertical: !truncatesMiddle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(truncatesMiddle ? value : "")
                .accessibilityLabel(label)
                .accessibilityValue(value)
        }
    }
}
