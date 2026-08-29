//
//  SessionRecoveryModel.swift
//  ScribeKit
//

import Foundation

/// Owns the recovery part of the meeting setup screen: whether the save folder
/// has been checked for unfinished meetings, what was found, and what the user
/// did about it.
///
/// The model holds state and delegates every decision about the filesystem to
/// ``SessionRecoveryService``, so the screen displays recovery rather than
/// implementing it. It starts nothing: no capture, no recognition, no timer
/// and no repeat scan. Checking a folder is something that happens once, when
/// the folder becomes available.
@MainActor
@Observable
final class SessionRecoveryModel {

    /// What the screen has to say about unfinished meetings.
    ///
    /// One value describes the whole situation, so "not checked yet" cannot be
    /// confused with "checked and found nothing", and a folder that could not
    /// be opened is never silently the same as a folder with nothing in it.
    enum State: Equatable {
        /// No folder has been checked.
        case unchecked

        /// A folder is being checked.
        case checking

        /// A folder was checked and held nothing unfinished.
        case clear

        /// A folder was checked and held something worth showing.
        case found(SessionRecoveryReport)

        /// The folder could not be opened, so nothing is known about it.
        case unavailable(message: String)
    }

    /// What the screen shows.
    private(set) var state: State = .unchecked

    /// What happened to the last session the user acted on, if anything.
    private(set) var actionMessage: String?

    private let service: SessionRecoveryService
    private var dismissed: Set<UUID> = []

    /// Creates the model.
    ///
    /// - Parameter service: Performs discovery and records interruptions. The
    ///   default reaches the real filesystem; tests substitute one built on a
    ///   store double.
    init(service: SessionRecoveryService = SessionRecoveryService()) {
        self.service = service
    }

    /// Unfinished sessions the user has not dismissed in this launch.
    var candidates: [SessionRecoveryCandidate] {
        guard case let .found(report) = state else { return [] }
        return report.candidates.filter { !dismissed.contains($0.id) }
    }

    /// Session directories whose records could not be interpreted.
    var problems: [SessionRecoveryProblem] {
        guard case let .found(report) = state else { return [] }
        return report.problems
    }

    /// Whether the screen has anything to show about recovery.
    var hasFindings: Bool { !candidates.isEmpty || !problems.isEmpty }

    /// Whether recovery has something to say at all, including a folder it
    /// could not open.
    var isVisible: Bool {
        switch state {
        case .unchecked, .clear: actionMessage != nil
        case .checking, .unavailable: true
        case .found: hasFindings || actionMessage != nil
        }
    }

    /// Checks one save folder for meetings that never finished.
    ///
    /// Only file reads happen here. Nothing is captured, no recogniser is
    /// created and no permission prompt can be raised by it.
    ///
    /// - Parameter destination: The folder the user chose, restored from its
    ///   bookmark or selected in this launch.
    func check(_ destination: URL) async {
        state = .checking
        actionMessage = nil
        do {
            let report = try await service.scan(destination)
            state = report.isEmpty ? .clear : .found(report)
        } catch {
            state = .unavailable(message: Self.message(for: error))
        }
    }

    /// Reports that the save folder could not be restored, so nothing could be
    /// checked.
    ///
    /// Called instead of ``check(_:)`` when there is no usable destination to
    /// check. ScribeKit says it does not know rather than looking somewhere
    /// the user did not choose.
    ///
    /// - Parameter message: Why the folder is unavailable.
    func reportDestinationUnavailable(_ message: String) {
        state = .unavailable(message: message)
        actionMessage = nil
    }

    /// Records an interruption for one unfinished session.
    ///
    /// This does not resume anything. It confirms the session is still there,
    /// marks its record as interrupted so it is not reported again, and adds a
    /// note to the transcript saying ScribeKit stopped before the meeting
    /// finished. Recognised speech is not touched.
    ///
    /// - Parameter candidate: The session to record.
    func recordInterruption(for candidate: SessionRecoveryCandidate) async {
        do {
            _ = try await service.recordInterruption(for: candidate)
            dismissed.insert(candidate.id)
            actionMessage = "\(candidate.metadata.title): marked as interrupted, and a note was added to the transcript."
        } catch {
            actionMessage = Self.message(for: error)
        }
    }

    /// Hides one finding for this launch without changing anything on disk.
    ///
    /// Dismissing is deliberately not a decision that is written down. Nothing
    /// is deleted, no record is altered, and the session is offered again next
    /// launch, because a user who closed a panel has not told ScribeKit that
    /// the meeting is dealt with.
    ///
    /// - Parameter candidate: The finding to hide.
    func dismiss(_ candidate: SessionRecoveryCandidate) {
        dismissed.insert(candidate.id)
        actionMessage = nil
    }

    /// Converts a recovery error into a message for the screen.
    ///
    /// - Parameter error: The error the service reported.
    /// - Returns: A user-facing description.
    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
