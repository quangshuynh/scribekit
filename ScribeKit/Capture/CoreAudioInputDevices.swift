//
//  CoreAudioInputDevices.swift
//  ScribeKit
//

import CoreAudio
import Foundation
import Synchronization

/// Reads the Mac's sound input devices from Core Audio.
///
/// This is the only place ScribeKit talks to the audio hardware layer about
/// devices, and every call here is a read: nothing sets the Mac's default
/// input or any other system-wide property. Choosing a microphone in
/// ScribeKit binds one meeting's own audio unit to it and leaves System
/// Settings exactly as it was.
///
/// Nothing here needs microphone permission. Listing devices and naming them
/// is not listening to them.
nonisolated enum CoreAudioInputDevices {

    /// The inputs a meeting could listen to, and the Mac's default input.
    ///
    /// The list is what System Settings › Sound › Input offers: devices with
    /// input streams that are alive and may be chosen as the default input.
    /// Hidden devices — private aggregates other applications create — are not
    /// in Core Audio's device list at all.
    static func catalog() -> MicrophoneInputCatalog {
        let devices = allDevices().compactMap { device -> MicrophoneInput? in
            guard hasInputStreams(device), isAlive(device), canBeDefaultInput(device),
                  let uid = uid(of: device) else { return nil }
            return MicrophoneInput(id: uid, name: name(of: device) ?? "Microphone")
        }
        return MicrophoneInputCatalog(devices: devices, defaultInputID: defaultInputDevice().flatMap(uid(of:)))
    }

    /// The device with a UID, when one is present.
    ///
    /// - Parameter uid: The device's UID.
    /// - Returns: Its object identifier, or `nil` when no device has it.
    static func device(forUID uid: String) -> AudioObjectID? {
        var address = globalAddress(kAudioHardwarePropertyTranslateUIDToDevice)
        var qualifier: CFString = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                pointer,
                &size,
                &device
            )
        }
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// The system's default input device, when there is one.
    static func defaultInputDevice() -> AudioObjectID? {
        var address = globalAddress(kAudioHardwarePropertyDefaultInputDevice)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device
        )
        guard status == noErr, device != AudioObjectID(kAudioObjectUnknown) else { return nil }
        return device
    }

    /// A device's UID.
    ///
    /// - Parameter device: The device.
    /// - Returns: Its UID, or `nil` when it reported none.
    static func uid(of device: AudioObjectID) -> String? {
        string(kAudioDevicePropertyDeviceUID, of: device)
    }

    /// Whether a device is ready and available, rather than about to go away.
    ///
    /// - Parameter device: The device.
    /// - Returns: `false` for a device Core Audio says is unusable, and for one
    ///   it no longer knows.
    static func isAlive(_ device: AudioObjectID) -> Bool {
        var address = globalAddress(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive)
        return status == noErr && alive != 0
    }

    /// Every device Core Audio lists.
    private static func allDevices() -> [AudioObjectID] {
        var address = globalAddress(kAudioHardwarePropertyDevices)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return [] }
        return Array(devices.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    /// Whether a device has at least one input stream.
    ///
    /// - Parameter device: The device.
    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
        return status == noErr && size >= UInt32(MemoryLayout<AudioStreamID>.size)
    }

    /// Whether a device may be chosen as the Mac's default input.
    ///
    /// - Parameter device: The device.
    private static func canBeDefaultInput(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceCanBeDefaultDevice,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        return status == noErr && value != 0
    }

    /// A device's name.
    ///
    /// - Parameter device: The device.
    private static func name(of device: AudioObjectID) -> String? {
        string(kAudioObjectPropertyName, of: device)
    }

    /// Reads one string property of an audio object.
    ///
    /// - Parameters:
    ///   - selector: The property to read.
    ///   - object: The object to read it from.
    /// - Returns: The value, or `nil` when the object did not supply one.
    private static func string(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = globalAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr, let value else { return nil }
        let string = value.takeRetainedValue() as String
        return string.isEmpty ? nil : string
    }

    /// A property address in the global scope of the main element.
    ///
    /// - Parameter selector: The property.
    static func globalAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
    }
}

/// A Core Audio property listener, removed when cancelled or released.
///
/// Core Audio calls the block on the queue it was registered with whenever the
/// property changes. The listener is event-driven — nothing polls — and it
/// holds nothing but the registration, so removing it is the whole of
/// stopping it.
nonisolated final class CoreAudioPropertyListener: Sendable {
    /// Core Audio's listener block, marked as safe to call from its queue.
    private typealias Block = @Sendable (UInt32, UnsafePointer<AudioObjectPropertyAddress>) -> Void

    private let object: AudioObjectID
    private let selector: AudioObjectPropertySelector
    private let queue: DispatchQueue
    private let block: Block
    private let isRegistered: Mutex<Bool>

    /// Starts listening to one property.
    ///
    /// - Parameters:
    ///   - selector: The property, in the global scope of the main element.
    ///   - object: The object that owns it. Defaults to the system object.
    ///   - queue: Where the handler runs.
    ///   - handler: Called after each change.
    /// - Returns: The listener, or `nil` when Core Audio refused the
    ///   registration.
    static func listen(
        to selector: AudioObjectPropertySelector,
        of object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject),
        on queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) -> CoreAudioPropertyListener? {
        let listener = CoreAudioPropertyListener(object: object, selector: selector, queue: queue) { _, _ in
            handler()
        }
        var address = CoreAudioInputDevices.globalAddress(selector)
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, listener.block)
        guard status == noErr else { return nil }
        listener.isRegistered.withLock { $0 = true }
        return listener
    }

    private init(
        object: AudioObjectID,
        selector: AudioObjectPropertySelector,
        queue: DispatchQueue,
        block: @escaping Block
    ) {
        self.object = object
        self.selector = selector
        self.queue = queue
        self.block = block
        isRegistered = Mutex(false)
    }

    deinit {
        cancel()
    }

    /// Stops listening. Calling it again does nothing.
    func cancel() {
        let wasRegistered = isRegistered.withLock { registered in
            defer { registered = false }
            return registered
        }
        guard wasRegistered else { return }
        var address = CoreAudioInputDevices.globalAddress(selector)
        AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
    }
}
