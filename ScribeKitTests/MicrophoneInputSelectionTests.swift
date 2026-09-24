//
//  MicrophoneInputSelectionTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// In-memory setup preferences, so a remembered microphone can be tested
/// without touching the user's own preference store.
private nonisolated final class MemoryPreferences: MeetingSetupPreferencesStoring, @unchecked Sendable {
    var audioRetention: AudioRetentionMode = .none
    var rememberedSourceIDs: [String] = []
    var captureMode: CaptureMode = .microphone
    var microphoneSelection: MicrophoneSelection = .systemDefault

    init(selection: MicrophoneSelection = .systemDefault) {
        microphoneSelection = selection
    }
}

private let builtIn = FakeMicrophoneAccess.builtIn
private let headset = MicrophoneInput(id: "BluetoothHeadset-UID", name: "AirPods Pro")
private let usb = MicrophoneInput(id: "AppleUSBAudioEngine:Studio:1", name: "Studio Mic")

/// Which inputs the Mac offers and what a selection resolves to — pure, with
/// no Core Audio behind it.
@Suite("Microphone input choice")
struct MicrophoneInputChoiceTests {

    private let catalog = MicrophoneInputCatalog(devices: [usb, headset, builtIn], defaultInputID: headset.id)

    @Test("The catalog lists inputs by name, whatever order Core Audio gave them in, and finds the default")
    func catalogOrderingAndDefault() {
        #expect(catalog.devices.map(\.name) == ["AirPods Pro", "MacBook Pro Microphone", "Studio Mic"])
        #expect(catalog.defaultInput == headset)
        #expect(catalog.input(id: usb.id) == usb)
        #expect(catalog.input(id: "Gone") == nil)

        let twins = MicrophoneInputCatalog(
            devices: [MicrophoneInput(id: "b", name: "USB Mic"), MicrophoneInput(id: "a", name: "USB Mic")],
            defaultInputID: nil
        )
        #expect(twins.devices.map(\.id) == ["a", "b"], "two devices with one name still have one order")
        #expect(twins.defaultInput == nil)
    }

    @Test("A default the list does not contain is no default")
    func defaultMustBeUsable() {
        let stale = MicrophoneInputCatalog(devices: [builtIn], defaultInputID: "Hidden-Aggregate")
        #expect(stale.defaultInput == nil)
        #expect(MicrophoneChoice.resolve(.systemDefault, in: stale).input == nil)
    }

    @Test("System Default resolves to the Mac's default input, and names no device of its own")
    func systemDefaultResolves() {
        let choice = MicrophoneChoice.resolve(.systemDefault, in: catalog)
        #expect(choice.input == headset)
        #expect(choice.usesSystemDefault)
        #expect(choice.unavailableSelection == nil)
    }

    @Test("A chosen device is used even when it is not the Mac's default")
    func explicitDeviceIsUsed() {
        let choice = MicrophoneChoice.resolve(.device(usb), in: catalog)
        #expect(choice.input == usb)
        #expect(!choice.usesSystemDefault)
        #expect(choice.unavailableSelection == nil)
    }

    @Test("A chosen device that is not connected falls back to the default, and the fallback is stated")
    func absentDeviceFallsBackVisibly() {
        let gone = MicrophoneInput(id: "Unplugged-UID", name: "Podcast Mic")
        let choice = MicrophoneChoice.resolve(.device(gone), in: catalog)
        #expect(choice.input == headset)
        #expect(choice.unavailableSelection == gone)
        #expect(choice.usesSystemDefault)
        #expect(choice.selection == .device(gone), "the user's choice itself is not rewritten")

        let empty = MicrophoneChoice.resolve(.device(gone), in: .empty)
        #expect(empty.input == nil)
        #expect(empty.unavailableSelection == gone)
    }

