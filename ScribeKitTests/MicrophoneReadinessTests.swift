//
//  MicrophoneReadinessTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

/// Whether a Microphone meeting can start, and what the screen says when it
/// cannot — derived from what macOS reports and nothing ScribeKit invents.
@Suite("Microphone readiness")
struct MicrophoneReadinessTests {

    private let input = MicrophoneInput(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")

    private func readiness(
        _ microphone: MicrophoneReadiness,
        saveLocation: SaveLocationReadiness = .ready(path: "/Users/example/Meetings"),
        speech: SpeechRecognitionAvailability = .available(localeIdentifier: "en-US")
    ) -> MeetingStartReadiness {
        MeetingStartReadiness(
            saveLocation: saveLocation,
            microphone: microphone,
            speech: speech,
            meetingIsActive: false
        )
    }

    /// What the setup screen reads when the user left the input on System
    /// Default.
    private func defaultInput(_ authorization: MicrophoneAuthorization, _ input: MicrophoneInput?) -> MicrophoneReadiness {
        .checked(authorization: authorization, choice: MicrophoneChoice(selection: .systemDefault, input: input))
    }

    private func row(
        _ prerequisite: MeetingStartReadiness.Prerequisite,
        in readiness: MeetingStartReadiness
    ) -> MeetingStartReadiness.Row? {
        readiness.rows.first { $0.prerequisite == prerequisite }
    }

    @Test("Granted access and an input allow a start, in the same four rows App Audio uses")
    func readyToStart() {
        let readiness = readiness(defaultInput(.authorized, input))
        #expect(readiness.canStart)
        #expect(readiness.captureMode == .microphone)
        #expect(readiness.rows.map(\.prerequisite) == MeetingStartReadiness.Prerequisite.allCases)
        #expect(readiness.rows.allSatisfy { $0.status == .satisfied })
        #expect(row(.captureAccess, in: readiness)?.title == "Microphone access")
        #expect(row(.captureSource, in: readiness)?.title == "Microphone input")
        #expect(row(.captureSource, in: readiness)?.detail.contains("MacBook Pro Microphone") == true)
        #expect(readiness.startExplanation.contains("No audio is kept"))
    }

    @Test("A Microphone meeting never asks about Screen & System Audio Recording")
    func screenRecordingIsNotAPrerequisite() {
        let readiness = readiness(defaultInput(.authorized, input))
        #expect(!readiness.rows.contains { $0.title == "Screen & System Audio Recording" })
        #expect(!readiness.startExplanation.contains("applications"))
    }

    @Test("A permission macOS has not asked about yet does not block: the start asks")
    func undeterminedIsAdvisory() {
        let readiness = readiness(defaultInput(.notDetermined, input))
        #expect(readiness.canStart)
        #expect(row(.captureAccess, in: readiness)?.status == .advisory)
        #expect(row(.captureAccess, in: readiness)?.detail.contains("asks") == true)
    }

    @Test("A refusal blocks the start and names where it can be changed")
    func deniedBlocksWithRecoveryPath() {
        let readiness = readiness(defaultInput(.denied, input))
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.prerequisite == .captureAccess)
        #expect(readiness.blocker?.detail.contains("System Settings › Privacy & Security › Microphone") == true)
        #expect(readiness.startExplanation.hasPrefix("Microphone access:"))
    }

    @Test("A restricted Mac blocks the start without sending the user to a setting they cannot change")
    func restrictedBlocks() {
        let readiness = readiness(defaultInput(.restricted, input))
        #expect(readiness.blocker?.prerequisite == .captureAccess)
        #expect(readiness.blocker?.detail.contains("restricted") == true)
        #expect(readiness.blocker?.detail.contains("Privacy & Security") == false)
    }

    @Test("No input blocks the start on the input row")
    func noInputBlocks() {
        let readiness = readiness(defaultInput(.authorized, nil))
        #expect(!readiness.canStart)
        #expect(readiness.blocker?.prerequisite == .captureSource)
        #expect(readiness.blocker?.title == "Microphone input")
    }

    @Test("Nothing read yet is checking, which prevents a start without describing a problem")
    func notCheckedIsChecking() {
        let readiness = readiness(.notChecked)
        #expect(!readiness.canStart)
        #expect(row(.captureAccess, in: readiness)?.status == .checking)
        #expect(row(.captureSource, in: readiness)?.status == .checking)
    }

    @Test("The save location still comes first")
    func saveLocationStillFirst() {
        let readiness = readiness(defaultInput(.denied, nil), saveLocation: .notChosen)
        #expect(readiness.blocker?.prerequisite == .saveLocation)
    }

