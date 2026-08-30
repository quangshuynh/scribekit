//
//  MeetingMenuBarPresentationTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("MeetingMenuBarPresentation")
struct MeetingMenuBarPresentationTests {

    private let destination = URL(filePath: "/tmp/scribekit-tests", directoryHint: .isDirectory)
    private let transcriptURL = URL(filePath: "/tmp/scribekit-tests/session/transcript.md")
    private let audioURL = URL(filePath: "/tmp/scribekit-tests/session/audio.m4a")

    /// A started meeting to present.
    ///
    /// - Parameter retention: What the meeting keeps of its audio.
    /// - Returns: The snapshot.
    private func snapshot(retention: AudioRetentionMode = .compressed) -> MeetingSnapshot {
        MeetingSnapshot(
            session: MeetingSession(
                title: "Weekly Sync",
                audioRetention: retention,
                selectedSources: [
                    .application(bundleIdentifier: "com.example.Meet", displayName: "Meet"),
                    .application(bundleIdentifier: "com.example.Browser", displayName: "Browser")
                ],
                destination: destination
            ),
            localeIdentifier: "en-US"
        )
    }

    /// The presentation for one status, with the artifacts a meeting in that
    /// status would have.
    private func presentation(
        _ status: MeetingRuntimeStatus,
        meeting: MeetingSnapshot? = nil,
        transcript: URL? = nil,
        audio: URL? = nil,
        canStop: Bool = false
    ) -> MeetingMenuBarPresentation {
        MeetingMenuBarPresentation(
            status: status,
            meeting: meeting,
            transcript: transcript,
            audio: audio,
            canStop: canStop
        )
    }

    @Test("An idle menu names no meeting and offers no stop")
    func idle() {
        let idle = presentation(.idle)
        #expect(idle.title == nil)
        #expect(idle.statusLine == "No meeting running")
        #expect(idle.details.isEmpty)
        #expect(!idle.showsElapsed)
        #expect(!idle.canStop)
        #expect(idle.failureMessage == nil)
        #expect(idle.accessibilityLabel == "ScribeKit. No meeting running")
    }

    @Test("A starting meeting is named before it is transcribing")
    func preparing() {
        let preparing = presentation(.preparing, meeting: snapshot(), canStop: true)
        #expect(preparing.title == "Weekly Sync")
        #expect(preparing.statusLine == "Starting…")
        #expect(preparing.showsElapsed)
        #expect(preparing.canStop)
    }

    @Test("An active meeting states what it captures and what it keeps")
    func transcribing() {
        let active = presentation(
            .transcribing,
            meeting: snapshot(),
            transcript: transcriptURL,
            audio: audioURL,
            canStop: true
        )
        #expect(active.title == "Weekly Sync")
        #expect(active.statusLine == "Transcribing")
        #expect(active.details == ["Capturing Meet and Browser", "Keeping compressed audio"])
        #expect(active.showsElapsed)
        #expect(active.transcriptURL == transcriptURL)
        #expect(active.audioURL == audioURL)
        #expect(active.accessibilityLabel == "ScribeKit. Transcribing. Weekly Sync")
    }

    @Test("A meeting keeping no audio says so rather than staying silent about it")
    func retentionModes() {
        #expect(
            presentation(.transcribing, meeting: snapshot(retention: .none)).details.last
                == "Keeping the transcript only"
        )
        #expect(
            presentation(.transcribing, meeting: snapshot(retention: .raw)).details.last
                == "Keeping raw audio"
        )
    }

    @Test("A stopping meeting still shows its elapsed time")
    func stopping() {
        let stopping = presentation(.stopping, meeting: snapshot())
        #expect(stopping.statusLine == "Stopping…")
        #expect(stopping.showsElapsed)
    }

    @Test("A finished meeting keeps its name and its files, and stops being timed")
    func completed() {
        let done = presentation(.completed, meeting: snapshot(), transcript: transcriptURL, audio: audioURL)
        #expect(done.statusLine == "Meeting finished")
        #expect(done.title == "Weekly Sync")
        #expect(!done.showsElapsed)
        #expect(!done.canStop)
        #expect(done.details.isEmpty)
        #expect(done.transcriptURL == transcriptURL)
    }

    @Test("A failed meeting carries the reason into the menu")
    func failed() {
        let failed = presentation(
            .failed(message: "Not being saved."),
            meeting: snapshot(),
            transcript: transcriptURL
        )
        #expect(failed.statusLine == "Meeting failed")
        #expect(failed.failureMessage == "Not being saved.")
        #expect(failed.symbolName == "exclamationmark.triangle.fill")
        #expect(!failed.showsElapsed)
    }

    @Test("Every state has its own menu bar symbol")
    func symbolsAreDistinct() {
        let symbols = [
            presentation(.idle).symbolName,
            presentation(.transcribing, meeting: snapshot()).symbolName,
            presentation(.completed, meeting: snapshot()).symbolName,
            presentation(.failed(message: "x")).symbolName
        ]
        #expect(Set(symbols).count == symbols.count)
    }
}