    @Test("A picker tag names a device by its identity, so a renamed device is the same row")
    func pickerTagIgnoresName() {
        let renamed = MicrophoneSelection.device(id: usb.id, name: "Desk Mic")
        #expect(renamed.pickerID == MicrophoneSelection.device(usb).pickerID)
        #expect(MicrophoneSelection.systemDefault.pickerID != MicrophoneSelection.device(usb).pickerID)
    }
}

/// The remembered choice, in the real preference store backed by an isolated
/// suite.
@Suite("Microphone preference")
struct MicrophonePreferenceTests {

    private func isolatedDefaults() throws -> UserDefaults {
        let name = "com.scribekit.tests.microphone.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("Nothing stored means System Default, as before there was a choice")
    func defaultsToSystemDefault() throws {
        let preferences = UserDefaultsMeetingSetupPreferences(defaults: try isolatedDefaults())
        #expect(preferences.microphoneSelection == .systemDefault)
    }

    @Test("A chosen device is remembered by identity and name across a new store, and cleared by System Default")
    func roundTrips() throws {
        let defaults = try isolatedDefaults()
        UserDefaultsMeetingSetupPreferences(defaults: defaults).microphoneSelection = .device(usb)
        #expect(UserDefaultsMeetingSetupPreferences(defaults: defaults).microphoneSelection == .device(usb))

        UserDefaultsMeetingSetupPreferences(defaults: defaults).microphoneSelection = .systemDefault
        #expect(UserDefaultsMeetingSetupPreferences(defaults: defaults).microphoneSelection == .systemDefault)
        #expect(defaults.dictionaryRepresentation().keys.allSatisfy { !$0.contains("microphoneDevice") },
                "System Default leaves no device behind")
    }

    @Test("An empty stored identity is not a device")
    func emptyIdentityIsSystemDefault() throws {
        let defaults = try isolatedDefaults()
        defaults.set("", forKey: "com.scribekit.meetingSetup.microphoneDeviceID")
        #expect(UserDefaultsMeetingSetupPreferences(defaults: defaults).microphoneSelection == .systemDefault)
    }
}

/// The setup screen's microphone state with a choice of inputs.
@MainActor
@Suite("Microphone input selection on the setup screen")
struct MeetingSetupMicrophoneSelectionTests {

    private func threeInputs(
        authorization: MicrophoneAuthorization = .authorized,
        default defaultInput: MicrophoneInput = builtIn
    ) -> FakeMicrophoneAccess {
        FakeMicrophoneAccess(authorization: authorization, devices: [builtIn, headset, usb], defaultInput: defaultInput)
    }

    @Test("Creating the model reads the remembered choice and asks macOS nothing")
    func creationIsInert() {
        let access = threeInputs()
        let model = MeetingSetupMicrophoneModel(access: access, preferences: MemoryPreferences(selection: .device(usb)))
        #expect(model.selection == .device(usb))
        #expect(model.readiness == .notChecked)
        #expect(!access.wasConsulted, "an App Audio screen that never shows the section never reaches Core Audio")
    }

    @Test("Refreshing lists every input and resolves System Default to the Mac's default, without prompting")
    func refreshListsInputs() {
        let access = threeInputs(authorization: .notDetermined, default: headset)
        let model = MeetingSetupMicrophoneModel(access: access, preferences: MemoryPreferences())
        model.refresh()
        #expect(model.catalog.devices.count == 3)
        #expect(model.input == headset)
        #expect(model.source == .microphone(headset))
        #expect(model.choice?.usesSystemDefault == true)
        #expect(access.requests == 0)
    }

    @Test("Choosing a device uses it, remembers it, and makes it the source a meeting starts with")
    func selectingPersists() {
        let preferences = MemoryPreferences()
        let model = MeetingSetupMicrophoneModel(access: threeInputs(), preferences: preferences)
        model.refresh()
        model.select(.device(usb))

        #expect(model.input == usb)
        #expect(preferences.microphoneSelection == .device(usb))
        #expect(model.source?.id == usb.id, "the meeting is set up for the device, not for whatever is default")
        #expect(model.source?.kind == .microphone)

        model.select(.systemDefault)
        #expect(model.input == builtIn)
        #expect(preferences.microphoneSelection == .systemDefault)
    }

