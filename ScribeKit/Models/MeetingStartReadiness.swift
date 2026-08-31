//
//  MeetingStartReadiness.swift
//  ScribeKit
//

import Foundation

/// What ScribeKit knows about the folder meetings would be written to.
///
/// The save location is the one prerequisite that is a user decision rather
/// than a property of the Mac, so its states are the ones the setup screen has
/// to be able to explain: nothing chosen yet, a usable folder, a folder that is
/// usable for this launch but was not remembered, and a remembered folder that
/// cannot be used any more.
nonisolated enum SaveLocationReadiness: Equatable, Sendable {
    /// No folder has been chosen. ScribeKit writes nowhere until one is.
    case notChosen

    /// A folder is available and remembered.
    case ready(path: String)

    /// A folder is usable for this launch but could not be remembered; the
    /// message says what that costs.
    case readyNotRemembered(path: String, message: String)

    /// A folder was remembered but cannot be used; the message says why.
    case unusable(message: String)
}

/// What ScribeKit knows about listing the applications it could capture.
///
/// Discovery answers two different questions at once — whether ScribeKit can
/// see this Mac's applications at all, and which of them the user picked — so
/// the cases keep "we were refused", "we failed", "we saw nothing" and "we saw
/// a list" apart rather than presenting all four as an empty list.
nonisolated enum CaptureSourceReadiness: Equatable, Sendable {
    /// Discovery has not run yet.
    case notAttempted

    /// Discovery is running.
    case discovering

    /// ScribeKit could not see this Mac's applications because the access it
    /// needs is not available; the message says what to do about it.
    case accessUnavailable(message: String)

    /// Discovery failed for a reason that is not about access.
    case discoveryFailed(message: String)

    /// Discovery succeeded and nothing qualified.
    case noApplicationsFound

    /// Discovery succeeded.
    ///
    /// - Parameters:
    ///   - available: How many applications can be captured.
    ///   - selected: How many of them the user selected.
    ///   - droppedSelections: Names of previously selected applications this
    ///     discovery no longer found.
    case discovered(available: Int, selected: Int, droppedSelections: [String])
}

