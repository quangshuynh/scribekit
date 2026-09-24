//
//  FakeMicrophoneAccess.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
@testable import ScribeKit

/// Stated answers about the microphone, so permission and input handling are
/// testable without a microphone, a permission dialog or the user's own
/// privacy settings.
///
/// Asking for access behaves the way macOS does: an undetermined permission
/// becomes whatever the test says the user answers, and a permission already
/// decided is returned unchanged without anything being shown.
nonisolated final class FakeMicrophoneAccess: MicrophoneAccessProviding, @unchecked Sendable {

    private struct State {
        var authorization: MicrophoneAuthorization
        var answer: Bool
        var input: MicrophoneInput?
        var authorizationReads = 0
        var inputReads = 0
        var requests = 0
    }

    private let state: Mutex<State>

    /// Creates stated answers.
    ///
    /// - Parameters:
    ///   - authorization: What macOS reports now.
    ///   - answer: What the user answers if they are asked.
    ///   - input: The Mac's current sound input.
    init(
        authorization: MicrophoneAuthorization,
        answer: Bool = true,
        input: MicrophoneInput? = MicrophoneInput(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
    ) {
        state = Mutex(State(authorization: authorization, answer: answer, input: input))
    }

    /// How many times authorization was read.
    var authorizationReads: Int { state.withLock { $0.authorizationReads } }

    /// How many times the current input was read.
    var inputReads: Int { state.withLock { $0.inputReads } }

    /// How many times macOS was asked, which is how many prompts a user
    /// could have seen.
    var requests: Int { state.withLock { $0.requests } }

    /// Whether anything about the microphone was asked at all.
    var wasConsulted: Bool { authorizationReads + inputReads + requests > 0 }

    /// Changes what macOS reports, as System Settings would.
    func setAuthorization(_ authorization: MicrophoneAuthorization) {
        state.withLock { $0.authorization = authorization }
    }

    /// Changes the Mac's current input, as plugging a device in would.
    func setInput(_ input: MicrophoneInput?) {
        state.withLock { $0.input = input }
    }

    func authorization() -> MicrophoneAuthorization {
        state.withLock { state in
            state.authorizationReads += 1
            return state.authorization
        }
    }

    func requestAccess() async -> Bool {
        state.withLock { state in
            state.requests += 1
            if state.authorization == .notDetermined {
                state.authorization = state.answer ? .authorized : .denied
            }
            return state.authorization == .authorized
        }
    }

    func currentInput() -> MicrophoneInput? {
        state.withLock { state in
            state.inputReads += 1
            return state.input
        }
    }
}
