//
//  RetainedAudioPlayback.swift
//  ScribeKit
//

import AVFoundation
import Foundation

/// Where in a retained recording a review candidate is, and how much of the
/// audio around it to play.
///
/// The plan is arithmetic on offsets and nothing else: no file is opened, no
/// asset is created and no clock is consulted, so the seek a candidate
/// produces can be checked exactly.
///
/// The offsets it uses are the ones the meeting recorded. A span's
/// ``TranscriptReviewCandidate/startTime`` is seconds from the first captured
/// frame, and a retained recording's time zero is that same frame, so second
/// *t* of the file is offset *t* of the transcript with nothing to
/// synchronise. The transcript's twelve-hour clock is never used for this: it
/// is a rendering of a moment, not a position in a file.
nonisolated struct RetainedAudioPlaybackPlan: Equatable, Sendable {

    /// How long before the span playback begins, so the passage is heard in
    /// the run-up to it rather than from a cold start mid-word.
    static let leadIn = 2.0

    /// How long after the span playback stops.
    static let leadOut = 1.5

    /// The recording to play.
    let url: URL

    /// Which container the recording is in.
    let format: HistoryAudioFormat

    /// Where playback begins, in seconds from the start of the file. Never
    /// negative: a span in the first seconds of a meeting starts at zero
    /// rather than before the recording exists.
    let startTime: Double

    /// Where playback stops, in seconds from the start of the file.
    let endTime: Double

    /// Where the span itself begins, kept so the interface can say what is
    /// being played rather than where the lead-in started.
    let spanStartTime: Double

    /// The span this plan plays.
    let spanIndex: Int

    /// Plans playback of one review candidate's audio.
    ///
    /// - Parameters:
    ///   - candidate: The span to hear.
    ///   - audio: The recording the meeting kept.
    init(candidate: TranscriptReviewCandidate, audio: HistoryAudio) {
        url = audio.url
        format = audio.format
        spanIndex = candidate.spanIndex
        spanStartTime = candidate.startTime
        startTime = max(0, candidate.startTime - Self.leadIn)
        endTime = max(candidate.endTime, candidate.startTime) + Self.leadOut
    }

    /// Plans playback explicitly, for tests that state the offsets directly.
    ///
    /// - Parameters:
    ///   - url: The recording to play.
    ///   - format: Which container it is in.
    ///   - startTime: Where playback begins.
    ///   - endTime: Where playback stops.
    ///   - spanStartTime: Where the span itself begins.
    ///   - spanIndex: The span being played.
    init(url: URL, format: HistoryAudioFormat, startTime: Double, endTime: Double, spanStartTime: Double, spanIndex: Int) {
        self.url = url
        self.format = format
        self.startTime = startTime
        self.endTime = endTime
        self.spanStartTime = spanStartTime
        self.spanIndex = spanIndex
    }
}

/// Plays a stretch of a retained recording, and owns the sandbox claim that
/// reading it needs.
///
/// Playback is file-backed. `AVPlayer` reads an `AVURLAsset` from disk as it
/// goes, so a multi-hour recording costs the same as a short one and no part
/// of the file is collected in memory — the same rule retention writes under,
/// applied to reading it back.
///
/// The security-scoped claim is explicit and owned. Reading a file inside the
/// folder the user chose needs access held for as long as the read lasts,
/// which for playback is longer than a call, so the player takes a
/// ``SecurityScopedLease`` when it starts and releases it when it stops,
/// fails, or is released. There is no path that leaves one open: every exit
/// goes through ``stop()``.
///
/// Nothing here writes. A recording is opened read-only, its bytes are not
/// modified, and no review state changes because a user listened to something.
@MainActor
@Observable
final class RetainedAudioPlayer {

    /// What the player is doing, as one value.
    enum Playback: Equatable {
        /// Nothing is loaded and no claim is held.
        case idle

        /// A recording is being opened.
        case loading(spanIndex: Int)

        /// A span's audio is playing.
        case playing(spanIndex: Int)

        /// A span's audio is loaded and paused.
        case paused(spanIndex: Int)

        /// The recording could not be played, and why.
        case failed(spanIndex: Int, message: String)
    }

    /// What the player is doing.
    private(set) var playback: Playback = .idle

    private let access: any SecurityScopedResourceAccessing
    private var player: AVPlayer?
    private var lease: SecurityScopedLease?
    private var endObserver: (any NSObjectProtocol)?

