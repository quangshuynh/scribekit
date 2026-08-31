//
//  DiagnosticReportAssembly.swift
//  ScribeKit
//

import Foundation

nonisolated extension DiagnosticReport.Application {
    /// The running application, read from its own bundle.
    static var current: Self {
        let info = Bundle.main.infoDictionary
        return Self(
            bundleIdentifier: Bundle.main.bundleIdentifier ?? "unknown",
            version: info?["CFBundleShortVersionString"] as? String ?? "unknown",
            build: info?["CFBundleVersion"] as? String ?? "unknown"
        )
    }
}

nonisolated extension DiagnosticReport.System {
    /// The Mac this is running on, in the two respects that change what
    /// ScribeKit can do: which macOS, and which architecture.
    ///
    /// Nothing here identifies the machine. There is no serial number, no host
    /// name, no user name and no network address, and there is no reason for
    /// diagnostics to want one.
    static var current: Self {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #if arch(arm64)
        let architecture = "arm64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "unknown"
        #endif
        return Self(
            operatingSystemVersion:
                "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            architecture: architecture
        )
    }
}

nonisolated extension DiagnosticReport.Readiness {
    /// Describes readiness as statuses alone.
    ///
    /// Each row's `detail` is deliberately dropped: it is the sentence the
    /// screen shows, and it names the chosen folder, the applications that
    /// disappeared and the framework's own complaint. The status is what a
    /// support conversation needs, and it carries none of that.
    ///
    /// - Parameters:
    ///   - readiness: What the setup screen derived.
    ///   - sources: What discovery last reported.
    init(_ readiness: MeetingStartReadiness, sources: CaptureSourceReadiness) {
        let counts: (discovered: Int, selected: Int, dropped: Int)?
        if case let .discovered(available, selected, droppedSelections) = sources {
            counts = (available, selected, droppedSelections.count)
        } else {
            counts = nil
        }
        self.init(
            canStart: readiness.canStart,
            blocker: readiness.blocker?.prerequisite.diagnosticName,
            prerequisites: readiness.rows.map {
                Prerequisite(name: $0.prerequisite.diagnosticName, status: $0.status.diagnosticName)
            },
            discoveredSourceCount: counts?.discovered,
            selectedSourceCount: counts?.selected,
            droppedSelectionCount: counts?.dropped
        )
    }
}

nonisolated extension DiagnosticReport.Storage {
    /// Describes the save location without naming it.
    ///
    /// Whether a folder was chosen, whether access to it currently resolves,
    /// and whether the choice survived relaunch answer every save-location
    /// support question. Where the folder is answers none of them, and is a
    /// path through somebody's home directory.
    ///
    /// - Parameters:
    ///   - saveLocation: What the destination model reports.
    ///   - sources: What discovery reported, which is the only authority on
    ///     capture access.
    init(saveLocation: SaveLocationReadiness, sources: CaptureSourceReadiness) {
        let captureAccess: Bool?
        switch sources {
        case .accessUnavailable: captureAccess = false
        case .discovered, .noApplicationsFound: captureAccess = true
        case .notAttempted, .discovering, .discoveryFailed: captureAccess = nil
        }
        switch saveLocation {
        case .notChosen:
            self.init(
                saveLocationChosen: false,
                saveLocationResolved: false,
                saveLocationRemembered: false,
                captureAccessAvailable: captureAccess
            )
        case .ready:
            self.init(
                saveLocationChosen: true,
                saveLocationResolved: true,
                saveLocationRemembered: true,
                captureAccessAvailable: captureAccess
            )
        case .readyNotRemembered:
            self.init(
                saveLocationChosen: true,
                saveLocationResolved: true,
                saveLocationRemembered: false,
                captureAccessAvailable: captureAccess
            )
        case .unusable:
            self.init(
                saveLocationChosen: true,
                saveLocationResolved: false,
                saveLocationRemembered: false,
                captureAccessAvailable: captureAccess
            )
        }
    }
}

nonisolated extension DiagnosticReport.Recovery {
    /// Describes what the last scan for unfinished sessions found, as counts
    /// and reasons rather than as folders.
    ///
    /// - Parameter state: What the recovery model holds.
    init(_ state: SessionRecoveryModel.State) {
        let schemas = (
            session: SessionRecoveryMetadata.currentSchemaVersion,
            review: SessionReviewMetadata.currentSchemaVersion,
            derived: DerivedSessionState.currentSchemaVersion
        )
        switch state {
        case .unchecked, .checking:
            self.init(
                scanned: false,
                unfinishedSessionCount: 0,
                unreadableSessionCount: 0,
                problems: [],
                sessionMetadataSchemaVersion: schemas.session,
                reviewMetadataSchemaVersion: schemas.review,
                derivedMetadataSchemaVersion: schemas.derived
            )
        case .clear, .unavailable:
            self.init(
                scanned: true,
                unfinishedSessionCount: 0,
                unreadableSessionCount: 0,
                problems: [],
                sessionMetadataSchemaVersion: schemas.session,
                reviewMetadataSchemaVersion: schemas.review,
                derivedMetadataSchemaVersion: schemas.derived
            )
        case let .found(report):
            self.init(
                scanned: true,
                unfinishedSessionCount: report.candidates.count,
                unreadableSessionCount: report.problems.count,
                problems: Set(report.problems.map(\.error.diagnosticName)).sorted(),
                sessionMetadataSchemaVersion: schemas.session,
                reviewMetadataSchemaVersion: schemas.review,
                derivedMetadataSchemaVersion: schemas.derived
            )
        }
    }
}

