//
//  AudioCaptureStateTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("AudioCaptureState")
struct AudioCaptureStateTests {

    @Test("Only idle and failed states accept a start")
    func startableStates() {
        #expect(AudioCaptureState.idle.canStart)
        #expect(AudioCaptureState.failed(message: "no permission").canStart)
        #expect(!AudioCaptureState.preparing.canStart)
        #expect(!AudioCaptureState.capturing.canStart)
        #expect(!AudioCaptureState.stopping.canStart)
    }

    @Test("Preparing and capturing states accept a stop")
    func stoppableStates() {
        #expect(AudioCaptureState.preparing.canStop)
        #expect(AudioCaptureState.capturing.canStop)
        #expect(!AudioCaptureState.idle.canStop)
        #expect(!AudioCaptureState.stopping.canStop)
        #expect(!AudioCaptureState.failed(message: "stream error").canStop)
    }

    @Test("States that hold capture resources report themselves as active")
    func activeStates() {
        #expect(AudioCaptureState.preparing.isActive)
        #expect(AudioCaptureState.capturing.isActive)
        #expect(AudioCaptureState.stopping.isActive)
        #expect(!AudioCaptureState.idle.isActive)
        #expect(!AudioCaptureState.failed(message: "stream error").isActive)
    }

    @Test("Failures with different reasons are distinct states")
    func failureEquality() {
        #expect(AudioCaptureState.failed(message: "a") != AudioCaptureState.failed(message: "b"))
        #expect(AudioCaptureState.failed(message: "a") == AudioCaptureState.failed(message: "a"))
    }
}
