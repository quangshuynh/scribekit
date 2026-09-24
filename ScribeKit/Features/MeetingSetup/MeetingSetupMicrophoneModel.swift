//
//  MeetingSetupMicrophoneModel.swift
//  ScribeKit
//

import Foundation

/// Owns the microphone part of the meeting setup screen: whether macOS lets
/// ScribeKit use the microphone, and which input a Microphone meeting would
/// listen to.
///
/// Like the application list, this configures the *next* meeting and belongs
/// to the screen, so it goes away with the window. A running meeting keeps the
/// input it was started with whatever this model reads afterwards.
///
/// Reading is a snapshot rather than a subscription, the same rule the rest of
/// the setup screen follows: nothing polls, and an input plugged in or a
/// permission changed in System Settings is noticed at the next Check Again.
@MainActor
@Observable
final class MeetingSetupMicrophoneModel {

    /// What macOS last reported.
    private(set) var readiness: MicrophoneReadiness = .notChecked

    /// Whether the permission prompt is on screen because the user asked for
    /// it here.
    private(set) var isRequestingAccess = false

    private let access: any MicrophoneAccessProviding

    /// Creates a model.
    ///
    /// - Parameter access: The system's answers about the microphone. The
    ///   default asks macOS; tests substitute their own.
    init(access: any MicrophoneAccessProviding = SystemMicrophoneAccess()) {
        self.access = access
    }

    /// Whether ScribeKit may use the microphone, once it has been read.
    var authorization: MicrophoneAuthorization? {
        if case let .checked(authorization, _) = readiness { authorization } else { nil }
    }

    /// The Mac's current sound input, once it has been read.
    var input: MicrophoneInput? {
        if case let .checked(_, input) = readiness { input } else { nil }
    }

    /// The source a Microphone meeting started now would capture, or `nil`
    /// when there is no input to listen to.
    var source: CaptureSource? { input.map(CaptureSource.microphone) }

    /// Reads the permission and the current input again. Asks nothing of the
    /// user.
    func refresh() {
        readiness = .checked(authorization: access.authorization(), input: access.currentInput())
    }

    /// Asks macOS for microphone access, for a user who has not been asked
    /// yet and chose to answer before starting.
    ///
    /// A permission macOS has already answered is not asked about again,
    /// because macOS would not show a prompt: the answer can only be changed
    /// in System Settings, and the screen says so.
    func requestAccess() async {
        refresh()
        guard authorization == .notDetermined, !isRequestingAccess else { return }
        isRequestingAccess = true
        _ = await access.requestAccess()
        isRequestingAccess = false
        refresh()
    }
}