    /// Creates a player.
    ///
    /// - Parameter access: How security-scoped access is started and stopped.
    ///   The system by default; a test substitutes a double to prove the claim
    ///   is taken for exactly the length of playback.
    init(access: any SecurityScopedResourceAccessing = SystemSecurityScopedResourceAccess()) {
        self.access = access
    }

    deinit {
        // A player dropped without being stopped must not leave the sandbox
        // claim open. The lease releases itself for the same reason; this is
        // the safety net, not the intended path.
        MainActor.assumeIsolated {
            teardown()
        }
    }

    /// Whether audio is playing right now.
    var isPlaying: Bool {
        if case .playing = playback { return true }
        return false
    }

    /// The span currently loaded, whatever the player is doing with it.
    var loadedSpanIndex: Int? {
        switch playback {
        case .idle: nil
        case let .loading(index), let .playing(index), let .paused(index), let .failed(index, _): index
        }
    }

    /// Why playback failed, when it did.
    var failureMessage: String? {
        guard case let .failed(_, message) = playback else { return nil }
        return message
    }

    /// Plays the audio around one review candidate.
    ///
    /// Any recording already loaded is stopped first, so one player is ever
    /// holding one claim on one file.
    ///
    /// - Parameters:
    ///   - plan: Which recording to play, and which stretch of it.
    ///   - destination: The folder the user chose, which is the security scope
    ///     the recording sits inside. `nil` when the recording is reachable
    ///     without one, as it is in a test's temporary directory.
    func play(_ plan: RetainedAudioPlaybackPlan, in destination: URL?) async {
        stop()
        playback = .loading(spanIndex: plan.spanIndex)

        if let destination {
            do {
                lease = try SecurityScopedLease.acquire(destination, using: access)
            } catch {
                fail(plan, "macOS did not grant ScribeKit access to the folder this recording is in.")
                return
            }
        }

        let asset = AVURLAsset(url: plan.url)
        let isPlayable = (try? await asset.load(.isPlayable)) ?? false
        guard isPlayable else {
            fail(plan, Self.unreadableMessage(for: plan.format))
            return
        }

        let item = AVPlayerItem(asset: asset)
        item.forwardPlaybackEndTime = CMTime(seconds: plan.endTime, preferredTimescale: 600)
        let player = AVPlayer(playerItem: item)
        self.player = player

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.playbackReachedEnd(spanIndex: plan.spanIndex) }
        }

        await player.seek(
            to: CMTime(seconds: plan.startTime, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
        guard self.player === player else { return }
        player.play()
        playback = .playing(spanIndex: plan.spanIndex)
    }

    /// Pauses playback, keeping the recording open and the claim held so it
    /// can be resumed.
    func pause() {
        guard case let .playing(index) = playback else { return }
        player?.pause()
        playback = .paused(spanIndex: index)
    }

    /// Resumes a paused span.
    func resume() {
        guard case let .paused(index) = playback, let player else { return }
        player.play()
        playback = .playing(spanIndex: index)
    }

    /// Stops playback, closes the recording and gives up the sandbox claim.
    func stop() {
        teardown()
        playback = .idle
    }

    /// Reports that the stretch being played has finished.
    ///
    /// - Parameter spanIndex: The span that was playing.
    private func playbackReachedEnd(spanIndex: Int) {
        guard loadedSpanIndex == spanIndex else { return }
        teardown()
        playback = .idle
    }

    /// Reports a failure and gives up whatever was taken for it.
    ///
    /// - Parameters:
    ///   - plan: What was being played.
    ///   - message: What to tell the user.
    private func fail(_ plan: RetainedAudioPlaybackPlan, _ message: String) {
        teardown()
        playback = .failed(spanIndex: plan.spanIndex, message: message)
    }

    /// Releases the player, the notification observer and the lease, in that
    /// order, leaving nothing held.
    private func teardown() {
        player?.pause()
        player = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
        lease?.release()
        lease = nil
    }

    /// What to say about a recording that would not open.
    ///
    /// - Parameter format: The container the file is in.
    /// - Returns: A message that states the likely cause without claiming to
    ///   have diagnosed it, and without offering a repair ScribeKit does not
    ///   do.
    private static func unreadableMessage(for format: HistoryAudioFormat) -> String {
        switch format {
        case .compressed:
            "This recording could not be opened. An M4A file is indexed when it is closed, so a meeting "
            + "that was killed before its recording was finalised leaves one that does not play. "
            + "ScribeKit does not repair it."
        case .raw:
            "This recording could not be opened."
        }
    }
}
