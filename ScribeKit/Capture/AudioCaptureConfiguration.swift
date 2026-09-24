//
//  AudioCaptureConfiguration.swift
//  ScribeKit
//

import Foundation

/// What a capture implementation needs in order to start.
///
/// The value carries only capture inputs. Session metadata — title, save
/// location, audio retention — belongs to the session, not to the stream.
nonisolated struct AudioCaptureConfiguration: Equatable, Sendable {

    /// ScreenCaptureKit's own default rate, requested unchanged so the capture
    /// system is never asked to resample on ScribeKit's behalf.
    static let defaultSampleRate = 48_000

    /// One channel is requested because meeting audio is transcribed as
    /// speech, which is monaural: asking for mono halves the data that crosses
    /// the delivery queue and loses nothing a recogniser would have used.
    /// The format that actually arrives is read back from the sample buffers.
    static let defaultChannelCount = 1

    /// Which capturer the configuration is for.
    let mode: CaptureMode

    /// What to capture: bundle identifiers of the applications for
    /// ``CaptureMode/applications``, or the identifier of the microphone input
    /// the meeting was set up with for ``CaptureMode/microphone``.
    let sourceIDs: Set<CaptureSource.ID>

    /// The requested sample rate in frames per second.
    let sampleRate: Int

    /// The requested number of channels.
    let channelCount: Int

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - sourceIDs: Identifiers of the selected sources.
    ///   - mode: Which capturer the configuration is for. Defaults to
    ///     application capture.
    ///   - sampleRate: Frames per second to request.
    ///   - channelCount: Channels to request.
    init(
        sourceIDs: Set<CaptureSource.ID>,
        mode: CaptureMode = .applications,
        sampleRate: Int = defaultSampleRate,
        channelCount: Int = defaultChannelCount
    ) {
        self.mode = mode
        self.sourceIDs = sourceIDs
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// The format this configuration asks the capture system for.
    ///
    /// Sample buffers are still read back for what actually arrived; this is
    /// what was requested, and it is what a retained audio file is opened for,
    /// because a container's format is fixed when the file is created and the
    /// first buffer has not arrived by then.
    ///
    /// Only application capture requests a format. A microphone delivers the
    /// input device's own rate, which is whatever the device runs at, so
    /// nothing may be opened on the assumption that this is what arrives —
    /// which is one reason Microphone meetings keep no recording.
    var requestedFormat: CapturedAudioFormat {
        CapturedAudioFormat(
            sampleRate: Double(sampleRate),
            channelCount: channelCount,
            bitsPerChannel: 32,
            isFloat: true,
            isInterleaved: false
        )
    }

    /// Creates a configuration from the sources the user selected.
    ///
    /// - Parameter sources: The selected capture sources. A selection that
    ///   mixes modes is refused before a configuration is built; built from
    ///   one anyway, it is treated as application capture, which a microphone
    ///   identifier can never satisfy.
    init(sources: [CaptureSource]) {
        self.init(
            sourceIDs: Set(sources.map(\.id)),
            mode: CaptureMode(sources: sources) ?? .applications
        )
    }
}
