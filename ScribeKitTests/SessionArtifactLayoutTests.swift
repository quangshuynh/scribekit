//
//  SessionArtifactLayoutTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("SessionArtifactLayout")
struct SessionArtifactLayoutTests {

    private let destination = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    private var layout: SessionArtifactLayout {
        SessionArtifactLayout(destination: destination, directoryName: "2026-08-31-standup")
    }

    @Test("The session directory sits inside the chosen save location")
    func placesSessionInsideDestination() {
        #expect(layout.directory.path(percentEncoded: false) == "/Users/example/Meetings/2026-08-31-standup/")
    }

    @Test("The transcript is a Markdown file at the top of the session directory")
    func placesTranscriptAtTopLevel() {
        #expect(layout.transcriptURL.lastPathComponent == "transcript.md")
        #expect(layout.transcriptURL.deletingLastPathComponent().lastPathComponent == "2026-08-31-standup")
    }

    @Test("Metadata lives in a hidden subdirectory, apart from the transcript")
    func keepsMetadataApart() {
        #expect(layout.metadataDirectory.lastPathComponent == ".scribekit")
        #expect(layout.metadataURL.lastPathComponent == "session.json")
        #expect(layout.metadataURL.deletingLastPathComponent() == layout.metadataDirectory)
    }

    @Test("Audio has a place only when the retention mode keeps some", arguments: [
        (AudioRetentionMode.none, nil as String?),
        (AudioRetentionMode.raw, "audio.caf"),
        (AudioRetentionMode.compressed, "audio.m4a")
    ])
    func namesAudioPerRetentionMode(mode: AudioRetentionMode, expected: String?) {
        #expect(layout.audioURL(for: mode)?.lastPathComponent == expected)
    }

    @Test("Layouts for the same directory are equal")
    func comparesByDirectory() {
        let other = SessionArtifactLayout(directory: layout.directory)
        #expect(layout == other)
    }
}
