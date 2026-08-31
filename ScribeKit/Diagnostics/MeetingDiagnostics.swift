//
//  MeetingDiagnostics.swift
//  ScribeKit
//

import AppKit
import OSLog
import UniformTypeIdentifiers

/// The one place a diagnostic report is assembled and saved.
///
/// It lives as long as the process, beside the meeting it describes, because
/// the window may be closed when somebody needs a report and a menu bar
/// application has to be able to explain itself with nothing on screen. What
/// the window knows and the process does not — the readiness rows, the save
/// location's standing, what the last recovery scan found — is published here
/// while the setup screen is up and kept as one current value afterwards.
///
/// That value is a snapshot, not a history. Nothing accumulates, nothing is
/// persisted, and no timer refreshes it: a report is assembled from what is
/// true when the user asks for one, and forgotten as soon as it is written.
@MainActor
@Observable
final class MeetingDiagnostics {

    /// What the setup screen derives and the process otherwise cannot see.
    struct SetupState: Equatable {
        /// Whether a meeting could be started, and what is stopping it.
        let readiness: MeetingStartReadiness

        /// The standing of the folder meetings are written to.
        let saveLocation: SaveLocationReadiness

        /// What discovery last reported.
        let sources: CaptureSourceReadiness

        /// What the last unfinished-session scan found.
        let recovery: SessionRecoveryModel.State
    }

    /// What the setup screen last derived, or `nil` when it has not been on
    /// screen in this launch.
    private(set) var setup: SetupState?

    /// The meeting being described.
    private let runtime: MeetingRuntime

    /// Turns a report into bytes on disk.
    private let writer: DiagnosticReportWriter

    /// Reads the wall clock.
    private let now: () -> Date

    /// Asks the user where to save, and answers `nil` when they cancel.
    private let chooseDestination: @MainActor (String, String) -> URL?

    /// What the user is told about a report that could not be written.
    private let announceFailure: @MainActor (String) -> Void

    /// What the save panel says a report is, before the user agrees to make
    /// one.
    ///
    /// Deliberately specific. It does not claim the report holds no personal
    /// information, because a macOS version, an application version and a
    /// recognition locale are still facts about somebody's Mac; it says what is
    /// in it and what is not, and that ScribeKit does not send it anywhere.
    static let privacyMessage = """
        This report describes ScribeKit itself: its version, this Mac's macOS \
        version and architecture, the state of the current or most recent \
        meeting, durations, counts, and the categories of anything that failed.

        It does not contain transcript text, recognised speech, audio, notes, \
        review passages, meeting titles, application names or folder paths.

        It is written only to the location you choose here. ScribeKit does not \
        upload it and makes no network connection of its own.
        """

    /// Creates the diagnostics owner.
    ///
    /// - Parameters:
    ///   - runtime: The application's meeting owner.
    ///   - writer: Writes the report. Tests substitute one that cannot reach
    ///     the filesystem.
    ///   - now: Reads the wall clock.
    ///   - chooseDestination: Asks the user where to save, given a suggested
    ///     filename and the message explaining what a report is. The default
    ///     runs a system save panel; tests substitute a decision.
    ///   - announceFailure: Tells the user a report could not be written.
    init(
        runtime: MeetingRuntime,
        writer: DiagnosticReportWriter = DiagnosticReportWriter(),
        now: @escaping () -> Date = { Date() },
        chooseDestination: @escaping @MainActor (String, String) -> URL? = MeetingDiagnostics.runSavePanel,
        announceFailure: @escaping @MainActor (String) -> Void = MeetingDiagnostics.presentFailure
    ) {
        self.runtime = runtime
        self.writer = writer
        self.now = now
        self.chooseDestination = chooseDestination
        self.announceFailure = announceFailure
    }

    /// Records what the setup screen currently derives.
    ///
    /// Called as those values change rather than polled, and it replaces what
    /// was there: there is one current answer, never a list of past ones.
    ///
    /// - Parameter state: What the screen derived.
    func publish(_ state: SetupState) {
        guard setup != state else { return }
        setup = state
    }

    /// Assembles a report from what is true now.
    ///
    /// - Returns: The report the user would be saving.
    func makeReport() -> DiagnosticReport {
        DiagnosticReport.make(runtime: runtime, setup: setup, generatedAt: now())
    }

    /// Asks the user where to save a report, and writes one there.
    ///
    /// Explicit from end to end: nothing is assembled until this is called,
    /// nothing is written until the user has picked a destination, and a
    /// cancelled panel leaves no file and no trace.
    ///
    /// - Returns: Where the report was written, or `nil` when the user
    ///   cancelled or the write failed.
    @discardableResult
    func export() -> URL? {
        let date = now()
        let report = makeReport()
        let name = DiagnosticReportWriter.filename(for: date)
        guard let url = chooseDestination(name, Self.privacyMessage) else {
            ScribeKitLog.diagnostics.debug("Diagnostic export cancelled")
            return nil
        }
        do {
            let bytes = try writer.write(report, to: url)
            ScribeKitLog.diagnostics.info(
                "Diagnostic report written: \(bytes, privacy: .public) bytes"
            )
            return url
        } catch {
            ScribeKitLog.diagnostics.error(
                "Diagnostic report not written: \(DiagnosticSafety.systemErrorIdentity(error).code, privacy: .public)"
            )
            let message = (error as? LocalizedError)?.errorDescription
                ?? DiagnosticReportWriteError.writeFailed.errorDescription
            announceFailure(message ?? "")
            return nil
        }
    }

    /// Runs the system save panel.
    ///
    /// - Parameters:
    ///   - name: The suggested filename.
    ///   - message: What the report is, shown above the file list.
    /// - Returns: The chosen destination, or `nil` when the user cancelled.
    private static func runSavePanel(name: String, message: String) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Diagnostics Report"
        panel.message = message
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    /// Tells the user a report could not be written.
    ///
    /// - Parameter message: What went wrong.
    private static func presentFailure(_ message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "The diagnostics report was not saved"
        alert.informativeText = message + " Nothing was written, and this Mac is unchanged."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
