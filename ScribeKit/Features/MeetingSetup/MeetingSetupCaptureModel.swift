//
//  MeetingSetupCaptureModel.swift
//  ScribeKit
//

import Foundation

/// Owns the capture part of the meeting setup screen: whether capture is
/// running, what it has delivered, and what to say when it fails.
///
/// The model drives an ``AudioCapturing`` value and never touches
/// ScreenCaptureKit, so the screen's behaviour is testable without capture
/// permission or a real meeting. Audio itself does not pass through here: the
/// capturer delivers buffers to an ``AudioCaptureActivityMonitor`` on its own
/// queue, and only coalesced summaries reach the main actor.
@MainActor
@Observable
final class MeetingSetupCaptureModel {

    /// The capture subsystem's current state.
    private(set) var state: AudioCaptureState = .idle

    /// What capture has delivered since it last started.
    private(set) var activity: AudioCaptureActivity = .none

    private let capturer: AudioCapturing
    private let monitor: AudioCaptureActivityMonitor

    /// Observes the capturer's interruptions for as long as the model exists.
    ///
    /// The sequence finishes when the capturer is released, which happens with
    /// the model, so the task ends with it.
    private var interruptionTask: Task<Void, Never>?

    /// Creates a model with its own capture stack.
    ///
    /// - Parameters:
    ///   - monitor: Accumulates delivered audio. Defaults to a fresh monitor,
    ///     which the model connects to its own published activity.
    ///   - makeCapturer: Builds the capturer around the monitor. The default
    ///     builds the ScreenCaptureKit implementation; tests substitute a fake.
    init(
        monitor: AudioCaptureActivityMonitor = AudioCaptureActivityMonitor(),
        makeCapturer: (AudioSampleConsuming) -> AudioCapturing = {
            ScreenCaptureKitAudioCapturer(consumer: $0)
        }
    ) {
        self.monitor = monitor
        self.capturer = makeCapturer(monitor)
        monitor.onUpdate = { [weak self] activity in
            Task { @MainActor [weak self] in self?.activity = activity }
        }
        let interruptions = capturer.interruptions
        interruptionTask = Task { [weak self] in
            for await error in interruptions {
                self?.handleInterruption(error)
            }
        }
    }

    /// Whether the interface should offer to start capture.
    ///
    /// - Parameter sources: The applications currently selected.
    /// - Returns: `true` when a start would be meaningful.
    func canStart(sources: [CaptureSource]) -> Bool {
        state.canStart && !sources.isEmpty
    }

    /// Whether the interface should offer to stop capture.
    var canStop: Bool { state.canStop }

    /// Starts capturing the selected applications.
    ///
    /// A start that is refused leaves the model in ``AudioCaptureState/failed``
    /// with the reason: capture is never reported as running when it is not.
    ///
    /// - Parameter sources: The applications the user selected.
    func start(sources: [CaptureSource]) async {
        guard state.canStart else { return }
        state = .preparing
        monitor.reset()
        activity = .none
        do {
            try await capturer.start(configuration: AudioCaptureConfiguration(sources: sources))
            state = .capturing
        } catch {
            state = .failed(message: message(for: error, sources: sources))
        }
    }

    /// Stops capturing.
    func stop() async {
        guard state.canStop else { return }
        state = .stopping
        await capturer.stop()
        state = .idle
    }

    /// Records the capture system ending a stream by itself.
    ///
    /// - Parameter error: The reason capture ended.
    private func handleInterruption(_ error: AudioCaptureError) {
        guard state.isActive else { return }
        state = .failed(message: message(for: error, sources: []))
    }

    /// Converts a capture error into a message for the screen.
    ///
    /// Unavailable sources are named rather than listed by bundle identifier
    /// when the selection they came from is known.
    ///
    /// - Parameters:
    ///   - error: The error capture reported.
    ///   - sources: The selection the start was made from, used to name
    ///     applications.
    /// - Returns: A user-facing description.
    private func message(for error: Error, sources: [CaptureSource]) -> String {
        if case let AudioCaptureError.sourcesUnavailable(identifiers) = error, !sources.isEmpty {
            let names = identifiers.map { identifier in
                sources.first { $0.id == identifier }?.displayName ?? identifier
            }
            return "No longer running, so capture did not start: " + names.formatted(.list(type: .and))
        }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
