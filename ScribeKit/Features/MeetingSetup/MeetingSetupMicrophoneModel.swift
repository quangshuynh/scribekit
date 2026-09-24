//
//  MeetingSetupMicrophoneModel.swift
//  ScribeKit
//

import Foundation

/// Owns the microphone part of the meeting setup screen: whether macOS lets
/// ScribeKit use the microphone, which inputs the Mac offers, and which one
/// the next Microphone meeting would listen to.
///
/// Like the application list, this configures the *next* meeting and belongs
/// to the screen, so it goes away with the window. A running meeting keeps the
/// input it was started with whatever this model reads or is told afterwards.
///
/// The list of inputs follows the hardware while the screen is shown —
/// ``observeInputChanges()`` is driven by Core Audio's own notifications, so a
/// microphone plugged in appears without polling. Permission is still a
/// snapshot: a change made in System Settings is noticed at the next Check
/// Again.
///
/// Choosing an input here changes nothing outside ScribeKit. The Mac's own
/// default input stays as it was; the choice is remembered in ScribeKit's
/// preferences and applied to the next meeting's own audio unit.
@MainActor
@Observable
final class MeetingSetupMicrophoneModel {

    /// What macOS last reported, with the input a meeting would use.
    private(set) var readiness: MicrophoneReadiness = .notChecked

    /// The inputs the Mac offered when it was last read.
    private(set) var catalog: MicrophoneInputCatalog = .empty

    /// Which microphone the user asked for.
    ///
    /// Remembered as soon as it changes. A remembered device that is not
    /// connected stays selected — shown as not connected — so it is used again
    /// once it is back, rather than being forgotten because it was unplugged
    /// when the screen opened.
    private(set) var selection: MicrophoneSelection

    /// Whether the permission prompt is on screen because the user asked for
    /// it here.
    private(set) var isRequestingAccess = false

    private let access: any MicrophoneAccessProviding
    private let preferences: MeetingSetupPreferencesStoring?

    /// Creates a model.
    ///
    /// - Parameters:
    ///   - access: The system's answers about the microphone. The default
    ///     asks macOS; tests substitute their own.
    ///   - preferences: Where the chosen microphone is remembered, or `nil`
    ///     to remember nothing.
    init(
        access: any MicrophoneAccessProviding = SystemMicrophoneAccess(),
        preferences: MeetingSetupPreferencesStoring? = nil
    ) {
        self.access = access
        self.preferences = preferences
        selection = preferences?.microphoneSelection ?? .systemDefault
    }

    /// Whether ScribeKit may use the microphone, once it has been read.
    var authorization: MicrophoneAuthorization? {
        if case let .checked(authorization, _) = readiness { authorization } else { nil }
    }

    /// The selection resolved against the inputs the Mac offers, once they
    /// have been read.
    var choice: MicrophoneChoice? {
        if case let .checked(_, choice) = readiness { choice } else { nil }
    }

    /// The input a Microphone meeting started now would listen to.
    var input: MicrophoneInput? { choice?.input }

    /// The source a Microphone meeting started now would capture, or `nil`
    /// when there is no input to listen to.
    var source: CaptureSource? { input.map(CaptureSource.microphone) }

    /// Reads the permission and the inputs again. Asks nothing of the user.
    func refresh() {
        catalog = access.inputs()
        readiness = .checked(authorization: access.authorization(), choice: .resolve(selection, in: catalog))
    }

    /// Chooses the input the next meeting listens to, and remembers it.
    ///
    /// - Parameter selection: System Default, or one input.
    func select(_ selection: MicrophoneSelection) {
        guard selection != self.selection else { return }
        self.selection = selection
        preferences?.microphoneSelection = selection
        if case let .checked(authorization, _) = readiness {
            readiness = .checked(authorization: authorization, choice: .resolve(selection, in: catalog))
        }
    }

    /// Reads the inputs again each time the hardware changes, for as long as
    /// the caller keeps awaiting it.
    ///
    /// Meant for the screen's own task, so it ends when the screen goes away.
    func observeInputChanges() async {
        for await _ in access.inputChanges() {
            refresh()
        }
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
