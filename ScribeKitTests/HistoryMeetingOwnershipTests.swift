//
//  HistoryMeetingOwnershipTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// A save folder the History model can restore, without a bookmark or the
/// sandbox.
private nonisolated final class StubSaveLocation: SaveLocationPersisting, @unchecked Sendable {
    private let folder: URL

    init(_ folder: URL) { self.folder = folder }

    func save(_ url: URL) throws {}
    func restore() throws -> URL? { folder }
    func clear() throws {}
}

/// History is a view, not an owner.
///
/// The application-scoped ``MeetingRuntime`` introduced with background
/// operation is the only thing that starts, stops or holds a meeting. These
/// tests prove that opening History, searching it and refreshing it while a
/// meeting runs leave capture, recognition, the transcript writer and the
/// process activity assertion exactly as they were, and that the menu bar goes
/// on describing the same meeting.
@MainActor
@Suite("History and the active meeting")
struct HistoryMeetingOwnershipTests {

    private let meet = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    /// Everything one runtime is built over, so a test can inspect any of it.
    private struct Meeting {
        let runtime: MeetingRuntime
        let capturer: FakeCapturer
        let transcriber: FakeSpeechTranscriber
        let persistence: FakeTranscriptPersistence
        let activity: FakeMeetingActivity
    }

    /// Builds an application-scoped runtime over doubles, prepared as the
    /// window prepares it.
    ///
    /// - Returns: The runtime and everything behind it.
    private func makeMeeting() async -> Meeting {
        let transcriber = FakeSpeechTranscriber()
        let persistence = FakeTranscriptPersistence()
        let activity = FakeMeetingActivity()
        var capturer: FakeCapturer!
        let runtime = MeetingRuntime(
            monitor: AudioCaptureActivityMonitor(minimumPublishInterval: .zero),
            transcriber: transcriber,
            persistence: persistence,
            audio: FakeAudioRetention(),
            elapsed: MeetingElapsedClock(now: { Date(timeIntervalSince1970: 1_000) }, interval: nil),
            processActivity: activity,
            makeCapturer: { consumer in
                capturer = FakeCapturer(consumer: consumer)
                return capturer
            }
        )
        await runtime.prepare()
        return Meeting(
            runtime: runtime,
            capturer: capturer,
            transcriber: transcriber,
            persistence: persistence,
            activity: activity
        )
    }

    /// A History model over an in-memory save folder holding one past meeting.
    private func makeHistory() throws -> HistoryModel {
        let store = FakeHistoryStore()
        try store.addSession(
            destination.appending(path: "2026-08-29-earlier", directoryHint: .isDirectory),
            in: destination,
            metadata: SessionRecoveryMetadata(
                sessionID: UUID(),
                title: "An Earlier Meeting",
                startedAt: TranscriptFixture.startedAt,
                sourceNames: ["QuickTime Player"],
                localeIdentifier: "en-US",
                status: .completed,
                endedAt: TranscriptFixture.startedAt.addingTimeInterval(120)
            ),
            transcript: TranscriptFixture.transcript(
                title: "An Earlier Meeting",
                texts: ["Something that was said last week."]
            )
        )
        return HistoryModel(
            service: HistoryService(store: store, access: FakeSecurityScopedAccess()),
            saveLocation: StubSaveLocation(destination)
        )
    }

    /// What the menu bar would show right now.
    private func menuBar(_ runtime: MeetingRuntime) -> MeetingMenuBarPresentation {
        MeetingMenuBarPresentation(
            status: runtime.status,
            meeting: runtime.meeting,
            transcript: runtime.persistenceState.layout?.transcriptURL,
            audio: runtime.audioRetentionState.url,
            canStop: runtime.canStop
        )
    }

    @Test("Opening, searching and refreshing History leaves the meeting running")
    func historyDoesNotDisturbTheMeeting() async throws {
        let meeting = await makeMeeting()
        await meeting.runtime.start(MeetingStartRequest(
            title: "Weekly Sync",
            sources: [meet],
            destination: destination,
            audioRetention: .none
        ))
        #expect(meeting.runtime.status == .transcribing)
        let startCount = meeting.capturer.startCount
        let before = menuBar(meeting.runtime)

        let history = try makeHistory()
        await history.load()
        history.query = "said last week"
        #expect(history.results.count == 1)
        history.query = ""
        await history.load()

        #expect(meeting.runtime.status == .transcribing)
        #expect(meeting.capturer.startCount == startCount)
        #expect(meeting.capturer.stopCount == 0)
        #expect(meeting.transcriber.startCount == 1)
        #expect(meeting.transcriber.stopCount == 0)
        #expect(meeting.persistence.isOpen)
        #expect(meeting.activity.isAsserted)
        #expect(meeting.runtime.meeting?.title == "Weekly Sync")
        #expect(menuBar(meeting.runtime) == before)
    }

    @Test("A History listing never names the running meeting's own runtime")
    func historyListsFilesNotRuntimes() async throws {
        let meeting = await makeMeeting()
        await meeting.runtime.start(MeetingStartRequest(
            title: "Weekly Sync",
            sources: [meet],
            destination: destination,
            audioRetention: .none
        ))

        let history = try makeHistory()
        await history.load()

        #expect(history.results.map(\.session.title) == ["An Earlier Meeting"])
        #expect(meeting.runtime.status == .transcribing)
    }

    @Test("Stopping the meeting is unaffected by History having been opened")
    func stopStillWorksAfterHistory() async throws {
        let meeting = await makeMeeting()
        await meeting.runtime.start(MeetingStartRequest(
            title: "Weekly Sync",
            sources: [meet],
            destination: destination,
            audioRetention: .none
        ))

        let history = try makeHistory()
        await history.load()
        await meeting.runtime.stop()

        #expect(meeting.runtime.status == .completed)
        #expect(meeting.capturer.stopCount == 1)
        #expect(meeting.transcriber.stopCount == 1)
        #expect(!meeting.persistence.isOpen)
        #expect(!meeting.activity.isAsserted)
    }
}
