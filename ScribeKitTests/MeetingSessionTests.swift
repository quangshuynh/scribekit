//
//  MeetingSessionTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("MeetingSession")
struct MeetingSessionTests {

    private static let destination = URL(fileURLWithPath: "/tmp/scribekit-tests", isDirectory: true)

    private static func makeSession(title: String = "Weekly Sync") -> MeetingSession {
        MeetingSession(title: title, destination: destination)
    }

    @Test("A new session is idle and retains no audio")
    func defaults() {
        let session = Self.makeSession()
        #expect(session.state == .idle)
        #expect(session.audioRetention == .none)
        #expect(session.selectedSources.isEmpty)
    }

    @Test("Identity is independent of title", arguments: ["", "  ", "Renamed"])
    func identityIsStable(newTitle: String) {
        var session = Self.makeSession()
        let id = session.id
        session.title = newTitle
        #expect(session.id == id)
    }

    @Test("Sessions with the same fields but different identifiers are not equal")
    func equalityUsesIdentifier() {
        let createdAt = Date()
        let first = MeetingSession(title: "Sync", createdAt: createdAt, destination: Self.destination)
        let second = MeetingSession(title: "Sync", createdAt: createdAt, destination: Self.destination)
        #expect(first != second)
        #expect(first == first)
    }

    @Test("Blank titles fall back to a placeholder", arguments: ["", "   ", "\n\t"])
    func blankTitlesUsePlaceholder(title: String) {
        #expect(Self.makeSession(title: title).displayTitle == MeetingSession.untitledPlaceholder)
    }

    @Test("Display titles are trimmed")
    func displayTitleIsTrimmed() {
        #expect(Self.makeSession(title: "  Weekly Sync  ").displayTitle == "Weekly Sync")
    }

    @Test("A session follows the meeting lifecycle")
    func lifecycle() throws {
        var session = Self.makeSession()
        for next in [MeetingState.preparing, .transcribing, .paused, .transcribing, .stopping, .completed] {
            try session.transition(to: next)
            #expect(session.state == next)
        }
    }

    @Test("Illegal transitions throw and leave the session unchanged")
    func illegalTransition() {
        var session = Self.makeSession()
        #expect(throws: MeetingStateError.invalidTransition(from: .idle, to: .completed)) {
            try session.transition(to: .completed)
        }
        #expect(session.state == .idle)
    }

    @Test("Sessions round-trip through Codable")
    func codableRoundTrip() throws {
        var session = Self.makeSession()
        session.audioRetention = .compressed
        session.selectedSources = [.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")]
        try session.transition(to: .preparing)

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(MeetingSession.self, from: data)
        #expect(decoded == session)
        #expect(decoded.state == .preparing)
    }
}