    @Test("App Audio readiness keeps its own titles")
    func applicationTitlesUnchanged() {
        let readiness = MeetingStartReadiness(
            saveLocation: .ready(path: "/Users/example/Meetings"),
            captureSources: .accessUnavailable(message: "Grant access."),
            speech: .available(localeIdentifier: "en-US"),
            meetingIsActive: false
        )
        #expect(readiness.captureMode == .applications)
        #expect(readiness.blocker?.title == "Screen & System Audio Recording")
        #expect(readiness.startExplanation == "Screen & System Audio Recording: Grant access.")
    }
}

/// The decision about whether a Microphone meeting may listen, made against
/// stated answers rather than this Mac's privacy settings.
@Suite("Microphone access gate")
struct MicrophoneAccessGateTests {

    @Test("Granted access passes without asking")
    func authorizedPasses() async throws {
        let access = FakeMicrophoneAccess(authorization: .authorized)
        try await MicrophoneAccessGate.ensureAccess(access, mayPrompt: true)
        #expect(access.requests == 0)
    }

    @Test("An undetermined permission is asked about once, and the answer decides")
    func undeterminedAsks() async throws {
        let granting = FakeMicrophoneAccess(authorization: .notDetermined, answer: true)
        try await MicrophoneAccessGate.ensureAccess(granting, mayPrompt: true)
        #expect(granting.requests == 1)

        let refusing = FakeMicrophoneAccess(authorization: .notDetermined, answer: false)
        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await MicrophoneAccessGate.ensureAccess(refusing, mayPrompt: true)
        }
        #expect(refusing.requests == 1)
    }

    @Test("Where prompting is not allowed, an undetermined permission is refused without asking")
    func noPromptWhenNotAllowed() async {
        let access = FakeMicrophoneAccess(authorization: .notDetermined)
        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await MicrophoneAccessGate.ensureAccess(access, mayPrompt: false)
        }
        #expect(access.requests == 0)
    }

    @Test("A refusal and a restriction are reported as themselves, without a prompt")
    func deniedAndRestricted() async {
        let denied = FakeMicrophoneAccess(authorization: .denied)
        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await MicrophoneAccessGate.ensureAccess(denied, mayPrompt: true)
        }
        let restricted = FakeMicrophoneAccess(authorization: .restricted)
        await #expect(throws: AudioCaptureError.microphoneAccessRestricted) {
            try await MicrophoneAccessGate.ensureAccess(restricted, mayPrompt: true)
        }
        #expect(denied.requests == 0)
        #expect(restricted.requests == 0)
    }

    @Test("The meeting's input must be connected; the Mac's default moving elsewhere does not matter")
    func expectedInput() throws {
        let input = FakeMicrophoneAccess.builtIn
        let studio = MicrophoneInput(id: "AppleUSBAudioEngine:1", name: "Studio Mic")
        let access = FakeMicrophoneAccess(authorization: .authorized, devices: [input, studio], defaultInput: input)
        #expect(try MicrophoneAccessGate.expectedInput(access, matching: ["AppleUSBAudioEngine:1"]) == studio,
                "a connected input that is not the default is still the meeting's input")

        access.setInputs([input], defaultInput: input)
        #expect(throws: AudioCaptureError.microphoneDisconnected) {
            try MicrophoneAccessGate.expectedInput(access, matching: ["AppleUSBAudioEngine:1"])
        }
        access.setInput(nil)
        #expect(throws: AudioCaptureError.microphoneUnavailable) {
            try MicrophoneAccessGate.expectedInput(access, matching: ["BuiltInMicrophoneDevice"])
        }
    }
}

/// The setup screen's microphone state: read without prompting, asked for
/// only when macOS would actually ask.
@MainActor
@Suite("MeetingSetupMicrophoneModel")
struct MeetingSetupMicrophoneModelTests {

    @Test("Refreshing reads the permission and the input and never prompts")
    func refreshNeverPrompts() {
        let access = FakeMicrophoneAccess(authorization: .notDetermined)
        let model = MeetingSetupMicrophoneModel(access: access)
        #expect(model.readiness == .notChecked)
        #expect(!access.wasConsulted, "creating the model asks macOS nothing")

        model.refresh()
        #expect(model.authorization == .notDetermined)
        #expect(model.input?.name == "MacBook Pro Microphone")
        #expect(model.source?.kind == .microphone)
        #expect(model.source?.id == "BuiltInMicrophoneDevice")
        #expect(access.requests == 0)
    }

