//
//  AccessibilitySemanticsTests.swift
//  ScribeKitTests
//

import Foundation
import SwiftUI
import Testing
@testable import ScribeKit

/// What assistive technology is told about ScribeKit's custom presentation.
///
/// The screens compose rows out of an icon, a status word, a detail sentence
/// and sometimes a control, and a row like that is published to the
/// accessibility tree as one leaf carrying one string. These tests are over
/// that string: that it names the thing, states its state in words rather than
/// leaving it to the icon, and carries the detail the row shows.
@Suite("Accessibility semantics")
@MainActor
struct AccessibilitySemanticsTests {

    // MARK: - Readiness rows

    /// A readiness value with everything satisfied unless a test says
    /// otherwise.
    private func readiness(
        saveLocation: SaveLocationReadiness = .ready(path: "/Users/example/Meetings"),
        sources: CaptureSourceReadiness = .discovered(available: 3, selected: 1, droppedSelections: []),
        speech: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")
    ) -> MeetingStartReadiness {
        MeetingStartReadiness(
            saveLocation: saveLocation,
            captureSources: sources,
            speech: speech,
            meetingIsActive: false
        )
    }

    @Test("A readiness row names the prerequisite, its status and its detail")
    func readinessRowIsSelfContained() {
        let rows = readiness().rows
        for row in rows {
            #expect(row.accessibilityDescription.hasPrefix(row.prerequisite.title))
            #expect(row.accessibilityDescription.contains(row.status.label))
            #expect(row.accessibilityDescription.contains(row.detail))
            #expect(row.accessibilityValue == "\(row.status.label). \(row.detail)")
        }
    }

    @Test("A blocked row states that action is needed in words")
    func blockedRowSaysSo() throws {
        let readiness = readiness(saveLocation: .notChosen)
        let row = try #require(readiness.rows.first { $0.prerequisite == .saveLocation })
        #expect(row.status == .blocked)
        #expect(row.accessibilityDescription.contains("Action needed"))
        #expect(row.accessibilityDescription.contains("Save location"))
    }

    @Test("Every status is named rather than shown only as a symbol")
    func everyStatusHasAWord() {
        let statuses: [MeetingStartReadiness.Status] = [.satisfied, .checking, .advisory, .blocked]
        let labels = statuses.map(\.label)
        #expect(labels.allSatisfy { !$0.isEmpty })
        #expect(Set(labels).count == statuses.count)
        #expect(Set(statuses.map(\.symbolName)).count == statuses.count)
    }

    // MARK: - Review candidates

    /// A flagged passage.
    ///
    /// - Parameters:
    ///   - confidence: The recogniser's confidence, when it reported one.
    ///   - reasons: Why the span was put forward.
    /// - Returns: The candidate.
    private func candidate(
        confidence: Double? = 0.2,
        reasons: [TranscriptReviewReason] = [.lowConfidence]
    ) -> TranscriptReviewCandidate {
        TranscriptReviewCandidate(
            spanIndex: 4,
            startTime: 61,
            endTime: 65,
            confidence: confidence,
            reasons: reasons
        )
    }

    @Test("A flagged passage states its time, priority, reviewed state and words")
    func candidateIsSelfContained() {
        let description = candidate().accessibilityDescription(
            timestamp: "10:31:05 AM",
            text: "the quarterly number",
            isReviewed: false,
            hasAudio: true
        )
        #expect(description.contains("10:31:05 AM"))
        #expect(description.contains("High priority"))
        #expect(description.contains("Needs review."))
        #expect(description.contains("the quarterly number"))
        #expect(description.contains("Recognition confidence was low."))
        #expect(description.contains("Audio is available"))
    }

    @Test("A reviewed passage says so rather than relying on the control beside it")
    func reviewedCandidateSaysSo() {
        let description = candidate().accessibilityDescription(
            timestamp: "10:31:05 AM",
            text: "the quarterly number",
            isReviewed: true,
            hasAudio: true
        )
        #expect(description.contains("Reviewed."))
        #expect(!description.contains("Needs review."))
    }

    @Test("A meeting that kept no recording says why there is nothing to play")
    func candidateWithoutAudioSaysSo() {
        let description = candidate().accessibilityDescription(
            timestamp: "10:31:05 AM",
            text: "the quarterly number",
            isReviewed: false,
            hasAudio: false
        )
        #expect(description.contains("no recording"))
        #expect(!description.contains("Audio is available"))
    }

    @Test("Every reason a passage was flagged is stated")
    func everyReasonIsStated() {
        let both = candidate(reasons: [.lowConfidence, .nearInterruption])
        let description = both.accessibilityDescription(
            timestamp: "10:31:05 AM",
            text: "the quarterly number",
            isReviewed: false,
            hasAudio: false
        )
        for reason in both.reasons {
            #expect(description.contains(reason.explanation))
        }
    }

    // MARK: - Menu command enablement

    /// What the menus say about a meeting in one status.
    private func presentation(
        _ status: MeetingRuntimeStatus,
        canStop: Bool = false,
        canPause: Bool = false,
        canResume: Bool = false
    ) -> MeetingMenuBarPresentation {
        MeetingMenuBarPresentation(
            status: status,
            meeting: nil,
            transcript: nil,
            audio: nil,
            canStop: canStop,
            canPause: canPause,
            canResume: canResume,
            outcome: nil
        )
    }

    @Test("With no meeting the Meeting menu offers nothing")
    func idleMenuOffersNothing() {
        let menu = presentation(.idle)
        #expect(!menu.canPause)
        #expect(!menu.canResume)
        #expect(!menu.canStop)
        #expect(menu.transcriptURL == nil)
        #expect(menu.audioURL == nil)
    }

    @Test("A running meeting can be paused and stopped but not resumed")
    func runningMenuOffersPauseAndStop() {
        let menu = presentation(.transcribing, canStop: true, canPause: true)
        #expect(menu.canPause)
        #expect(!menu.canResume)
        #expect(menu.canStop)
    }

    @Test("A paused meeting can be resumed and stopped but not paused again")
    func pausedMenuOffersResumeAndStop() {
        let menu = presentation(.transcribing, canStop: true, canResume: true)
        #expect(!menu.canPause)
        #expect(menu.canResume)
        #expect(menu.canStop)
    }

    // MARK: - Keyboard routes into the window

    @Test("Asking for the History search field changes every time it is asked")
    func searchFocusCounts() {
        let focus = HistorySearchFocus()
        #expect(focus.requestCount == 0)
        focus.request()
        focus.request()
        #expect(focus.requestCount == 2)
    }

    @Test("A search request identifies the screen offering it")
    func searchFocusIdentity() {
        let focus = HistorySearchFocus()
        #expect(focus == focus)
        #expect(focus != HistorySearchFocus())
    }

    @Test("Each screen has a name, a symbol and its own number key")
    func tabsAreNamedAndReachable() {
        let tabs = ScribeKitTab.allCases
        #expect(tabs == [.meeting, .history])
        #expect(Set(tabs.map(\.title)).count == tabs.count)
        #expect(Set(tabs.map(\.systemImage)).count == tabs.count)
        #expect(Set(tabs.map { "\($0.shortcut.character)" }).count == tabs.count)
        #expect(tabs.allSatisfy { !$0.title.isEmpty })
    }

    @Test("The window opens on the meeting and the menu can move it")
    func tabSelectionStartsOnMeeting() {
        let selection = ScribeKitTabSelection()
        #expect(selection.tab == .meeting)
        selection.tab = .history
        #expect(selection.tab == .history)
        #expect(selection != ScribeKitTabSelection())
    }
}
