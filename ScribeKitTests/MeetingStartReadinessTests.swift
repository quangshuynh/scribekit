//
//  MeetingStartReadinessTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("MeetingStartReadiness")
struct MeetingStartReadinessTests {

    /// A readiness value with everything satisfied unless a test says
    /// otherwise, so each test states only the thing it is about.
    private func readiness(
        saveLocation: SaveLocationReadiness = .ready(path: "/Users/example/Meetings"),
        sources: CaptureSourceReadiness = .discovered(available: 3, selected: 1, droppedSelections: []),
        speech: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US"),
        meetingIsActive: Bool = false
    ) -> MeetingStartReadiness {
        MeetingStartReadiness(
            saveLocation: saveLocation,
            captureSources: sources,
            speech: speech,
            meetingIsActive: meetingIsActive
        )
    }

    /// The row for one prerequisite.
    private func row(
        _ prerequisite: MeetingStartReadiness.Prerequisite,
        in readiness: MeetingStartReadiness
    ) -> MeetingStartReadiness.Row? {
        readiness.rows.first { $0.prerequisite == prerequisite }
    }

    @Test("Everything satisfied allows a start")
    func ready() {
        let readiness = readiness()
        #expect(readiness.canStart)
        #expect(readiness.blocker == nil)
        #expect(readiness.rows.allSatisfy { $0.status == .satisfied })
        #expect(readiness.rows.map(\.prerequisite) == MeetingStartReadiness.Prerequisite.allCases)
    }

