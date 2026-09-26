//
//  DesignSystemTests.swift
//  ScribeKitTests
//

import AppKit
import Foundation
import SwiftUI
import Testing
@testable import ScribeKit

/// The rules the type system keeps, checked on the specifications rather than
/// on rendered pixels.
@Suite("Typography")
struct TypographyTests {

    /// The point size a system text style resolves to at the default text
    /// size.
    private func pointSize(_ style: Font.TextStyle) -> CGFloat {
        let ns: NSFont.TextStyle = switch style {
        case .largeTitle: .largeTitle
        case .title: .title1
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .subheadline: .subheadline
        case .callout: .callout
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        default: .body
        }
        return NSFont.preferredFont(forTextStyle: ns).pointSize
    }

    @Test("Nothing is set bold or heavier; emphasis comes from size and colour as well as weight")
    func boldIsRare() {
        let heavy: Set<Font.Weight> = [.bold, .heavy, .black]
        #expect(TextRole.allCases.allSatisfy { !heavy.contains($0.spec.weight) })
    }

    @Test("Only titles are semibold")
    func semiboldIsForTitles() {
        let semibold = Set(TextRole.allCases.filter { $0.spec.weight == .semibold })
        #expect(semibold == [.pageTitle, .sectionTitle, .groupTitle, .emptyStateTitle])
    }

    @Test("Identifiers are set in the monospaced face; speech and prose are not")
    func technicalValuesAreMonospaced() {
        let monospaced = Set(TextRole.allCases.filter { $0.spec.design == .monospaced })
        #expect(monospaced == [.technical, .strongTechnical, .technicalValue, .editor])
        #expect(TextRole.transcript.spec.design == .standard)
    }

    @Test("Times use tabular figures, so a changing time does not move sideways")
    func timesHaveTabularDigits() {
        #expect(TextRole.timestamp.spec.digits == .monospaced)
        #expect(TextRole.elapsed.spec.digits == .monospaced)
        #expect(TextRole.transcript.spec.digits == .proportional)
    }

    @Test("Speech is the largest reading text and quieter things are smaller")
    func speechLeadsItsMetadata() {
        let transcript = pointSize(TextRole.transcript.spec.style)
        #expect(transcript > pointSize(TextRole.body.spec.style))
        #expect(transcript > pointSize(TextRole.timestamp.spec.style))
        #expect(transcript > pointSize(TextRole.metadata.spec.style))
        #expect(pointSize(TextRole.pageTitle.spec.style) > pointSize(TextRole.sectionTitle.spec.style))
        #expect(pointSize(TextRole.sectionTitle.spec.style) > pointSize(TextRole.groupTitle.spec.style))
        #expect(pointSize(TextRole.secondaryBody.spec.style) < pointSize(TextRole.body.spec.style))
    }

    @Test("Speech is primary; times and metadata step back in the secondary colour")
    func toneHierarchy() {
        #expect(TextRole.transcript.spec.tone == .primary)
        #expect(TextRole.pageTitle.spec.tone == .primary)
        for role in [TextRole.timestamp, .metadata, .secondaryBody, .caption, .technical] {
            #expect(role.spec.tone == .secondary, "\(role)")
        }
    }

    @Test("Every role resolves to a font")
    func everyRoleHasAFont() {
        for role in TextRole.allCases {
            _ = Font.role(role)
        }
    }
}

/// How states are coloured, and that none of them is carried by colour alone.
@Suite("Status tones")
struct StatusToneTests {

    /// Whether SF Symbols has a symbol by this name on this Mac.
    private func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    @Test("A prerequisite that blocks a start is a warning, not a failure; a satisfied one is positive")
    func readinessTones() {
        #expect(MeetingStartReadiness.Status.blocked.tone == .warning)
        #expect(MeetingStartReadiness.Status.satisfied.tone == .positive)
        #expect(MeetingStartReadiness.Status.checking.tone == .neutral)
        #expect(MeetingStartReadiness.Status.advisory.tone == .attention)
    }

    @Test("Review emphasis is proportionate: never an error, and nothing at all for the lowest priority")
    func reviewTonesAreProportionate() {
        let tones = TranscriptReviewPriority.allCases.map(\.tone)
        #expect(!tones.contains(.critical))
        #expect(TranscriptReviewPriority.high.tone == .warning)
        #expect(TranscriptReviewPriority.medium.tone == .attention)
        #expect(TranscriptReviewPriority.low.tone == .neutral)
    }

    @Test("Each review priority has a word and a symbol of its own")
    func reviewPrioritiesAreDistinctWithoutColour() {
        let priorities = TranscriptReviewPriority.allCases
        #expect(Set(priorities.map(\.displayName)).count == priorities.count)
        #expect(Set(priorities.map(\.symbolName)).count == priorities.count)
    }

    @Test("Only a finished meeting goes unstated in the History list; a failure is critical")
    func historyStatuses() {
        let statuses = HistorySessionStatus.allCases
        #expect(statuses.filter { !$0.isNoteworthy } == [.completed])
        #expect(HistorySessionStatus.failed.tone == .critical)
        #expect(HistorySessionStatus.interrupted.tone == .warning)
        #expect(Set(statuses.map(\.symbolName)).count == statuses.count)
        #expect(Set(statuses.map(\.displayName)).count == statuses.count)
    }

    @Test("Every symbol the interface names exists")
    func symbolsExist() {
        var names = MeetingStartReadiness.Status.allCasesForTesting.map(\.symbolName)
        names += TranscriptReviewPriority.allCases.map(\.symbolName)
        names += TranscriptReviewReason.allCases.map(\.symbolName)
        names += HistorySessionStatus.allCases.map(\.symbolName)
        names += CaptureMode.allCases.map(\.symbolName)
        for name in names {
            #expect(exists(name), "\(name) is not an SF Symbol")
        }
    }
}

extension MeetingStartReadiness.Status {
    /// Every status, for tests that walk them.
    static let allCasesForTesting: [Self] = [.satisfied, .checking, .advisory, .blocked]
}

/// How locations are written on screen.
@Suite("Display paths")
struct DisplayPathTests {

    @Test("A path inside the home folder is written from ~")
    func abbreviatesHome() {
        #expect(DisplayPath.abbreviated("/Users/ada/Documents/Meetings", home: "/Users/ada") == "~/Documents/Meetings")
        #expect(DisplayPath.abbreviated("/Users/ada/Documents/", home: "/Users/ada/") == "~/Documents/")
        #expect(DisplayPath.abbreviated("/Users/ada", home: "/Users/ada") == "~")
    }

    @Test("A path that only shares a prefix with the home folder is left alone")
    func siblingIsNotAbbreviated() {
        #expect(DisplayPath.abbreviated("/Users/adam/Meetings", home: "/Users/ada") == "/Users/adam/Meetings")
        #expect(DisplayPath.abbreviated("/Volumes/Work/Meetings", home: "/Users/ada") == "/Volumes/Work/Meetings")
    }

    @Test("Without a home folder the path is shown as it is")
    func noHome() {
        #expect(DisplayPath.abbreviated("/Users/ada/Meetings", home: nil) == "/Users/ada/Meetings")
        #expect(DisplayPath.abbreviated("/Users/ada/Meetings", home: "") == "/Users/ada/Meetings")
    }

    @Test("The home folder is the account's own, not the sandbox container")
    func userHomeIsNotTheContainer() throws {
        let home = try #require(DisplayPath.userHome)
        #expect(!home.contains("/Library/Containers/"))
    }
}
