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
        var catalog: MicrophoneInputCatalog
        var authorizationReads = 0
        var inputReads = 0
        var requests = 0
        var changeContinuations: [AsyncStream<Void>.Continuation] = []
    }

    private let state: Mutex<State>

    /// Creates stated answers for a Mac with one input, which is its default.
    ///
    /// - Parameters:
    ///   - authorization: What macOS reports now.
    ///   - answer: What the user answers if they are asked.
    ///   - input: The Mac's only sound input, or `nil` for none.
    convenience init(
        authorization: MicrophoneAuthorization,
        answer: Bool = true,
        input: MicrophoneInput? = FakeMicrophoneAccess.builtIn
    ) {
        self.init(authorization: authorization, answer: answer, devices: input.map { [$0] } ?? [], defaultInput: input)
    }

    /// Creates stated answers for a Mac with several inputs.
    ///
    /// - Parameters:
    ///   - authorization: What macOS reports now.
    ///   - answer: What the user answers if they are asked.
    ///   - devices: The Mac's sound inputs.
    ///   - defaultInput: Which of them is the default.
    init(
        authorization: MicrophoneAuthorization,
        answer: Bool = true,
        devices: [MicrophoneInput],
        defaultInput: MicrophoneInput?
    ) {
        state = Mutex(State(
            authorization: authorization,
            answer: answer,
            catalog: MicrophoneInputCatalog(devices: devices, defaultInputID: defaultInput?.id)
        ))
    }

    /// The built-in microphone most tests use.
    static let builtIn = MicrophoneInput(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")

    /// How many times authorization was read.
    var authorizationReads: Int { state.withLock { $0.authorizationReads } }

    /// How many times the inputs were read.
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

    /// Makes one input the Mac's only one, as unplugging every other device
    /// and choosing it in System Settings would.
    func setInput(_ input: MicrophoneInput?) {
        setInputs(input.map { [$0] } ?? [], defaultInput: input)
    }

    /// Changes the Mac's inputs, as connecting or disconnecting devices would.
    /// Nothing is announced until ``announceInputChange()``.
    func setInputs(_ devices: [MicrophoneInput], defaultInput: MicrophoneInput?) {
        state.withLock { $0.catalog = MicrophoneInputCatalog(devices: devices, defaultInputID: defaultInput?.id) }
    }

    /// How many observations of input changes have begun.
    var inputObserverCount: Int { state.withLock { $0.changeContinuations.count } }

    /// Tells every observer the inputs changed, as Core Audio would.
    func announceInputChange() {
        for continuation in state.withLock({ $0.changeContinuations }) { continuation.yield() }
    }

    /// Ends every observation, as a screen going away would.
    func finishInputChanges() {
        for continuation in state.withLock({ $0.changeContinuations }) { continuation.finish() }
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

    func inputs() -> MicrophoneInputCatalog {
        state.withLock { state in
            state.inputReads += 1
            return state.catalog
        }
    }

    func inputChanges() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        state.withLock { $0.changeContinuations.append(continuation) }
        return stream
    }
}