    @Test("No save location blocks the start and says what to choose")
    func noSaveLocation() {
        let readiness = readiness(saveLocation: .notChosen)
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.prerequisite == .saveLocation)
        #expect(readiness.blocker?.status == .blocked)
        #expect(readiness.startExplanation.contains("Save location"))
    }

    @Test("A folder that cannot be used blocks the start with the reason it failed")
    func unusableSaveLocation() {
        let readiness = readiness(saveLocation: .unusable(message: "The saved folder could not be found."))
        #expect(readiness.blocker?.prerequisite == .saveLocation)
        #expect(readiness.blocker?.detail == "The saved folder could not be found.")
    }

    @Test("A folder that could not be remembered is usable and does not block a start")
    func saveLocationNotRemembered() {
        let readiness = readiness(
            saveLocation: .readyNotRemembered(path: "/Volumes/Work", message: "It will need choosing again.")
        )
        #expect(readiness.canStart)
        #expect(row(.saveLocation, in: readiness)?.status == .advisory)
    }

    @Test("Missing capture access blocks the start ahead of the empty source list it causes")
    func captureAccessUnavailable() {
        let readiness = readiness(sources: .accessUnavailable(message: "Grant it in System Settings."))
        #expect(readiness.blocker?.prerequisite == .captureAccess)
        #expect(row(.captureSource, in: readiness)?.status == .blocked)
    }

    @Test("A discovery failure that is not about access is reported as itself")
    func discoveryFailed() {
        let readiness = readiness(sources: .discoveryFailed(message: "Applications could not be listed."))
        #expect(readiness.blocker?.prerequisite == .captureAccess)
        #expect(readiness.blocker?.detail == "Applications could not be listed.")
    }

    @Test("Finding no applications is a source problem, not an access problem")
    func noApplicationsFound() {
        let readiness = readiness(sources: .noApplicationsFound)
        #expect(row(.captureAccess, in: readiness)?.status == .satisfied)
        #expect(readiness.blocker?.prerequisite == .captureSource)
    }

    @Test("Discovering applications without selecting one blocks the start")
    func noSourceSelected() {
        let readiness = readiness(sources: .discovered(available: 4, selected: 0, droppedSelections: []))
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.prerequisite == .captureSource)
    }

    @Test("A remembered application that has gone blocks the start rather than being treated as valid")
    func rememberedSourceGone() {
        let readiness = readiness(sources: .discovered(available: 2, selected: 0, droppedSelections: ["Meet"]))
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.prerequisite == .captureSource)
        #expect(readiness.blocker?.detail.contains("Meet") == true)
    }

    @Test("A dropped selection beside a surviving one is worth saying but does not block")
    func partiallyDroppedSelection() {
        let readiness = readiness(sources: .discovered(available: 2, selected: 1, droppedSelections: ["Meet"]))
        #expect(readiness.canStart)
        #expect(row(.captureSource, in: readiness)?.status == .advisory)
    }

    @Test("An uninstalled speech model blocks the start and keeps its own explanation")
    func modelNotInstalled() {
        let availability = SpeechRecognitionAvailability.modelNotInstalled(localeIdentifier: "fr-FR")
        let readiness = readiness(speech: availability)
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.prerequisite == .speechRecognition)
        #expect(readiness.blocker?.detail == availability.message)
    }

    @Test("A Mac that cannot run the recogniser is explained rather than shown as no languages")
    func speechUnsupported() {
        let readiness = readiness(speech: .unsupportedSystem)
        #expect(readiness.blocker?.prerequisite == .speechRecognition)
        #expect(readiness.blocker?.detail.isEmpty == false)
    }

    @Test("Availability that could not be determined is reported, not passed off as ready")
    func speechFailed() {
        let readiness = readiness(speech: .failed(message: "the recogniser did not answer"))
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.detail.contains("the recogniser did not answer") == true)
    }

    @Test("Nothing is claimed while discovery and availability are still being checked")
    func stillChecking() {
        let readiness = readiness(sources: .notAttempted, speech: .unknown)
        #expect(!readiness.canStart)
        #expect(row(.captureAccess, in: readiness)?.status == .checking)
        #expect(row(.speechRecognition, in: readiness)?.status == .checking)
        #expect(readiness.blocker?.prerequisite == .captureAccess)
    }

    @Test("A running meeting is why a start is not offered, ahead of any prerequisite")
    func meetingAlreadyRunning() {
        let readiness = readiness(meetingIsActive: true)
        #expect(!readiness.canStart)
        #expect(readiness.blocker == nil)
        #expect(readiness.startExplanation == "A meeting is already running.")
    }

    @Test("The save location is the first thing asked for when several are missing")
    func blockingPriority() {
        let readiness = readiness(
            saveLocation: .notChosen,
            sources: .accessUnavailable(message: "Grant it in System Settings."),
            speech: .unsupportedSystem
        )
        #expect(readiness.blocker?.prerequisite == .saveLocation)
        #expect(readiness.rows.filter { $0.status == .blocked }.count == 4)
    }

    @Test("Correcting each blocking state in turn ends in a startable meeting")
    func correctingEachBlockerInTurn() {
        var current = readiness(
            saveLocation: .notChosen,
            sources: .notAttempted,
            speech: .unknown
        )
        #expect(current.blocker?.prerequisite == .saveLocation)

        current = readiness(sources: .accessUnavailable(message: "Grant it."), speech: .unknown)
        #expect(current.blocker?.prerequisite == .captureAccess)

        current = readiness(
            sources: .discovered(available: 2, selected: 0, droppedSelections: []),
            speech: .modelNotInstalled(localeIdentifier: "en-US")
        )
        #expect(current.blocker?.prerequisite == .speechRecognition)

        current = readiness(sources: .discovered(available: 2, selected: 0, droppedSelections: []))
        #expect(current.blocker?.prerequisite == .captureSource)

        current = readiness()
        #expect(current.canStart)
    }

    @Test("A failure leaves nothing behind once the state it came from is healthy")
    func failuresDoNotOutlastTheirCause() {
        let failed = readiness(
            saveLocation: .unusable(message: "The saved folder could not be found."),
            sources: .accessUnavailable(message: "Grant it in System Settings."),
            speech: .modelNotInstalled(localeIdentifier: "en-US")
        )
        #expect(!failed.canStart)

        let healthy = readiness()
        #expect(healthy.canStart)
        #expect(healthy.rows.allSatisfy { $0.detail != failed.blocker?.detail })
    }

    @Test("Every row names its status in words, so nothing is carried by colour alone")
    func statusIsSpokenNotOnlyShown() {
        let readiness = readiness(saveLocation: .notChosen, sources: .noApplicationsFound)
        for row in readiness.rows {
            #expect(!row.status.label.isEmpty)
            #expect(!row.status.symbolName.isEmpty)
            #expect(row.accessibilityDescription.contains(row.prerequisite.title))
            #expect(row.accessibilityDescription.contains(row.status.label))
        }
    }
}
