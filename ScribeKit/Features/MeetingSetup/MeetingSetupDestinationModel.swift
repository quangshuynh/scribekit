//
//  MeetingSetupDestinationModel.swift
//  ScribeKit
//

import Foundation

/// Owns the save-location part of the meeting setup screen: which folder is in
/// use, where it came from, and what to say when it cannot be used.
///
/// The model talks to a ``SaveLocationPersisting`` value and never touches
/// bookmark data itself, so the screen's behaviour is testable without the
/// sandbox, a real folder or an open panel.
@MainActor
@Observable
final class MeetingSetupDestinationModel {

    /// Where the current destination came from.
    enum Origin: Equatable, Sendable {
        /// Restored from a previous launch.
        case restored

        /// Chosen by the user in this launch.
        case chosen
    }

    /// A usable save location and its provenance.
    struct Destination: Equatable, Sendable {
        /// The folder meeting artifacts will be written to.
        let url: URL

        /// How ScribeKit came to have it.
        let origin: Origin
    }

    /// The save location's current condition.
    ///
    /// One value describes the whole situation, so "remembered but broken" and
    /// "usable but not remembered" cannot be confused with each other or with
    /// having no destination at all.
    enum State: Equatable {
        /// No folder has been chosen.
        case none

        /// A folder is available for use.
        case available(Destination)

        /// A folder was remembered but cannot be used; the message explains why.
        case unavailable(message: String)

        /// Storing the preference failed. `url` is the folder that still works
        /// for this launch, or `nil` when the failure was in forgetting one.
        case persistenceFailed(url: URL?, message: String)
    }

    /// The current state of the save location.
    private(set) var state: State = .none

    private let persistence: SaveLocationPersisting

    /// Creates the model.
    ///
    /// - Parameter persistence: Storage for the chosen folder.
    init(persistence: SaveLocationPersisting) {
        self.persistence = persistence
    }

    /// The folder usable right now, if any.
    var url: URL? {
        switch state {
        case let .available(destination): destination.url
        case let .persistenceFailed(url, _): url
        case .none, .unavailable: nil
        }
    }

    /// Whether a folder can be forgotten, which is only worth offering when
    /// something is remembered or in use.
    var canClear: Bool {
        switch state {
        case .none: false
        case .available, .unavailable, .persistenceFailed: true
        }
    }

    /// Text used when the interface has no destination to show.
    static let emptyDescription = "No folder selected"

    /// The folder path to display, or ``emptyDescription`` when there is none.
    var pathDescription: String {
        url?.path(percentEncoded: false) ?? Self.emptyDescription
    }

    /// What is wrong with the save location, when something is.
    ///
    /// The interface shows this as text, so an unusable destination is never
    /// signalled by styling alone.
    var warningMessage: String? {
        switch state {
        case .none, .available: nil
        case let .unavailable(message): message
        case let .persistenceFailed(_, message): message
        }
    }

    /// Whether the current folder came from a previous launch.
    var isRestored: Bool {
        if case let .available(destination) = state { destination.origin == .restored } else { false }
    }

    /// A full description of the save location, used as the accessibility
    /// value so assistive technology hears the same thing the screen shows.
    var statusDescription: String {
        guard let warningMessage else { return pathDescription }
        if case let .persistenceFailed(url?, _) = state {
            return "\(url.path(percentEncoded: false)) — \(warningMessage)"
        }
        return warningMessage
    }

    /// Restores the folder remembered by a previous launch.
    ///
    /// A missing folder, revoked access or unreadable stored data all end in
    /// ``State/unavailable(message:)``: ScribeKit says so rather than quietly
    /// substituting a folder the user never chose.
    func restore() {
        do {
            if let url = try persistence.restore() {
                state = .available(Destination(url: url, origin: .restored))
            } else {
                state = .none
            }
        } catch {
            state = .unavailable(message: message(for: error))
        }
    }

    /// Adopts a folder the user selected, replacing any previous one.
    ///
    /// - Parameter url: The selected folder, as returned by the system open
    ///   panel. When it cannot be remembered it is still used for this launch,
    ///   and the screen says it will need choosing again.
    func choose(_ url: URL) {
        do {
            try persistence.save(url)
            state = .available(Destination(url: url, origin: .chosen))
        } catch {
            state = .persistenceFailed(url: url, message: message(for: error))
        }
    }

    /// Forgets the current folder.
    func clear() {
        do {
            try persistence.clear()
            state = .none
        } catch {
            state = .persistenceFailed(url: nil, message: message(for: error))
        }
    }

    /// Converts a persistence error into a message for the screen.
    ///
    /// - Parameter error: The error thrown by persistence.
    /// - Returns: A user-facing description; raw OS codes are never the whole
    ///   explanation.
    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
