//
//  CapturedMediaClock.swift
//  ScribeKit
//

import Foundation
import Synchronization

/// How much audio a meeting has actually captured, in seconds.
///
/// This is *media* time, not wall-clock time: it advances only while capture
/// is running, so a meeting that was paused for five minutes is five minutes
/// shorter here than it is on the wall. That is the timeline the transcript's
/// offsets and the retained recording share — offset *t* is second *t* of the
/// file — and pausing a meeting must not move one without the other.
///
/// The clock is a capture consumer rather than a timer, so it counts the same
/// buffers the recogniser and the retainer see, in the same order, on the
/// capture system's own delivery queue. Each buffer contributes its own frame
/// count over its own sample rate, so a capture format that changes mid-meeting
/// is counted correctly rather than at whichever rate arrived last.
nonisolated final class CapturedMediaClock: AudioSampleConsuming {

    private let state = Mutex(0.0)

    /// Creates a clock reading zero.
    init() {}

    /// Seconds of audio captured since the last ``reset()``.
    var seconds: Double { state.withLock { $0 } }

    /// Returns the clock to zero, for a new meeting.
    func reset() {
        state.withLock { $0 = 0 }
    }

    func consume(_ buffer: CapturedPCMBuffer) {
        let rate = buffer.format.sampleRate
        guard rate > 0 else { return }
        let seconds = Double(buffer.frameCount) / rate
        state.withLock { $0 += seconds }
    }
}
