//
//  TranscriptionStateTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("TranscriptionState")
struct TranscriptionStateTests {

    @Test("Only idle and failed accept a start")
    func startableStates() {
        #expect(TranscriptionState.idle.canStart)
        #expect(TranscriptionState.failed(message: "no model").canStart)
        #expect(!TranscriptionState.preparing.canStart)
        #expect(!TranscriptionState.transcribing.canStart)
        #expect(!TranscriptionState.recovering.canStart)
        #expect(!TranscriptionState.stopping.canStart)
    }

    @Test("A stop is meaningful only while recognition is under way")
    func stoppableStates() {
        #expect(TranscriptionState.preparing.canStop)
        #expect(TranscriptionState.transcribing.canStop)
        #expect(TranscriptionState.recovering.canStop)
        #expect(!TranscriptionState.idle.canStop)
        #expect(!TranscriptionState.stopping.canStop)
        #expect(!TranscriptionState.failed(message: "no model").canStop)
    }

    @Test("Only the resting states hold no resources")
    func activeStates() {
        #expect(TranscriptionState.preparing.isActive)
        #expect(TranscriptionState.transcribing.isActive)
        #expect(TranscriptionState.recovering.isActive)
        #expect(TranscriptionState.stopping.isActive)
        #expect(!TranscriptionState.idle.isActive)
        #expect(!TranscriptionState.failed(message: "no model").isActive)
    }

    @Test("A failure carries its reason and compares by it")
    func failureCarriesReason() {
        #expect(TranscriptionState.failed(message: "no model") == .failed(message: "no model"))
        #expect(TranscriptionState.failed(message: "no model") != .failed(message: "no audio"))
    }
}
