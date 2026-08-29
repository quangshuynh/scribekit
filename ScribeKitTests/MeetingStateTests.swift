//
//  MeetingStateTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("MeetingState")
struct MeetingStateTests {

    @Test("Only completed is terminal")
    func terminalStates() {
        let terminal = MeetingState.allCases.filter(\.isTerminal)
        #expect(terminal == [.completed])
    }

    @Test("Idle and completed hold no capture resources")
    func activeStates() {
        let inactive = MeetingState.allCases.filter { !$0.isActive }
        #expect(Set(inactive) == [.idle, .completed])
    }

    @Test("A state cannot transition to itself")
    func selfTransitionsAreRejected() {
        for state in MeetingState.allCases {
            #expect(!state.canTransition(to: state))
        }
    }

    @Test("Every active state can reach completion")
    func activeStatesCanBeStopped() {
        for state in MeetingState.allCases where state.isActive && state != .stopping {
            #expect(state.canTransition(to: .stopping))
        }
        #expect(MeetingState.stopping.canTransition(to: .completed))
    }

    @Test("Pausing is only possible while transcribing")
    func pauseIsRestricted() {
        let pausable = MeetingState.allCases.filter { $0.canTransition(to: .paused) }
        #expect(pausable == [.transcribing])
        #expect(MeetingState.paused.canTransition(to: .transcribing))
    }

    @Test("Completed sessions cannot be restarted")
    func completedIsFinal() {
        for state in MeetingState.allCases {
            #expect(!MeetingState.completed.canTransition(to: state))
        }
    }
}
