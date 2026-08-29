//
//  DiscoveredApplication.swift
//  ScribeKit
//

import Foundation

/// A neutral description of one running application reported by a system
/// discovery API.
///
/// System frameworks are adapted into this value at the subsystem boundary so
/// that filtering, mapping and the tests covering them never depend on a
/// capture framework being available or authorised.
struct DiscoveredApplication: Hashable, Sendable {
    /// The application's bundle identifier, empty when the system reports none.
    let bundleIdentifier: String

    /// The application name as reported by the system.
    let applicationName: String

    /// The identifier of the process the system observed.
    ///
    /// A process identifier is reused across launches and is therefore only
    /// used for diagnostics and de-duplication within a single discovery pass,
    /// never as a durable source identity.
    let processIdentifier: pid_t

    /// Whether the application owns at least one ordinary on-screen window.
    ///
    /// This is the only signal the discovery API gives that separates an
    /// application a user recognises from a helper or background process.
    let ownsOnScreenWindow: Bool
}
