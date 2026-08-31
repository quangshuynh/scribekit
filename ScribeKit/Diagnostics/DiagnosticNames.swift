//
//  DiagnosticNames.swift
//  ScribeKit
//

import Foundation

/// Stable names for states that a report and a log line can both use.
///
/// A state's own description is written for a person looking at the screen, and
/// several of these carry a message that quotes a folder, an application or a
/// framework. What diagnostics needs is the case, not the sentence: a name that
/// does not change when the wording does, and that carries nothing the wording
/// might have picked up.
///
/// `String(describing:)` would give a name too, and it is deliberately not used
/// anywhere in diagnostics: it prints associated values, and it makes Swift's
/// spelling of a case into an accidental published format.

nonisolated extension MeetingRuntimeStatus {
    /// The lifecycle answer as one stable word.
    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .transcribing: "transcribing"
        case .paused: "paused"
        case .stopping: "stopping"
        case .completed: "completed"
        case .failed: "failed"
        }
    }
}

nonisolated extension AudioCaptureState {
    /// The capture subsystem's state as one stable word.
    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .capturing: "capturing"
        case .paused: "paused"
        case .stopping: "stopping"
        case .failed: "failed"
        }
    }
}

nonisolated extension TranscriptionState {
    /// The recogniser's state as one stable word.
    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .transcribing: "transcribing"
        case .recovering: "recovering"
        case .stopping: "stopping"
        case .failed: "failed"
        }
    }
}

nonisolated extension TranscriptPersistenceState {
    /// The canonical transcript's state as one stable word, without the layout
    /// it names.
    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .saving: "saving"
        case .saved: "saved"
        case .failed: "failed"
        }
    }
}

nonisolated extension AudioRetentionState {
    /// Retained audio's state as one stable word, without the file it names.
    var diagnosticName: String {
        switch self {
        case .idle: "idle"
        case .preparing: "preparing"
        case .retaining: "retaining"
        case .retained: "retained"
        case .failed: "failed"
        }
    }
}

nonisolated extension AudioRetentionMode {
    /// How much audio a meeting keeps, as one stable word.
    var diagnosticName: String {
        switch self {
        case .none: "none"
        case .raw: "raw"
        case .compressed: "compressed"
        }
    }
}

nonisolated extension SpeechRecognitionAvailability {
    /// Whether an on-device model can transcribe, as one stable word.
    ///
    /// The locale identifier several cases carry is reported once, beside the
    /// configured locale, rather than repeated here.
    var diagnosticName: String {
        switch self {
        case .unknown: "unknown"
        case .available: "available"
        case .unsupportedLocale: "unsupportedLocale"
        case .modelNotInstalled: "modelNotInstalled"
        case .unsupportedSystem: "unsupportedSystem"
        case .failed: "failed"
        }
    }
}

nonisolated extension SessionCompletionOutcome {
    /// What a session record was closed as.
    var diagnosticName: String {
        switch self {
        case .completed: "completed"
        case .failed: "failed"
        case .interrupted: "interrupted"
        }
    }
}

nonisolated extension MeetingOutcomePresentation.Category {
    /// The ending the user was shown, as one stable word.
    var diagnosticName: String {
        switch self {
        case .completed: "completed"
        case .interrupted: "interrupted"
        case .transcriptFailure: "transcriptFailure"
        case .audioFailure: "audioFailure"
        case .recognitionFailure: "recognitionFailure"
        case .startFailure: "startFailure"
        }
    }
}

nonisolated extension MeetingStartReadiness.Prerequisite {
    /// Which prerequisite, as one stable word.
    var diagnosticName: String {
        switch self {
        case .saveLocation: "saveLocation"
        case .captureAccess: "captureAccess"
        case .speechRecognition: "speechRecognition"
        case .captureSource: "captureSource"
        }
    }
}

nonisolated extension MeetingStartReadiness.Status {
    /// A prerequisite's standing, as one stable word.
    var diagnosticName: String {
        switch self {
        case .satisfied: "satisfied"
        case .checking: "checking"
        case .advisory: "advisory"
        case .blocked: "blocked"
        }
    }
}

nonisolated extension SessionRecoveryError {
    /// Why a session folder could not be described, as one stable word. The
    /// schema version an unsupported record announced is deliberately dropped:
    /// the build's own supported version is reported separately.
    var diagnosticName: String {
        switch self {
        case .destinationUnavailable: "destinationUnavailable"
        case .sessionDirectoryMissing: "sessionDirectoryMissing"
        case .metadataMissing: "metadataMissing"
        case .metadataUnreadable: "metadataUnreadable"
        case .metadataMalformed: "metadataMalformed"
        case .unsupportedSchemaVersion: "unsupportedSchemaVersion"
        case .transcriptMissing: "transcriptMissing"
        case .transcriptUnreadable: "transcriptUnreadable"
        case .metadataWriteFailed: "metadataWriteFailed"
        case .transcriptAnnotationFailed: "transcriptAnnotationFailed"
        }
    }
}
