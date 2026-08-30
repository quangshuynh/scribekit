//
//  HistorySession.swift
//  ScribeKit
//

import Foundation

/// Where a session ScribeKit found in the save folder stands.
///
/// This is broader than ``SessionRecoveryStatus`` by exactly one case.
/// Recovery asks whether a meeting is unfinished, so every session it
/// considers has a record; history asks what is in the folder, and a
/// transcript written before session records existed is a real meeting with no
/// record to read. ``unrecorded`` says that, rather than guessing a lifecycle
/// position nothing wrote down.
nonisolated enum HistorySessionStatus: String, Equatable, Sendable, CaseIterable {
    /// The session's record still says its transcript is open. Either a
    /// meeting is running right now, or one was interrupted and has not been
    /// reported yet.
    case inProgress

    /// The meeting ended normally and its artifacts were closed.
    case completed

    /// The meeting ended because a durable artifact stopped being saved.
    case failed

    /// The meeting was found unfinished after a relaunch and reported.
    case interrupted

    /// The directory holds a ScribeKit transcript and no session record, so
    /// only what the transcript itself states is known.
    case unrecorded

    /// Adopts the status a session record carries.
    ///
    /// - Parameter status: The recorded status.
    init(_ status: SessionRecoveryStatus) {
        switch status {
        case .inProgress: self = .inProgress
        case .completed: self = .completed
        case .failed: self = .failed
        case .interrupted: self = .interrupted
        }
    }

    /// A short label for a list row.
    var displayName: String {
        switch self {
        case .inProgress: "In Progress"
        case .completed: "Completed"
        case .failed: "Failed"
        case .interrupted: "Interrupted"
        case .unrecorded: "Legacy"
        }
    }

    /// One sentence saying what the status means for the artifacts.
    var explanation: String {
        switch self {
        case .inProgress:
            "This session's record still says its transcript is open — either it is being written now, "
            + "or the meeting never finished."
        case .completed:
            "The meeting ended normally. Its transcript, and its recording if it kept one, were closed."
        case .failed:
            "The meeting ended because a durable artifact stopped being saved. What reached the files is here."
        case .interrupted:
            "ScribeKit stopped before this meeting finished. The transcript ends at the last speech that "
            + "reached the file."
        case .unrecorded:
            "This meeting has no ScribeKit session record, so only what its transcript states is known."
        }
    }
}

/// Which retained recording format a session's audio file is in.
nonisolated enum HistoryAudioFormat: String, Equatable, Sendable {
    /// Linear PCM in a CAF container, as ``AudioRetentionMode/raw`` writes.
    case raw

    /// AAC in an MPEG-4 container, as ``AudioRetentionMode/compressed`` writes.
    case compressed

    /// Recognises a recording by its file extension.
    ///
    /// - Parameter fileExtension: The file's extension, without its dot.
    /// - Returns: The format, or `nil` for a file ScribeKit does not write.
    init?(fileExtension: String) {
        switch fileExtension.lowercased() {
        case "caf": self = .raw
        case "m4a": self = .compressed
        default: return nil
        }
    }

    /// A short label naming the file the user will find in the folder.
    var displayName: String {
        switch self {
        case .raw: "CAF (lossless)"
        case .compressed: "M4A (compressed)"
        }
    }
}

/// A retained recording history found beside a transcript.
///
/// Measured, never opened: history reports a recording's format, size and
/// modification date and makes no claim that it plays. ScribeKit has no
/// playback.
nonisolated struct HistoryAudio: Equatable, Sendable {

    /// Where the recording is.
    let url: URL

    /// Which format it is in, from its extension.
    let format: HistoryAudioFormat

    /// Its size and modification date, as the filesystem reports them.
    let file: SessionFileInfo

    /// Creates the description.
    ///
    /// - Parameters:
    ///   - url: Where the recording is.
    ///   - format: Which format it is in.
    ///   - file: Its size and modification date.
    init(url: URL, format: HistoryAudioFormat, file: SessionFileInfo) {
        self.url = url
        self.format = format
        self.file = file
    }
}

