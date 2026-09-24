//
//  MicrophoneAccess.swift
//  ScribeKit
//

import Foundation

/// What macOS says about ScribeKit's access to the microphone.
///
/// The cases are the operating system's own and nothing more: ScribeKit does
/// not keep a permission state of its own beside the one macOS holds, so there
/// is nothing here that could disagree with System Settings. Each answer is a
/// fact about the moment it was read.
nonisolated enum MicrophoneAuthorization: Equatable, Sendable {
    /// ScribeKit has never asked. macOS asks the user the first time a
    /// Microphone meeting starts.
    case notDetermined

    /// The user allowed ScribeKit to use the microphone.
    case authorized

    /// The user refused, or later turned access off. Only System Settings can
    /// change this; macOS will not ask again.
    case denied

    /// Access is restricted on this Mac, for example by a device-management
    /// profile, and neither ScribeKit nor the user can grant it from here.
    case restricted
}

/// One sound input device the Mac offers.
nonisolated struct MicrophoneInput: Identifiable, Hashable, Sendable {
    /// The device's Core Audio UID.
    ///
    /// Apple documents the UID as persistent across boots on one Mac and not
    /// meaningful on another, so it is kept in this Mac's own preferences to
    /// remember an explicit choice and nowhere else: not in `session.json`,
    /// not in the transcript and not in diagnostics, all of which may travel.
    let id: String

    /// The device's name, as System Settings shows it.
    let name: String
}

/// The sound inputs the Mac offered when it was last asked.
nonisolated struct MicrophoneInputCatalog: Equatable, Sendable {
    /// The usable inputs, ordered by name so the list does not reorder itself
    /// between reads.
    let devices: [MicrophoneInput]

    /// The UID of the Mac's default input, when it has one.
    let defaultInputID: MicrophoneInput.ID?

    /// A catalog with no inputs, for a Mac with none or one not yet read.
    static let empty = MicrophoneInputCatalog(devices: [], defaultInputID: nil)

    /// Creates a catalog.
    ///
    /// - Parameters:
    ///   - devices: The usable inputs, in any order.
    ///   - defaultInputID: The UID of the Mac's default input.
    init(devices: [MicrophoneInput], defaultInputID: MicrophoneInput.ID?) {
        self.devices = devices.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
        self.defaultInputID = defaultInputID
    }

    /// The Mac's default input, when it is one of the usable inputs.
    var defaultInput: MicrophoneInput? {
        defaultInputID.flatMap(input(id:))
    }

    /// The input with a UID, when it is connected.
    ///
    /// - Parameter id: The device's UID.
    /// - Returns: The input, or `nil` when no usable input has that UID.
    func input(id: MicrophoneInput.ID) -> MicrophoneInput? {
        devices.first { $0.id == id }
    }
}

/// Which microphone the user asked the next meeting to listen to.
///
/// A preference, not a device. System Default names no hardware: it means
/// "whichever input the Mac is set to when the meeting starts". A device
/// choice names one input by its UID and keeps the name it had when it was
/// chosen, so a choice whose device is not connected can still be described.
nonisolated enum MicrophoneSelection: Hashable, Sendable {
    /// Use the Mac's default input, read when the meeting starts.
    case systemDefault

    /// Use one input, whatever the Mac's default is.
    ///
    /// - Parameters:
    ///   - id: The device's UID.
    ///   - name: Its name when it was chosen.
    case device(id: MicrophoneInput.ID, name: String)

    /// Chooses one input.
    ///
    /// - Parameter input: The input to use.
    /// - Returns: A selection of exactly that device.
    static func device(_ input: MicrophoneInput) -> MicrophoneSelection {
        .device(id: input.id, name: input.name)
    }

    /// A stable value for a picker to tag this selection with.
    ///
    /// A device is tagged by its UID alone, so a device renamed since it was
    /// chosen is still the same row.
    var pickerID: String {
        switch self {
        case .systemDefault: "system-default"
        case let .device(id, _): "device:\(id)"
        }
    }
}

/// What a selection resolves to, given the inputs the Mac offers now.
///
/// This is where System Default becomes a device and where a remembered
/// device that is not connected is noticed. The fallback is stated rather than
/// taken quietly: ``unavailableSelection`` names the device the user chose,
/// the screen says the next meeting will use the default instead, and the
/// preference itself is left alone so the device is used again once it is
/// connected.
nonisolated struct MicrophoneChoice: Equatable, Sendable {
    /// What the user asked for.
    let selection: MicrophoneSelection

    /// The input a meeting started now would listen to, or `nil` when there
    /// is none.
    let input: MicrophoneInput?

    /// The chosen device, when it is not connected and the default is being
    /// used in its place.
    let unavailableSelection: MicrophoneInput?

    /// Creates a choice.
    ///
    /// - Parameters:
    ///   - selection: What the user asked for.
    ///   - input: The input a meeting would listen to.
    ///   - unavailableSelection: The chosen device, when it is not connected.
    init(selection: MicrophoneSelection, input: MicrophoneInput?, unavailableSelection: MicrophoneInput? = nil) {
        self.selection = selection
        self.input = input
        self.unavailableSelection = unavailableSelection
    }

    /// Resolves a selection against the inputs the Mac offers.
    ///
    /// - Parameters:
    ///   - selection: What the user asked for.
    ///   - catalog: The inputs the Mac offers now.
    /// - Returns: The chosen device when it is connected; otherwise the
    ///   default input, with the absent choice recorded.
    static func resolve(_ selection: MicrophoneSelection, in catalog: MicrophoneInputCatalog) -> MicrophoneChoice {
        switch selection {
        case .systemDefault:
            return MicrophoneChoice(selection: selection, input: catalog.defaultInput)
        case let .device(id, name):
            if let input = catalog.input(id: id) {
                return MicrophoneChoice(selection: selection, input: input)
            }
            return MicrophoneChoice(
                selection: selection,
                input: catalog.defaultInput,
                unavailableSelection: MicrophoneInput(id: id, name: name)
            )
        }
    }

    /// Whether the input is the Mac's default rather than a device the user
    /// picked — because they asked for the default, or because their device
    /// is not connected.
    var usesSystemDefault: Bool {
        selection == .systemDefault || unavailableSelection != nil
    }
}

/// What the setup screen knows about listening to the microphone.
nonisolated enum MicrophoneReadiness: Equatable, Sendable {
    /// Nothing has been read yet.
    case notChecked

    /// What macOS reported when it was last asked.
    ///
    /// - Parameters:
    ///   - authorization: Whether ScribeKit may use the microphone.
    ///   - choice: Which input a meeting would listen to, and why.
    case checked(authorization: MicrophoneAuthorization, choice: MicrophoneChoice)
}