    @Test("A remembered device that is absent at launch falls back visibly and stays remembered")
    func absentAtLaunch() {
        let access = FakeMicrophoneAccess(authorization: .authorized, devices: [builtIn], defaultInput: builtIn)
        let preferences = MemoryPreferences(selection: .device(headset))
        let model = MeetingSetupMicrophoneModel(access: access, preferences: preferences)
        model.refresh()

        #expect(model.input == builtIn)
        #expect(model.choice?.unavailableSelection == headset)
        #expect(preferences.microphoneSelection == .device(headset), "unplugged is not the same as unchosen")
    }

    @Test("The device leaving before a start is noticed from the hardware event, and coming back restores it")
    func disappearsAndReconnectsBeforeStart() async {
        let access = threeInputs()
        let model = MeetingSetupMicrophoneModel(access: access, preferences: MemoryPreferences())
        model.refresh()
        model.select(.device(headset))
        #expect(model.input == headset)

        let observing = Task { await model.observeInputChanges() }
        defer { observing.cancel() }
        #expect(await wait { access.inputObserverCount == 1 })

        access.setInputs([builtIn, usb], defaultInput: builtIn)
        access.announceInputChange()
        #expect(await wait { model.choice?.unavailableSelection == headset })
        #expect(model.input == builtIn)
        #expect(model.source?.id == builtIn.id, "a start now uses the default the screen is showing")

        access.setInputs([builtIn, usb, headset], defaultInput: builtIn)
        access.announceInputChange()
        #expect(await wait { model.input == headset })
        #expect(model.choice?.unavailableSelection == nil)

        access.finishInputChanges()
        await observing.value
    }

    @Test("A new default is followed by System Default and ignored by a chosen device")
    func defaultChangeBeforeStart() async {
        let access = threeInputs()
        let preferences = MemoryPreferences()
        let model = MeetingSetupMicrophoneModel(access: access, preferences: preferences)
        model.refresh()
        #expect(model.input == builtIn)

        access.setInputs([builtIn, headset, usb], defaultInput: usb)
        model.refresh()
        #expect(model.input == usb, "System Default is whatever the Mac is set to when the meeting starts")

        model.select(.device(headset))
        access.setInputs([builtIn, headset, usb], defaultInput: builtIn)
        model.refresh()
        #expect(model.input == headset)
    }

    @Test("Choosing a device before access is granted still asks nothing, and asking keeps the choice")
    func selectionAndPermission() async {
        let access = threeInputs(authorization: .notDetermined)
        let model = MeetingSetupMicrophoneModel(access: access, preferences: MemoryPreferences())
        model.refresh()
        model.select(.device(usb))
        #expect(access.requests == 0)

        await model.requestAccess()
        #expect(access.requests == 1)
        #expect(model.authorization == .authorized)
        #expect(model.input == usb)
    }
}

/// What the readiness rows say about the chosen input.
@Suite("Microphone input readiness")
struct MicrophoneInputReadinessTests {

    private func inputRow(_ choice: MicrophoneChoice) -> MeetingStartReadiness.Row? {
        MeetingStartReadiness(
            saveLocation: .ready(path: "/Users/example/Meetings"),
            microphone: .checked(authorization: .authorized, choice: choice),
            speech: .available(localeIdentifier: "en-US"),
            meetingIsActive: false
        ).rows.first { $0.prerequisite == .captureSource }
    }

    @Test("System Default names the device it stands for")
    func systemDefaultRow() {
        let row = inputRow(MicrophoneChoice(selection: .systemDefault, input: builtIn))
        #expect(row?.status == .satisfied)
        #expect(row?.detail.contains("MacBook Pro Microphone, the Mac's default input") == true)
    }

