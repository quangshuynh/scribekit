//
//  MeetingSetupPreferences.swift
//  ScribeKit
//

import Foundation

/// Remembers the meeting-setup choices that are worth carrying between
/// launches.
///
/// Only settled preferences belong here. Runtime state — what discovery just
/// returned, whether it failed, which applications happen to be running, what
/// a meeting is currently doing — is deliberately excluded: it describes this
/// launch, not the user's intent.
///
/// The meeting title is not remembered either. It names one meeting, and
/// silently reusing it would misname the next one.
nonisolated protocol MeetingSetupPreferencesStoring: AnyObject {
    /// The audio retention mode the user last chose.
    var audioRetention: AudioRetentionMode { get set }

    /// Bundle identifiers of the applications the user last selected.
    ///
    /// These are preferences, not live sources. An identifier here says the
    /// user wants that application captured when it is available; it makes no
    /// claim that the application is running, and it is never a process
    /// identifier, which would not survive a relaunch.
    var rememberedSourceIDs: [String] { get set }
}

/// Meeting-setup preferences backed by the local preference store.
nonisolated final class UserDefaultsMeetingSetupPreferences: MeetingSetupPreferencesStoring {
    private enum Key {
        static let audioRetention = "com.scribekit.meetingSetup.audioRetention"
        static let rememberedSourceIDs = "com.scribekit.meetingSetup.sourceIDs"
    }

    private let defaults: UserDefaults

    /// Creates a preference store.
    ///
    /// - Parameter defaults: Where preferences are kept. Defaults to the
    ///   standard preferences; tests pass an isolated suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The remembered retention mode, falling back to the default when nothing
    /// valid is stored.
    var audioRetention: AudioRetentionMode {
        get {
            guard let raw = defaults.string(forKey: Key.audioRetention),
                  let mode = AudioRetentionMode(rawValue: raw) else { return .default }
            return mode
        }
        set { defaults.set(newValue.rawValue, forKey: Key.audioRetention) }
    }

    var rememberedSourceIDs: [String] {
        get { defaults.stringArray(forKey: Key.rememberedSourceIDs) ?? [] }
        set { defaults.set(newValue, forKey: Key.rememberedSourceIDs) }
    }
}
