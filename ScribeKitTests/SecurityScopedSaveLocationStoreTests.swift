//
//  SecurityScopedSaveLocationStoreTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

/// Covers the store's handling of what it finds in the preference store.
///
/// Creating and resolving real security-scoped bookmarks needs a folder the
/// user picked in an open panel, which a unit test cannot produce; that thin
/// boundary is exercised by running the app. What is tested here is everything
/// around it: absent, malformed and unresolvable stored data, and removal.
///
/// The tests share one preference domain and therefore run serially.
@Suite("SecurityScopedSaveLocationStore", .serialized)
struct SecurityScopedSaveLocationStoreTests {
    /// Preference domain used by these tests, kept apart from the app's own.
    private static let suiteName = "com.scribekit.tests.saveLocation"

    private let key = "bookmark"

    /// Runs a test against an isolated preference domain.
    ///
    /// - Parameter body: Work to perform with a store and its defaults.
    private func withStore(_ body: (SecurityScopedSaveLocationStore, UserDefaults) throws -> Void) throws {
        let defaults = UserDefaults(suiteName: Self.suiteName)!
        defaults.removePersistentDomain(forName: Self.suiteName)
        defer { defaults.removePersistentDomain(forName: Self.suiteName) }
        try body(SecurityScopedSaveLocationStore(defaults: defaults, key: key), defaults)
    }

    @Test("Nothing stored means no destination, not an error")
    func returnsNilWhenNothingStored() throws {
        try withStore { store, _ in
            let restored = try store.restore()
            #expect(restored == nil)
        }
    }

    @Test("Stored data that is not bookmark data is reported as malformed", arguments: [
        "not bookmark data" as Any, 42 as Any, Data() as Any
    ])
    func reportsMalformedStoredData(value: Any) throws {
        try withStore { store, defaults in
            defaults.set(value, forKey: key)
            let error = #expect(throws: SaveLocationError.self) { try store.restore() }
            #expect(error?.reason == .malformedStoredData)
        }
    }

    @Test("Bookmark data that will not resolve is reported as such, with the system error kept")
    func reportsUnresolvableBookmark() throws {
        try withStore { store, defaults in
            defaults.set(Data([0x01, 0x02, 0x03, 0x04]), forKey: key)
            let error = #expect(throws: SaveLocationError.self) { try store.restore() }
            #expect(error?.reason == .bookmarkResolutionFailed)
            #expect(error?.underlying != nil)
        }
    }

    @Test("Clearing removes the stored destination")
    func clearRemovesStoredData() throws {
        try withStore { store, defaults in
            defaults.set(Data([0x01]), forKey: key)
            try store.clear()
            #expect(defaults.object(forKey: key) == nil)
            let restored = try store.restore()
            #expect(restored == nil)
        }
    }
}
