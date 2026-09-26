//
//  Metrics.swift
//  ScribeKit
//

import CoreGraphics

/// The spacing steps the interface is laid out on.
///
/// A short scale rather than whatever number looked right at the time, so
/// related things sit at the same distance on every screen. Native controls
/// keep their own internal metrics; these govern the space between them.
nonisolated enum Spacing {

    /// Between a line and the line that qualifies it.
    static let hairline: CGFloat = 2

    /// Between an icon and its word, or items in one line of metadata.
    static let xSmall: CGFloat = 4

    /// Between related lines, and between buttons in a row.
    static let small: CGFloat = 8

    /// Inside a notice or a card, and between rows of a list.
    static let medium: CGFloat = 12

    /// Between the blocks of a pane.
    static let large: CGFloat = 16

    /// The margin around a pane's content.
    static let xLarge: CGFloat = 20

    /// Between the major sections of a pane.
    static let xxLarge: CGFloat = 28
}

/// Corner radii, in the few sizes the interface uses.
nonisolated enum CornerRadius {

    /// A highlight behind a few words or a transcript passage.
    static let small: CGFloat = 5

    /// A notice, a card or an editor's frame.
    static let medium: CGFloat = 8
}

/// Sizes that shape the window and its columns.
nonisolated enum LayoutMetrics {

    /// The narrowest the main window may be: History's sidebar beside a
    /// detail pane still wide enough to read a transcript in.
    static let windowMinWidth: CGFloat = 680

    /// The shortest the main window may be.
    static let windowMinHeight: CGFloat = 560

    /// The main window's size on first launch.
    static let windowDefaultWidth: CGFloat = 900

    /// The main window's height on first launch.
    static let windowDefaultHeight: CGFloat = 760

    /// The widest a setup form grows to. Past this a form's labels and values
    /// drift too far apart to read as pairs.
    static let formMaxWidth: CGFloat = 720

    /// The widest a column of transcript text grows to, which keeps lines to
    /// a comfortable reading length in a wide window.
    static let readableWidth: CGFloat = 760

    /// History's sidebar: narrowest, preferred and widest.
    static let sidebarMinWidth: CGFloat = 250
    /// History's sidebar preferred width.
    static let sidebarIdealWidth: CGFloat = 290
    /// History's sidebar widest.
    static let sidebarMaxWidth: CGFloat = 400

    /// The width reserved for a live transcript's `mm:ss` offsets at the
    /// default text size; scaled with the text size where it is used.
    static let offsetColumnWidth: CGFloat = 44

    /// The width reserved for a written transcript's `h:mm:ss AM` times at
    /// the default text size; scaled with the text size where it is used.
    static let clockColumnWidth: CGFloat = 78

    /// The extra space between the lines of one transcript passage.
    static let transcriptLineSpacing: CGFloat = 3

    /// The space between one transcript passage and the next.
    static let transcriptPassageSpacing: CGFloat = 10

    /// The height of the notes editor before the user types into it.
    static let notesEditorMinHeight: CGFloat = 110

    /// The tallest the list of unreadable sessions grows before it scrolls.
    static let problemsListMaxHeight: CGFloat = 160
}

/// How strongly a tinted surface shows its tint.
nonisolated enum TintOpacity {

    /// The fill behind a notice.
    static let noticeFill: Double = 0.10

    /// The outline around a notice.
    static let noticeStroke: Double = 0.28

    /// A passage that was just revealed from Review.
    static let revealedPassage: Double = 0.14

    /// A find match other than the current one.
    static let findMatch: Double = 0.28
}
