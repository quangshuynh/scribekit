//
//  AudioRetentionModeTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("AudioRetentionMode")
struct AudioRetentionModeTests {

    @Test("Retention defaults to keeping no audio")
    func defaultKeepsNoAudio() {
        #expect(AudioRetentionMode.default == .none)
        #expect(!AudioRetentionMode.default.retainsAudio)
    }

    @Test("Only raw and compressed retain audio")
    func retainingModes() {
        let retaining = AudioRetentionMode.allCases.filter(\.retainsAudio)
        #expect(Set(retaining) == [.raw, .compressed])
    }

    @Test("Round-trips through Codable", arguments: AudioRetentionMode.allCases)
    func codableRoundTrip(mode: AudioRetentionMode) throws {
        let data = try JSONEncoder().encode(mode)
        #expect(try JSONDecoder().decode(AudioRetentionMode.self, from: data) == mode)
    }

    @Test("Raw values are stable across releases")
    func stableRawValues() {
        #expect(AudioRetentionMode.none.rawValue == "none")
        #expect(AudioRetentionMode.raw.rawValue == "raw")
        #expect(AudioRetentionMode.compressed.rawValue == "compressed")
    }
}