/// Whether Start Meeting can currently succeed, and what to say when it
/// cannot.
///
/// This is the single answer to that question. The setup screen, the Start
/// control and its explanation all read this one value, so the button being
/// disabled and the reason shown beside it cannot disagree, and a new
/// prerequisite is added in one place rather than in each view that happens to
/// check something.
///
/// It is a derivation, not stored state: nothing sets it, it is computed from
/// the save location, discovery, speech availability and whether a meeting is
/// already running. A prerequisite that becomes healthy therefore stops being
/// reported the moment the state it was derived from changes, which is what
/// keeps a corrected failure from lingering on the screen.
nonisolated struct MeetingStartReadiness: Equatable, Sendable {

    /// A thing a meeting needs before it can start.
    ///
    /// The order of the cases is the order the screen reports them in and the
    /// order a blocking reason is chosen in. It follows the dependencies of
    /// the start path rather than the order the runtime happens to check
    /// things: without a folder there is nothing to write, without capture
    /// access there is no list to select a source from, and speech readiness is
    /// a property of the Mac that the user's selection cannot change.
    enum Prerequisite: Equatable, Sendable, CaseIterable {
        /// The folder the user chose for meeting artifacts.
        case saveLocation

        /// Being able to see, and record, this Mac's applications.
        case captureAccess

        /// On-device recognition for the selected language.
        case speechRecognition

        /// At least one application selected to capture.
        case captureSource

        /// The name shown for this prerequisite.
        var title: String {
            switch self {
            case .saveLocation: "Save location"
            case .captureAccess: "Screen & System Audio Recording"
            case .speechRecognition: "Speech recognition"
            case .captureSource: "Audio source"
            }
        }
    }

    /// How a prerequisite stands.
    enum Status: Equatable, Sendable {
        /// Satisfied; nothing is needed.
        case satisfied

        /// Not determined yet. It does not describe a problem, but a meeting
        /// is not started on an unanswered question either.
        case checking

        /// Usable, with something worth saying. Never prevents a start.
        case advisory

        /// Not satisfied; a meeting cannot start.
        case blocked

        /// Whether this status stops a meeting from starting.
        var preventsStart: Bool {
            switch self {
            case .satisfied, .advisory: false
            case .checking, .blocked: true
            }
        }

        /// A word naming the status, so nothing is signalled by colour alone.
        var label: String {
            switch self {
            case .satisfied: "Ready"
            case .checking: "Checking"
            case .advisory: "Note"
            case .blocked: "Action needed"
            }
        }

        /// An SF Symbol for the status, always shown beside ``label``.
        var symbolName: String {
            switch self {
            case .satisfied: "checkmark.circle"
            case .checking: "clock"
            case .advisory: "info.circle"
            case .blocked: "exclamationmark.triangle"
            }
        }
    }

    /// One prerequisite's current state, and what to say about it.
    struct Row: Equatable, Sendable, Identifiable {
        /// The prerequisite this row is about.
        let prerequisite: Prerequisite

        /// How it stands.
        let status: Status

        /// What that means, and what to do when something is needed.
        let detail: String

        var id: Prerequisite { prerequisite }

        /// What assistive technology hears, which is the same claim the screen
        /// makes rather than the icon alone.
        var accessibilityDescription: String {
            "\(prerequisite.title). \(accessibilityValue)"
        }

        /// The row's state, for a screen that has already named the
        /// prerequisite.
        ///
        /// The status word and the detail travel together: the icon carries no
        /// meaning of its own, and a detail read without the status it belongs
        /// to says what is wrong without saying that anything is.
        var accessibilityValue: String {
            "\(status.label). \(detail)"
        }
    }

    /// Every prerequisite, in dependency order.
    let rows: [Row]

    /// The one reason a meeting cannot start, or `nil` when one can.
    ///
    /// A screen may show several rows needing attention; the Start control
    /// gets one reason, chosen by ``Prerequisite`` order, so the user is given
    /// the first thing to fix rather than a list to triage.
    let blocker: Row?

    /// Whether a meeting is already running, which is a reason not to offer a
    /// start that is not about prerequisites at all.
    let meetingIsActive: Bool

    /// Whether Start Meeting can currently succeed.
    var canStart: Bool { blocker == nil && !meetingIsActive }

    /// What to say about the Start control, whether or not it is available.
    var startExplanation: String {
        if meetingIsActive { return "A meeting is already running." }
        guard let blocker else {
            return "Capture the selected applications and write a timestamped Markdown transcript."
        }
        return "\(blocker.prerequisite.title): \(blocker.detail)"
    }

    /// Derives readiness from what ScribeKit currently knows.
    ///
    /// - Parameters:
    ///   - saveLocation: The state of the folder meetings are written to.
    ///   - captureSources: What discovery last reported, and what is selected.
    ///   - speech: What the on-device recogniser reports for the chosen
    ///     language.
    ///   - meetingIsActive: Whether a meeting is running, starting or stopping.
    init(
        saveLocation: SaveLocationReadiness,
        captureSources: CaptureSourceReadiness,
        speech: SpeechRecognitionAvailability,
        meetingIsActive: Bool
    ) {
        let rows = [
            Self.saveLocationRow(saveLocation),
            Self.captureAccessRow(captureSources),
            Self.speechRow(speech),
            Self.captureSourceRow(captureSources)
        ]
        self.rows = rows
        self.blocker = rows.first { $0.status.preventsStart }
        self.meetingIsActive = meetingIsActive
    }

    /// Describes the save location.
    private static func saveLocationRow(_ readiness: SaveLocationReadiness) -> Row {
        switch readiness {
        case .notChosen:
            Row(
                prerequisite: .saveLocation,
                status: .blocked,
                detail: "No folder chosen. ScribeKit writes each meeting to a folder you pick and saves "
                    + "nowhere else, so choose one before starting."
            )
        case let .ready(path):
            Row(prerequisite: .saveLocation, status: .satisfied, detail: path)
        case let .readyNotRemembered(path, message):
            Row(prerequisite: .saveLocation, status: .advisory, detail: "\(path) — \(message)")
        case let .unusable(message):
            Row(prerequisite: .saveLocation, status: .blocked, detail: message)
        }
    }

    /// Describes whether ScribeKit can see this Mac's applications.
    ///
    /// Finding no applications is not an access problem: ScribeKit was able to
    /// look. That is reported on the source row instead, so the user is not
    /// sent to System Settings to fix a Mac with nothing running on it.
    private static func captureAccessRow(_ readiness: CaptureSourceReadiness) -> Row {
        switch readiness {
        case .notAttempted, .discovering:
            Row(
                prerequisite: .captureAccess,
                status: .checking,
                detail: "Looking for applications ScribeKit can record. macOS asks for this permission the "
                    + "first time ScribeKit looks."
            )
        case let .accessUnavailable(message):
            Row(prerequisite: .captureAccess, status: .blocked, detail: message)
        case let .discoveryFailed(message):
            Row(prerequisite: .captureAccess, status: .blocked, detail: message)
        case .noApplicationsFound, .discovered:
            Row(
                prerequisite: .captureAccess,
                status: .satisfied,
                detail: "ScribeKit can list and record this Mac's running applications."
            )
        }
    }

    /// Describes on-device recognition for the selected language.
    ///
    /// ``SpeechRecognitionAvailability`` already words each refusal, so this
    /// says what a refusal means for starting rather than restating it.
    private static func speechRow(_ availability: SpeechRecognitionAvailability) -> Row {
        switch availability {
        case .unknown:
            Row(
                prerequisite: .speechRecognition,
                status: .checking,
                detail: "Checking which languages this Mac has installed."
            )
        case let .available(identifier):
            Row(
                prerequisite: .speechRecognition,
                status: .satisfied,
                detail: "On-device recognition is ready in \(identifier). Nothing is sent to a server."
            )
        case .unsupportedLocale, .modelNotInstalled, .unsupportedSystem, .failed:
            Row(
                prerequisite: .speechRecognition,
                status: .blocked,
                detail: availability.message ?? "On-device speech recognition is unavailable."
            )
        }
    }

    /// Describes the application selection.
    private static func captureSourceRow(_ readiness: CaptureSourceReadiness) -> Row {
        switch readiness {
        case .notAttempted, .discovering:
            Row(prerequisite: .captureSource, status: .checking, detail: "Waiting for the application list.")
        case .accessUnavailable, .discoveryFailed:
            Row(
                prerequisite: .captureSource,
                status: .blocked,
                detail: "No application can be selected until ScribeKit can list them."
            )
        case .noApplicationsFound:
            Row(
                prerequisite: .captureSource,
                status: .blocked,
                detail: "No application on this Mac can be captured right now. Open the one you want to "
                    + "record, then Refresh."
            )
        case let .discovered(available, selected, dropped):
            if selected > 0 {
                Row(
                    prerequisite: .captureSource,
                    status: dropped.isEmpty ? .satisfied : .advisory,
                    detail: dropped.isEmpty
                        ? "\(selected) of \(available) applications selected."
                        : "\(selected) of \(available) applications selected. "
                          + "No longer running, so removed from your selection: "
                          + dropped.formatted(.list(type: .and))
                )
            } else if dropped.isEmpty {
                Row(
                    prerequisite: .captureSource,
                    status: .blocked,
                    detail: "No application selected. Choose at least one from the list to record its audio."
                )
            } else {
                Row(
                    prerequisite: .captureSource,
                    status: .blocked,
                    detail: "No longer running, so removed from your selection: "
                        + dropped.formatted(.list(type: .and))
                        + ". Select an application that is running now."
                )
            }
        }
    }
}
