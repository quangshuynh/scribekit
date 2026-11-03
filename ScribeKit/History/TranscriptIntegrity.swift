//
//  TranscriptIntegrity.swift
//  ScribeKit
//

import Foundation

/// Whether a transcript is still the file ScribeKit closed.
///
/// The answer is a comparison between two pieces of local evidence and nothing
/// else: the ``TranscriptSeal`` the session record carries, and the bytes in
/// the file now. It is deterministic — the same file and the same record
/// always give the same answer — and it never changes either of them. A
/// transcript that differs is reported as changed and is still listed,
/// previewed, searched, opened and exported; ScribeKit does not repair,
/// rewrite or replace it, and does not update the seal to agree with it.
///
/// Absent evidence is not bad evidence. A transcript with no seal — written
/// before seals existed, still being written, or closed by a ScribeKit that
/// stopped first — is ``unverified(_:)``, never ``changed(expectedByteCount:observedByteCount:)``.
nonisolated enum TranscriptIntegrity: Equatable, Sendable {

    /// Why there is nothing to check a transcript against.
    nonisolated enum UnverifiedReason: Equatable, Sendable {
        /// The session has no record at all, as transcripts written before
        /// session records existed do not.
        case noRecord

        /// The session has a record, and the record carries no seal: it was
        /// closed by a version of ScribeKit that did not keep one, or its
        /// transcript could not be read back when it closed.
        case notRecorded

        /// The record still says the transcript is open: it is being written
        /// now, or its meeting never finished.
        case stillOpen

        /// ScribeKit stopped before the meeting closed, and recovery recorded
        /// the interruption afterwards. Nothing was there to seal the file.
        case interruptedBeforeSealing

        /// The record carries a seal in an algorithm this build cannot check.
        case unsupportedAlgorithm(String)
    }

    /// The transcript's bytes are exactly the ones ScribeKit sealed.
    case verified

    /// There is no seal this build can check the transcript against.
    case unverified(UnverifiedReason)

    /// The transcript's bytes differ from the ones ScribeKit sealed.
    ///
    /// - Parameters:
    ///   - expectedByteCount: The length the seal records.
    ///   - observedByteCount: The length of the file now.
    case changed(expectedByteCount: Int, observedByteCount: Int)

    /// Compares a transcript's bytes with the seal recorded for it.
    ///
    /// Pure: nothing is read or written. The digest is computed only when
    /// there is a seal this build can check.
    ///
    /// - Parameters:
    ///   - seal: The seal the session record carries, or `nil`.
    ///   - unsealed: Why there is no seal, used when `seal` is `nil`.
    ///   - data: The transcript's bytes as they are now.
    /// - Returns: The verdict.
    static func assess(seal: TranscriptSeal?, unsealed: UnverifiedReason, data: Data) -> TranscriptIntegrity {
        guard let seal else { return .unverified(unsealed) }
        guard seal.isSupported else { return .unverified(.unsupportedAlgorithm(seal.algorithm)) }
        return compare(seal, with: TranscriptSeal.sealing(data))
    }

    /// Compares a recorded seal with one computed from the file now.
    ///
    /// - Parameters:
    ///   - recorded: The seal the session record carries.
    ///   - observed: The seal of the file's current bytes.
    /// - Returns: The verdict.
    static func compare(_ recorded: TranscriptSeal, with observed: TranscriptSeal) -> TranscriptIntegrity {
        guard recorded.isSupported else { return .unverified(.unsupportedAlgorithm(recorded.algorithm)) }
        if recorded.byteCount == observed.byteCount, recorded.digest == observed.digest {
            return .verified
        }
        return .changed(expectedByteCount: recorded.byteCount, observedByteCount: observed.byteCount)
    }

    /// Whether the verdict is something the user should be warned about.
    ///
    /// Only evidence that the file differs from what ScribeKit wrote is. An
    /// unverified transcript is the ordinary state of every meeting recorded
    /// before seals existed and is stated quietly.
    ///
    /// A transcript that is missing or cannot be read has no verdict at all:
    /// History reports it as a session it could not read, and an export
    /// reports it as the reason nothing was written.
    var isWarning: Bool {
        switch self {
        case .verified, .unverified: false
        case .changed: true
        }
    }

    /// A short label for the Details grid.
    var displayName: String {
        switch self {
        case .verified: "Verified"
        case .unverified: "Not verified"
        case .changed: "Changed since ScribeKit closed it"
        }
    }

    /// One or two sentences saying what the verdict means, without quoting the
    /// transcript and without implying a repair.
    var explanation: String {
        switch self {
        case .verified:
            return "The transcript is byte for byte the file ScribeKit wrote when this meeting closed."
        case let .unverified(reason):
            return reason.explanation
        case let .changed(expected, observed):
            let recorded = Self.bytes(expected)
            let now = Self.bytes(observed)
            let shape = observed < expected
                ? "It is shorter than when ScribeKit closed it (\(now) now, \(recorded) then), so it may have been "
                    + "cut short or edited outside ScribeKit."
                : "Its contents differ from the file ScribeKit wrote when this meeting closed (\(now) now, "
                    + "\(recorded) then), so it may have been edited outside ScribeKit."
            return shape + " ScribeKit has not changed or repaired it, and still shows and exports it as it is now."
        }
    }

    /// A file size in the units the Finder uses.
    ///
    /// - Parameter count: The size in bytes.
    /// - Returns: The description.
    private static func bytes(_ count: Int) -> String {
        Int64(count).formatted(.byteCount(style: .file))
    }
}

nonisolated extension TranscriptIntegrity.UnverifiedReason {

    /// Why the transcript was not checked, stated as the ordinary thing it is.
    var explanation: String {
        switch self {
        case .noRecord:
            "This meeting has no session record, so there is no checksum to compare its transcript with. "
            + "That is expected of early meetings and does not mean anything is wrong."
        case .notRecorded:
            "No checksum was recorded when this meeting closed. Meetings recorded before ScribeKit kept "
            + "checksums have none, and that does not mean anything is wrong."
        case .stillOpen:
            "This transcript is still open, or its meeting never finished, so no checksum has been recorded yet."
        case .interruptedBeforeSealing:
            "ScribeKit stopped before this meeting closed, so no checksum was recorded. The transcript holds "
            + "everything that reached the file."
        case .unsupportedAlgorithm:
            "This meeting's checksum was recorded in a form this version of ScribeKit cannot check, "
            + "so it was not compared."
        }
    }
}

nonisolated extension HistorySession {

    /// Why a session would have no seal to check, from what its record says.
    ///
    /// Only consulted when there is no seal. It distinguishes the ordinary
    /// reasons a transcript was never sealed so that each can be stated as
    /// what it is rather than as a single, vaguer "unknown".
    var unsealedReason: TranscriptIntegrity.UnverifiedReason {
        switch status {
        case .unrecorded: .noRecord
        case .inProgress: .stillOpen
        case .interrupted where endedAt == nil: .interruptedBeforeSealing
        case .completed, .failed, .interrupted: .notRecorded
        }
    }
}