/// One meeting as history found it in the user's save folder.
///
/// Everything here is either read from the session record, read from the
/// transcript's own header, or measured from the filesystem. Nothing is
/// inferred: a legacy session has no start time because none was written down,
/// and saying so is more useful than a plausible date derived from a folder
/// name.
///
/// The type holds no transcript text. Search needs the words and the detail
/// pane needs a preview, so both come from a ``TranscriptSearchDocument`` that
/// lives for as long as the History screen is loaded and is thrown away on the
/// next refresh. The session itself stays small enough to keep in a list.
nonisolated struct HistorySession: Identifiable, Equatable, Sendable {

    /// The session's directory inside the save folder.
    let directory: URL

    /// The session's recorded identity, or `nil` for a session with no record.
    let sessionID: UUID?

    /// The meeting's title, from the record or from the transcript's heading.
    let title: String

    /// Where the session stands.
    let status: HistorySessionStatus

    /// When the meeting's timeline began, from its record. `nil` for a session
    /// with no record: the transcript states a date and a clock time, and
    /// turning those back into a moment would mean guessing the time zone the
    /// meeting was held in.
    let startedAt: Date?

    /// When ScribeKit closed the session, when it did.
    let endedAt: Date?

    /// Display names of the captured applications.
    let sourceNames: [String]

    /// The BCP-47 locale recognition ran in, when it is known.
    let localeIdentifier: String?

    /// Where the transcript is.
    let transcriptURL: URL

    /// The transcript's size and modification date.
    let transcript: SessionFileInfo

    /// What the meeting was asked to keep of its audio, when a record says so.
    let audioRetention: AudioRetentionMode?

    /// The retained recording, when one is actually in the folder.
    let audio: HistoryAudio?

    /// The directory, which identifies the session uniquely within one scan
    /// and exists for a legacy session that has no recorded identity.
    var id: URL { directory }

    /// Whether the session has no ScribeKit record.
    var isLegacy: Bool { status == .unrecorded }

    /// How long the meeting ran, when both ends of it were recorded.
    var duration: TimeInterval? {
        guard let startedAt, let endedAt else { return nil }
        return max(0, endedAt.timeIntervalSince(startedAt))
    }

    /// Whether the record says audio was being kept but no file is there.
    ///
    /// True of a meeting that was killed before its first captured buffer, and
    /// worth saying rather than showing as a meeting that kept nothing.
    var isMissingExpectedAudio: Bool {
        audio == nil && (audioRetention?.retainsAudio ?? false)
    }

    /// The moment the list is ordered by.
    ///
    /// The recorded start when there is one, and otherwise the last time the
    /// transcript was written, which is the only date a session with no record
    /// actually has.
    var sortDate: Date {
        startedAt ?? transcript.modifiedAt ?? .distantPast
    }

    /// Creates a session.
    ///
    /// - Parameters:
    ///   - directory: The session's directory.
    ///   - sessionID: Its recorded identity, when it has one.
    ///   - title: The meeting's title.
    ///   - status: Where the session stands.
    ///   - startedAt: When the meeting's timeline began.
    ///   - endedAt: When ScribeKit closed the session.
    ///   - sourceNames: Display names of the captured applications.
    ///   - localeIdentifier: The recognition locale.
    ///   - transcriptURL: Where the transcript is.
    ///   - transcript: The transcript's size and modification date.
    ///   - audioRetention: What the meeting was asked to keep of its audio.
    ///   - audio: The retained recording, when one is in the folder.
    init(
        directory: URL,
        sessionID: UUID?,
        title: String,
        status: HistorySessionStatus,
        startedAt: Date?,
        endedAt: Date?,
        sourceNames: [String],
        localeIdentifier: String?,
        transcriptURL: URL,
        transcript: SessionFileInfo,
        audioRetention: AudioRetentionMode?,
        audio: HistoryAudio?
    ) {
        self.directory = directory
        self.sessionID = sessionID
        self.title = title
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceNames = sourceNames
        self.localeIdentifier = localeIdentifier
        self.transcriptURL = transcriptURL
        self.transcript = transcript
        self.audioRetention = audioRetention
        self.audio = audio
    }
}

/// One session's metadata together with the words that were said in it.
///
/// This is what search runs against. It is built once when History loads, held
/// for as long as that load is on screen, and replaced wholesale by the next
/// refresh — never written to disk, and never a second copy of a transcript
/// that outlives the screen showing it.
nonisolated struct TranscriptSearchDocument: Identifiable, Equatable, Sendable {

    /// The session the text belongs to.
    let session: HistorySession

    /// What the meeting observed about its own recognition, when a readable
    /// review sidecar was beside the transcript.
    ///
    /// `nil` for every session recorded before review metadata existed, for a
    /// session whose sidecar could not be written, and for one whose sidecar
    /// this build cannot interpret. All three mean the same thing to the
    /// interface: there is no review information for this meeting, and
    /// everything else about it works normally.
    let review: SessionReviewMetadata?

    /// The finalised spans, in the order the transcript wrote them.
    ///
    /// Only recognised speech. Header fields, minute headings, gap
    /// blockquotes, the interruption notice and the footer are structure
    /// ScribeKit wrote about the meeting, so they are not searchable text and
    /// cannot produce a match.
    let spans: [TranscriptSpan]

    /// The session's directory.
    var id: URL { session.id }

    /// Creates a document.
    ///
    /// - Parameters:
    ///   - session: The session the text belongs to.
    ///   - spans: The finalised spans.
    ///   - review: What the meeting observed about its own recognition.
    init(session: HistorySession, spans: [TranscriptSpan], review: SessionReviewMetadata? = nil) {
        self.session = session
        self.spans = spans
        self.review = review
    }

    /// The review candidates that name a span this transcript actually has,
    /// in transcript order, each paired with the words it points at.
    ///
    /// A candidate naming a span the document does not contain is dropped
    /// rather than shown against the wrong words: review points at the
    /// transcript, so a sidecar that disagrees with it loses.
    var reviewCandidates: [(candidate: TranscriptReviewCandidate, span: TranscriptSpan)] {
        guard let review else { return [] }
        return review.orderedCandidates.compactMap { candidate in
            guard candidate.spanIndex >= 0, candidate.spanIndex < spans.count else { return nil }
            return (candidate, spans[candidate.spanIndex])
        }
    }
}