    @Test("A chosen device says the Mac's own setting is unchanged")
    func explicitRow() {
        let row = inputRow(MicrophoneChoice(selection: .device(usb), input: usb))
        #expect(row?.status == .satisfied)
        #expect(row?.detail.contains("Studio Mic, chosen in ScribeKit") == true)
        #expect(row?.detail.contains("unchanged") == true)
    }

    @Test("A fallback is advisory and names both devices, so Start still works and nothing is silent")
    func fallbackRow() {
        let row = inputRow(MicrophoneChoice(selection: .device(headset), input: builtIn, unavailableSelection: headset))
        #expect(row?.status == .advisory)
        #expect(row?.detail.contains("AirPods Pro is not connected") == true)
        #expect(row?.detail.contains("System Default: MacBook Pro Microphone") == true)
    }

    @Test("A fallback with nothing to fall back to blocks, naming the device that is missing")
    func fallbackWithNoInputBlocks() {
        let row = inputRow(MicrophoneChoice(selection: .device(headset), input: nil, unavailableSelection: headset))
        #expect(row?.status == .blocked)
        #expect(row?.detail.contains("AirPods Pro is not connected") == true)
    }
}

/// What a change to the audio system means for a running Microphone meeting,
/// judged from what the system reports rather than from which notification
/// arrived.
@Suite("Microphone route assessment")
struct MicrophoneRouteAssessmentTests {

    private let format = MicrophoneStreamFormat(sampleRate: 48_000, channelCount: 1)

    /// A meeting that started on the built-in microphone while it was the
    /// Mac's default.
    private var baseline: MicrophoneRouteBaseline {
        MicrophoneRouteBaseline(inputID: builtIn.id, format: format, defaultInputID: builtIn.id)
    }

    /// What the system reports, starting from "nothing about the input
    /// changed".
    private func observation(
        present: Bool = true,
        listening: String? = builtIn.id,
        format: MicrophoneStreamFormat? = MicrophoneStreamFormat(sampleRate: 48_000, channelCount: 1),
        running: Bool = true,
        defaultInput: String? = builtIn.id
    ) -> MicrophoneRouteObservation {
        MicrophoneRouteObservation(
            inputIsPresent: present,
            listeningInputID: listening,
            format: format,
            engineIsRunning: running,
            defaultInputID: defaultInput
        )
    }

    @Test("Headphones plugged in or out — an output-only change — leaves the meeting listening")
    func outputOnlyChangeIsHarmless() {
        #expect(MicrophoneRouteAssessment.assess(observation(), against: baseline) == .unaffected(.unrelated))
    }

    @Test("The Mac's default input moving to another device neither ends nor switches the meeting")
    func defaultChangeIsHarmless() {
        let moved = observation(defaultInput: headset.id)
        #expect(MicrophoneRouteAssessment.assess(moved, against: baseline) == .unaffected(.systemDefaultChanged))

        let noDefault = observation(defaultInput: nil)
        #expect(MicrophoneRouteAssessment.assess(noDefault, against: baseline) == .unaffected(.systemDefaultChanged))
    }

    @Test("The meeting's microphone disappearing ends it, even while the engine still claims to run")
    func disconnectedIsLost() {
        let gone = observation(present: false, listening: headset.id, running: true, defaultInput: headset.id)
        #expect(MicrophoneRouteAssessment.assess(gone, against: baseline) == .lost(.inputDisconnected))
    }

