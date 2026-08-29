//
//  SessionDirectoryNameTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("SessionDirectoryName")
struct SessionDirectoryNameTests {

    /// 2026-08-31 00:00:00 UTC.
    private let midnight = Date(timeIntervalSince1970: 1_788_134_400)

    /// 2026-08-31 13:45:07 UTC.
    private let afternoon = Date(timeIntervalSince1970: 1_788_183_907)

    /// 2026-08-31 02:30:00 UTC, which is still 30 August in New York.
    private let earlyMorning = Date(timeIntervalSince1970: 1_788_143_400)

    private let utc = TimeZone(identifier: "UTC")!

    @Test("A name combines the session date with a slug of the title")
    func combinesDateAndTitle() {
        let name = SessionDirectoryName.make(date: midnight, title: "iOS Training Day 2", timeZone: utc)
        #expect(name == "2026-08-31-ios-training-day-2")
    }

    @Test("The date is formatted with fixed digits and the Gregorian calendar")
    func formatsDateDeterministically() {
        #expect(SessionDirectoryName.datePrefix(for: afternoon, timeZone: utc) == "2026-08-31")
    }

    @Test("The date is the local day, not the UTC day")
    func usesTheGivenTimeZone() {
        let newYork = TimeZone(identifier: "America/New_York")!
        #expect(SessionDirectoryName.datePrefix(for: earlyMorning, timeZone: newYork) == "2026-08-30")
        #expect(SessionDirectoryName.datePrefix(for: earlyMorning, timeZone: utc) == "2026-08-31")
    }

    @Test("Titles are lower-cased, folded and joined by single hyphens", arguments: [
        ("Weekly Standup", "weekly-standup"),
        ("WEEKLY   STANDUP", "weekly-standup"),
        ("Café Résumé Review", "cafe-resume-review"),
        ("Q3 // Planning — Notes", "q3-planning-notes"),
        ("  Kickoff  ", "kickoff"),
        ("---Kickoff---", "kickoff"),
        ("Design/Review: v2.1", "design-review-v2-1")
    ])
    func normalisesTitles(title: String, expected: String) {
        #expect(SessionDirectoryName.slug(for: title) == expected)
    }

    @Test("A title with nothing usable falls back rather than producing an empty name", arguments: [
        "", "   ", "!!! ???", "日本語"
    ])
    func fallsBackForUnusableTitles(title: String) {
        #expect(SessionDirectoryName.slug(for: title) == SessionDirectoryName.fallbackSlug)
    }

    @Test("A long title is truncated on a word boundary")
    func truncatesLongTitles() {
        let title = "Quarterly platform architecture review with the whole engineering organisation"
        let slug = SessionDirectoryName.slug(for: title)
        #expect(slug.count <= SessionDirectoryName.maximumSlugLength)
        #expect(!slug.hasSuffix("-"))
        #expect(slug == "quarterly-platform-architecture-review-with-the-whole")
    }

    @Test("A single word longer than the limit is cut to the limit")
    func truncatesOneLongWord() {
        let slug = SessionDirectoryName.slug(for: String(repeating: "a", count: 100))
        #expect(slug.count == SessionDirectoryName.maximumSlugLength)
    }

    @Test("A free name is used unchanged")
    func keepsFreeNames() {
        let name = SessionDirectoryName.make(date: midnight, title: "Standup", timeZone: utc) { _ in false }
        #expect(name == "2026-08-31-standup")
    }

    @Test("A taken name gains the lowest free numeric suffix")
    func addsCollisionSuffix() {
        let taken: Set<String> = ["2026-08-31-standup", "2026-08-31-standup-2"]
        let name = SessionDirectoryName.make(date: midnight, title: "Standup", timeZone: utc) { taken.contains($0) }
        #expect(name == "2026-08-31-standup-3")
    }

    @Test("An exhausted numeric range falls back to the session's time of day")
    func fallsBackToTimeOfDay() {
        let name = SessionDirectoryName.make(date: afternoon, title: "Standup", timeZone: utc) { _ in true }
        #expect(name == "2026-08-31-standup-134507")
    }

    @Test("Naming is deterministic for the same inputs")
    func isDeterministic() {
        let first = SessionDirectoryName.make(date: afternoon, title: "Board Sync", timeZone: utc)
        let second = SessionDirectoryName.make(date: afternoon, title: "Board Sync", timeZone: utc)
        #expect(first == second)
    }
}