@MainActor
extension DiagnosticReport {

    /// Assembles a report from state that already exists.
    ///
    /// Nothing is read from disk, no canonical artifact is opened, and nothing
    /// is written: this reads the meeting owner's own published state and
    /// whatever the setup screen last derived, and turns them into counts and
    /// stable names. A report generated during a meeting therefore cannot
    /// disturb it, and one generated afterwards cannot alter what it left
    /// behind.
    ///
    /// - Parameters:
    ///   - runtime: The application's meeting owner.
    ///   - setup: What the setup screen last derived, or `nil` when it has not
    ///     been on screen in this launch.
    ///   - generatedAt: When the report is being made.
    /// - Returns: A report safe to hand to somebody else.
    static func make(
        runtime: MeetingRuntime,
        setup: MeetingDiagnostics.SetupState?,
        generatedAt: Date = Date()
    ) -> DiagnosticReport {
        DiagnosticReport(
            schemaVersion: DiagnosticReport.currentSchemaVersion,
            generatedAt: generatedAt,
            application: .current,
            system: .current,
            runtime: Runtime(
                status: runtime.status.diagnosticName,
                isRunning: runtime.isRunning,
                capture: runtime.captureState.diagnosticName,
                recognition: runtime.transcriptionState.diagnosticName,
                transcript: runtime.persistenceState.diagnosticName,
                audio: runtime.audioRetentionState.diagnosticName,
                recognitionLocaleIdentifier: runtime.localeIdentifier,
                speechAvailability: runtime.availability.diagnosticName,
                installedRecognitionLocaleCount: runtime.availableLocales.count
            ),
            readiness: setup.map { Readiness($0.readiness, sources: $0.sources) },
            storage: setup.map { Storage(saveLocation: $0.saveLocation, sources: $0.sources) },
            recovery: Recovery(setup?.recovery ?? .unchecked),
            session: SessionSummary(runtime: runtime),
            lastOutcome: Outcome(runtime: runtime)
        )
    }
}

@MainActor
extension DiagnosticReport.SessionSummary {

    /// Describes the meeting that is running, or the last one to end.
    ///
    /// The snapshot the meeting was started with is read for its counts and
    /// its locale and for nothing else: the title is prose the user wrote, the
    /// destination is a path through their home folder, and the applications
    /// say who they were meeting.
    ///
    /// - Parameter runtime: The application's meeting owner.
    init?(runtime: MeetingRuntime) {
        guard let meeting = runtime.meeting else { return nil }
        let format = runtime.requestedCaptureFormat
        self.init(
            phase: runtime.isRunning ? "active" : "ended",
            retentionMode: meeting.audioRetention.diagnosticName,
            recognitionLocaleIdentifier: meeting.localeIdentifier,
            selectedSourceCount: meeting.sources.count,
            startedAt: meeting.startedAt,
            wallDurationSeconds: runtime.elapsed.elapsed,
            capturedDurationSeconds: runtime.capturedDuration,
            pauseCount: runtime.pauseCount,
            recognitionRestartCount: runtime.recognitionRestartCount,
            transcriptSpanCount: runtime.transcriptSpanCount,
            gapCount: runtime.gapCount,
            untranscribedSeconds: runtime.transcript.untranscribedSeconds,
            recordingPresent: runtime.audioRetentionState.url != nil,
            capturedSampleRate: format?.sampleRate,
            capturedChannelCount: format?.channelCount
        )
    }
}

@MainActor
extension DiagnosticReport.Outcome {

    /// Describes how the last meeting ended, as the category the user was
    /// shown rather than the paragraph explaining it.
    ///
    /// The outcome's `detail` — the framework's own message — is not carried:
    /// it is written by another team, it can name a file, and the category
    /// says what it says without that risk.
    ///
    /// - Parameter runtime: The application's meeting owner.
    init?(runtime: MeetingRuntime) {
        guard let outcome = runtime.outcome else { return nil }
        self.init(
            category: outcome.category.diagnosticName,
            diagnosticCategory: DiagnosticCategory(outcome: outcome.category),
            capturedAudio: runtime.lastCompletion?.capturedAudio ?? false
        )
    }
}