    @Test("The unit listening to another device ends the meeting rather than transcribe the wrong microphone")
    func reroutedIsLost() {
        let rerouted = observation(listening: headset.id, defaultInput: headset.id)
        #expect(MicrophoneRouteAssessment.assess(rerouted, against: baseline) == .lost(.inputChanged))
        let unreadable = observation(listening: nil)
        #expect(MicrophoneRouteAssessment.assess(unreadable, against: baseline) == .lost(.inputChanged),
                "a device that cannot be confirmed is not assumed to be the right one")
    }

    @Test("A new sample rate or channel count on the same device ends the meeting")
    func formatChangeIsLost() {
        let rate = observation(format: MicrophoneStreamFormat(sampleRate: 44_100, channelCount: 1))
        #expect(MicrophoneRouteAssessment.assess(rate, against: baseline) == .lost(.formatChanged))
        let channels = observation(format: MicrophoneStreamFormat(sampleRate: 48_000, channelCount: 2))
        #expect(MicrophoneRouteAssessment.assess(channels, against: baseline) == .lost(.formatChanged))
        #expect(MicrophoneRouteAssessment.assess(observation(format: nil), against: baseline) == .lost(.formatChanged))
    }

    @Test("An engine that stopped by itself ends the meeting though its device is fine")
    func stoppedEngineIsLost() {
        #expect(MicrophoneRouteAssessment.assess(observation(running: false), against: baseline) == .lost(.engineStopped))
    }

    @Test("A meeting on a chosen, non-default device is judged against that device")
    func explicitDeviceBaseline() {
        let chosen = MicrophoneRouteBaseline(inputID: usb.id, format: format, defaultInputID: builtIn.id)
        let steady = observation(listening: usb.id)
        #expect(MicrophoneRouteAssessment.assess(steady, against: chosen) == .unaffected(.unrelated))
        let followedDefault = observation(listening: builtIn.id)
        #expect(MicrophoneRouteAssessment.assess(followedDefault, against: chosen) == .lost(.inputChanged))
    }

    @Test("Losing the device is reported first, whatever else changed with it")
    func disconnectionTakesPrecedence() {
        let everything = observation(present: false, listening: nil, format: nil, running: false, defaultInput: nil)
        #expect(MicrophoneRouteAssessment.assess(everything, against: baseline) == .lost(.inputDisconnected))
    }

    @Test("What an interruption says names no device and says ScribeKit did not switch")
    func descriptionsNameNoDevice() {
        let losses: [MicrophoneRouteLoss] = [.inputDisconnected, .inputChanged, .formatChanged, .engineStopped]
        for loss in losses {
            let text = loss.interruptionDescription
            #expect(!text.isEmpty)
            for input in [builtIn, headset, usb] {
                #expect(!text.contains(input.id))
                #expect(!text.contains(input.name))
            }
        }
        #expect(MicrophoneRouteLoss.inputDisconnected.interruptionDescription.contains("rather than switch"))
    }
}

/// The capturer's refusals with a choice of inputs, checked before any engine
/// exists.
@Suite("Microphone capture with a chosen input")
struct MicrophoneChosenInputCaptureTests {

    @Test("Preparing for a connected input that is not the default succeeds without a prompt")
    func preparesForNonDefaultInput() async throws {
        let access = FakeMicrophoneAccess(authorization: .authorized, devices: [builtIn, usb], defaultInput: builtIn)
        let capturer = MicrophoneAudioCapturer(consumer: BroadcastingAudioSampleConsumer([]), access: access)
        try await capturer.prepare(configuration: AudioCaptureConfiguration(sourceIDs: [usb.id], mode: .microphone))
        #expect(access.requests == 0)
    }

    @Test("Preparing for an input that left since the screen showed it is refused, not redirected")
    func refusesDepartedInput() async {
        let access = FakeMicrophoneAccess(authorization: .authorized, devices: [builtIn], defaultInput: builtIn)
        let capturer = MicrophoneAudioCapturer(consumer: BroadcastingAudioSampleConsumer([]), access: access)
        await #expect(throws: AudioCaptureError.microphoneDisconnected) {
            try await capturer.prepare(configuration: AudioCaptureConfiguration(sourceIDs: [usb.id], mode: .microphone))
        }
    }
}

/// Polls a condition on the main actor for a short while.
///
/// - Parameter condition: What to wait for.
/// - Returns: Whether it became true in time.
@MainActor
private func wait(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
