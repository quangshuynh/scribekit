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

    /// Bundle identifiers of the applications to capture.
    let sourceIDs: Set<CaptureSource.ID>

    /// The requested sample rate in frames per second.
    let sampleRate: Int

    /// The requested number of channels.
    let channelCount: Int

    /// Creates a configuration.
    ///
    /// - Parameters:
    ///   - sourceIDs: Bundle identifiers of the selected applications.
    ///   - sampleRate: Frames per second to request.
    ///   - channelCount: Channels to request.
    init(
        sourceIDs: Set<CaptureSource.ID>,
        sampleRate: Int = defaultSampleRate,
        channelCount: Int = defaultChannelCount
    ) {
        self.sourceIDs = sourceIDs
        self.sampleRate = sampleRate
        self.channelCount = channelCount
    }

    /// Creates a configuration from the sources the user selected.
    ///
    /// - Parameter sources: The selected capture sources.
    init(sources: [CaptureSource]) {
        self.init(sourceIDs: Set(sources.map(\.id)))
    }
}
