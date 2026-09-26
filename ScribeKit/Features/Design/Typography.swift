//
//  Typography.swift
//  ScribeKit
//

import SwiftUI

/// The job a piece of text does in the interface, which decides how it is set.
///
/// Views name a role rather than a font, so the same kind of text looks the
/// same on every screen and the type system can be read, tested and changed in
/// one place. Every role is built on a system text style, which keeps it
/// scaling with the text size macOS and assistive technology ask for.
///
/// Hierarchy comes from size, weight and colour together. Semibold is kept for
/// titles; nothing is bold; secondary information is smaller and quieter
/// rather than heavier.
nonisolated enum TextRole: CaseIterable, Sendable {

    /// The one title a screen or pane leads with: a running meeting's name, a
    /// past meeting's name.
    case pageTitle

    /// A heading over a block of a pane, such as Review or Transcript.
    case sectionTitle

    /// The name of one item inside a group: a History row, a notice.
    case groupTitle

    /// Ordinary reading text.
    case body

    /// Reading text that deserves a little more weight than its neighbours.
    case emphasizedBody

    /// Explanations and supporting sentences.
    case secondaryBody

    /// A caption under a control, or a count in a footer.
    case caption

    /// Facts about something — a date, a capture mode, a status word.
    case metadata

    /// Values that are identifiers rather than prose: paths, locales, sizes,
    /// audio formats.
    case technical

    /// A technical value that is the point of the line it is on.
    case strongTechnical

    /// A technical value in a column of values, such as a path beside a
    /// label: the monospaced face, sized to sit beside body text.
    case technicalValue

    /// A time within a transcript or a meeting.
    case timestamp

    /// A running meeting's elapsed time, read at a glance.
    case elapsed

    /// Recognised speech.
    case transcript

    /// Text the user edits as source, such as Markdown notes.
    case editor

    /// The sentence a warning or an error is carried in.
    case notice

    /// The title of an empty or unavailable state.
    case emptyStateTitle

    /// How the role is set.
    var spec: TypeSpec {
        switch self {
        case .pageTitle: TypeSpec(style: .title2, weight: .semibold)
        case .sectionTitle: TypeSpec(style: .title3, weight: .semibold)
        case .groupTitle: TypeSpec(style: .body, weight: .semibold)
        case .body: TypeSpec(style: .body)
        case .emphasizedBody: TypeSpec(style: .body, weight: .medium)
        case .secondaryBody: TypeSpec(style: .callout, tone: .secondary)
        case .caption: TypeSpec(style: .caption, tone: .secondary)
        case .metadata: TypeSpec(style: .subheadline, tone: .secondary)
        case .technical: TypeSpec(style: .subheadline, design: .monospaced, tone: .secondary)
        case .strongTechnical: TypeSpec(style: .subheadline, weight: .medium, design: .monospaced)
        case .technicalValue: TypeSpec(style: .callout, design: .monospaced)
        case .timestamp: TypeSpec(style: .subheadline, digits: .monospaced, tone: .secondary)
        case .elapsed: TypeSpec(style: .title3, weight: .medium, digits: .monospaced)
        case .transcript: TypeSpec(style: .title3)
        case .editor: TypeSpec(style: .body, design: .monospaced)
        case .notice: TypeSpec(style: .callout)
        case .emptyStateTitle: TypeSpec(style: .title3, weight: .semibold)
        }
    }
}

/// How one ``TextRole`` is set: a system text style, a weight, a design and a
/// colour.
///
/// A value rather than a `Font`, so the rules the type system keeps — which
/// roles are monospaced, how rare heavy weights are — can be tested without
/// rendering anything.
nonisolated struct TypeSpec: Equatable, Sendable {

    /// The letterforms: the system's proportional face, or its monospaced one.
    enum Design: Equatable, Sendable {
        /// SF Pro.
        case standard
        /// SF Mono.
        case monospaced
    }

    /// How digits are spaced.
    enum Digits: Equatable, Sendable {
        /// The face's own figures.
        case proportional
        /// Tabular figures, so a changing time does not shift sideways.
        case monospaced
    }

    /// How loudly the text speaks relative to its neighbours.
    enum Tone: Equatable, Sendable {
        /// The label colour.
        case primary
        /// The secondary label colour.
        case secondary
    }

    /// The system text style the size is taken from, so the role scales with
    /// the text size in effect.
    let style: Font.TextStyle

    /// The weight.
    let weight: Font.Weight

    /// The letterforms.
    let design: Design

    /// How digits are spaced.
    let digits: Digits

    /// The colour.
    let tone: Tone

    /// Creates a specification.
    ///
    /// - Parameters:
    ///   - style: The system text style.
    ///   - weight: The weight; regular unless stated.
    ///   - design: The letterforms; SF Pro unless stated.
    ///   - digits: How digits are spaced; proportional unless stated.
    ///   - tone: The colour; primary unless stated.
    init(
        style: Font.TextStyle,
        weight: Font.Weight = .regular,
        design: Design = .standard,
        digits: Digits = .proportional,
        tone: Tone = .primary
    ) {
        self.style = style
        self.weight = weight
        self.design = design
        self.digits = digits
        self.tone = tone
    }

    /// The font the specification describes.
    var font: Font {
        let font = Font.system(style, design: design == .monospaced ? .monospaced : .default, weight: weight)
        return digits == .monospaced ? font.monospacedDigit() : font
    }
}

extension Font {

    /// The font for one role, for a place that sets a font without a colour —
    /// an attributed string, or a control that styles its own label.
    ///
    /// - Parameter role: The role.
    /// - Returns: The role's font.
    static func role(_ role: TextRole) -> Font {
        role.spec.font
    }
}

extension View {

    /// Sets this text in one role's font and colour.
    ///
    /// - Parameter role: What the text is for.
    /// - Returns: The styled view.
    func textRole(_ role: TextRole) -> some View {
        modifier(TextRoleModifier(spec: role.spec))
    }
}

/// Applies a ``TypeSpec`` to a view.
private struct TextRoleModifier: ViewModifier {

    /// The specification to apply.
    let spec: TypeSpec

    func body(content: Content) -> some View {
        switch spec.tone {
        case .primary: content.font(spec.font)
        case .secondary: content.font(spec.font).foregroundStyle(.secondary)
        }
    }
}