    @Test("Asking for access prompts once, and only while macOS has never been asked")
    func requestOnlyWhenUndetermined() async {
        let access = FakeMicrophoneAccess(authorization: .notDetermined, answer: true)
        let model = MeetingSetupMicrophoneModel(access: access)
        await model.requestAccess()
        #expect(access.requests == 1)
        #expect(model.authorization == .authorized)

        await model.requestAccess()
        #expect(access.requests == 1, "an answered permission is not asked about again")

        let denied = FakeMicrophoneAccess(authorization: .denied)
        let refused = MeetingSetupMicrophoneModel(access: denied)
        await refused.requestAccess()
        #expect(denied.requests == 0)
        #expect(refused.authorization == .denied)
    }

    @Test("A change made in System Settings is noticed at the next refresh, not before")
    func refreshIsASnapshot() {
        let access = FakeMicrophoneAccess(authorization: .denied)
        let model = MeetingSetupMicrophoneModel(access: access)
        model.refresh()
        access.setAuthorization(.authorized)
        access.setInput(MicrophoneInput(id: "AppleUSBAudioEngine:1", name: "Studio Mic"))
        #expect(model.authorization == .denied)

        model.refresh()
        #expect(model.authorization == .authorized)
        #expect(model.input?.name == "Studio Mic")
    }

    @Test("No input means no source to start from")
    func noInputNoSource() {
        let model = MeetingSetupMicrophoneModel(access: FakeMicrophoneAccess(authorization: .authorized, input: nil))
        model.refresh()
        #expect(model.source == nil)
    }
}

/// The one capturer a runtime talks to, sending each start to the capturer
/// for its mode.
@Suite("Capture mode router")
struct CaptureModeRouterTests {

    private let consumer = BroadcastingAudioSampleConsumer([])

    @Test("Each mode's start reaches its own capturer and no other")
    func routesByMode() async throws {
        let applications = FakeCapturer(consumer: consumer)
        let microphone = FakeCapturer(consumer: consumer)
        let router = CaptureModeRouter(applications: applications, microphone: microphone)

        let mic = AudioCaptureConfiguration(sourceIDs: ["BuiltInMicrophoneDevice"], mode: .microphone)
        try await router.prepare(configuration: mic)
        try await router.start(configuration: mic)
        #expect(microphone.prepareCount == 1)
        #expect(microphone.startCount == 1)
        #expect(applications.prepareCount == 0)
        #expect(applications.startCount == 0)

        await router.stop()
        let apps = AudioCaptureConfiguration(sourceIDs: ["com.example.Meet"])
        try await router.prepare(configuration: apps)
        try await router.start(configuration: apps)
        #expect(applications.startCount == 1)
        #expect(microphone.startCount == 1)
    }

    @Test("A stop reaches both capturers, so a stream that ended by itself leaves nothing stale")
    func stopReachesBoth() async throws {
        let applications = FakeCapturer(consumer: consumer)
        let microphone = FakeCapturer(consumer: consumer)
        let router = CaptureModeRouter(applications: applications, microphone: microphone)
        try await router.start(configuration: AudioCaptureConfiguration(sourceIDs: ["mic"], mode: .microphone))

        microphone.interrupt(.interrupted("gone"))
        try await router.start(configuration: AudioCaptureConfiguration(sourceIDs: ["mic"], mode: .microphone))
        #expect(microphone.startCount == 2, "an interrupted capturer can start again")

        await router.stop()
        #expect(applications.stopCount == 1)
        #expect(microphone.stopCount == 1)
        #expect(!microphone.isCapturing)
    }

    @Test("A refusal from the mode's capturer is the router's refusal")
    func refusalsPassThrough() async {
        let applications = FakeCapturer(consumer: consumer)
        let microphone = FakeCapturer(consumer: consumer)
        microphone.prepareError = .microphoneAccessDenied
        let router = CaptureModeRouter(applications: applications, microphone: microphone)

        await #expect(throws: AudioCaptureError.microphoneAccessDenied) {
            try await router.prepare(configuration: AudioCaptureConfiguration(sourceIDs: ["mic"], mode: .microphone))
        }
        try? await router.prepare(configuration: AudioCaptureConfiguration(sourceIDs: ["com.example.Meet"]))
        #expect(applications.prepareCount == 1)
    }

    @Test("Interruptions from either capturer come out of the router")
    func interruptionsAreForwarded() async {
        let applications = FakeCapturer(consumer: consumer)
        let microphone = FakeCapturer(consumer: consumer)
        let router = CaptureModeRouter(applications: applications, microphone: microphone)

        microphone.interrupt(.interrupted(MicrophoneRouteLoss.inputDisconnected.interruptionDescription))
        var iterator = router.interruptions.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .interrupted(MicrophoneRouteLoss.inputDisconnected.interruptionDescription))

        applications.interrupt(.permissionDenied)
        let second = await iterator.next()
        #expect(second == .permissionDenied)
    }
}
