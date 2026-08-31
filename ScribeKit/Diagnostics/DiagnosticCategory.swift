//
//  DiagnosticCategory.swift
//  ScribeKit
//

import Foundation

/// The stable name a support conversation can use for a failure.
///
/// ScribeKit's subsystems keep their own rich errors, and this does not replace
/// them: `AudioCaptureError`, `TranscriptionError`, `TranscriptPersistenceError`,
/// `AudioRetentionError` and `SessionRecoveryError` still say precisely what
/// went wrong to the code that has to react. What they do not have is a name
/// that survives a rewording, a localisation or a framework upgrade, and that
/// is what a report and a log line need: two people looking at the same
/// `captureInterrupted` are looking at the same thing, whatever sentence the
/// screen showed.
///
/// The cases are reachable states, not a taxonomy of everything that could
/// theoretically go wrong.
nonisolated enum DiagnosticCategory: String, Codable, CaseIterable, Equatable, Sendable {

    /// The system has not granted Screen & System Audio Recording.
    case captureAccess

    /// The list of capturable applications could not be read.
    case captureDiscovery

    /// A capture stream could not be started.
    case captureStart

    /// A running capture stream ended without being asked to.
    case captureInterrupted

    /// Speech recognition is unavailable: no model, an unsupported locale, or
    /// an unsupported system.
    case recognitionAvailability

    /// A recognition run could not be started.
    case recognitionStart

    /// The recogniser used up its automatic restarts and the meeting ended.
    case recognitionRestartExhausted

    /// The chosen save folder is missing, unreadable or was refused.
    case saveLocation

    /// The canonical transcript could not be written, flushed or closed.
    case transcriptPersistence

    /// A retained recording could not be created, written or finalised.
    case audioPersistence

    /// The session record could not be written or updated.
    case sessionMetadata

    /// A session record read back was missing, damaged or of a version this
    /// build does not know.
    case recoveryMetadata

    /// The category an error belongs to, when it is one diagnostics names.
    ///
    /// - Parameter error: An error from any ScribeKit subsystem.
    /// - Returns: The support-facing category, or `nil` for an error that is
    ///   not a failure worth naming in a report.
    init?(_ error: Error) {
        switch error {
        case let error as AudioCaptureError:
            switch error {
            case .permissionDenied: self = .captureAccess
            case .noSourcesSelected, .sourcesUnavailable, .noCaptureDisplay: self = .captureDiscovery
            case .alreadyCapturing, .systemFailure: self = .captureStart
            case .interrupted: self = .captureInterrupted
            }
        case let error as TranscriptionError:
            switch error {
            case .unavailable: self = .recognitionAvailability
            case .alreadyTranscribing, .incompatibleAudioFormat, .systemFailure: self = .recognitionStart
            }
        case let error as TranscriptPersistenceError:
            switch error.reason {
            case .accessDenied, .directoryCreationFailed: self = .saveLocation
            case .recoveryMetadataFailed: self = .sessionMetadata
            case .noSessionInProgress, .sessionAlreadyInProgress, .transcriptCreationFailed,
                 .segmentNotFinalized, .writeFailed, .flushFailed:
                self = .transcriptPersistence
            }
        case is AudioRetentionError:
            self = .audioPersistence
        case is SessionRecoveryError:
            self = .recoveryMetadata
        default:
            return nil
        }
    }

    /// The category an ending belongs to.
    ///
    /// The outcome presentation already decided which of six endings a meeting
    /// had, from the same states; naming it again from the subsystems would be
    /// a second opinion that could disagree with the one the user was shown.
    ///
    /// - Parameter outcome: How the meeting ended.
    /// - Returns: The support-facing category, or `nil` for a meeting that
    ///   finished normally.
    init?(outcome: MeetingOutcomePresentation.Category) {
        switch outcome {
        case .completed: return nil
        case .interrupted: self = .captureInterrupted
        case .transcriptFailure: self = .transcriptPersistence
        case .audioFailure: self = .audioPersistence
        case .recognitionFailure: self = .recognitionRestartExhausted
        case .startFailure: self = .captureStart
        }
    }
}
