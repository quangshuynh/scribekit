//
//  SecurityScopedLeaseTests.swift
//  ScribeKitTests
//

import Foundation
import Synchronization
import Testing
@testable import ScribeKit

/// Records the start and stop calls macOS balances, and can refuse access, so
/// lease lifetimes are testable without the sandbox.
nonisolated final class FakeSecurityScopedAccess: SecurityScopedResourceAccessing {
    private struct State {
        var started: [URL] = []
        var stopped: [URL] = []
        var isGranted = true
    }

    private let state = Mutex(State())

    /// Creates an accessor that grants access.
    ///
    /// - Parameter isGranted: Whether ``startAccess(to:)`` succeeds.
    init(isGranted: Bool = true) {
        state.withLock { $0.isGranted = isGranted }
    }

    /// The directories access was started for, in order.
    var started: [URL] { state.withLock { $0.started } }

    /// The directories access was stopped for, in order.
    var stopped: [URL] { state.withLock { $0.stopped } }

    /// Whether every start has been balanced by a stop.
    var isBalanced: Bool { state.withLock { $0.started.count == $0.stopped.count } }

    func startAccess(to url: URL) -> Bool {
        state.withLock { state in
            guard state.isGranted else { return false }
            state.started.append(url)
            return true
        }
    }

    func stopAccess(to url: URL) {
        state.withLock { $0.stopped.append(url) }
    }
}

@Suite("SecurityScopedLease")
struct SecurityScopedLeaseTests {

    private let folder = URL(filePath: "/Users/example/Meetings", directoryHint: .isDirectory)

    @Test("A lease holds access open until it is released")
    func leaseSpansItsOwnLifetime() throws {
        let access = FakeSecurityScopedAccess()

        let lease = try SecurityScopedLease.acquire(folder, using: access)

        #expect(access.started == [folder])
        #expect(access.stopped.isEmpty)

        lease.release()

        #expect(access.stopped == [folder])
        #expect(access.isBalanced)
    }

    @Test("Releasing twice does not unbalance the system's reference count")
    func releaseIsIdempotent() throws {
        let access = FakeSecurityScopedAccess()
        let lease = try SecurityScopedLease.acquire(folder, using: access)

        lease.release()
        lease.release()
        lease.release()

        #expect(access.stopped == [folder])
    }

    @Test("Refused access is reported rather than treated as a lease")
    func refusedAccessThrows() {
        let access = FakeSecurityScopedAccess(isGranted: false)

        #expect(throws: SaveLocationError.self) {
            _ = try SecurityScopedLease.acquire(folder, using: access)
        }
        #expect(access.started.isEmpty)
        #expect(access.stopped.isEmpty)
    }

    @Test("Scoped work releases access even when the work throws")
    func withAccessAlwaysReleases() {
        let access = FakeSecurityScopedAccess()

        #expect(throws: (any Error).self) {
            try SecurityScopedAccess.withAccess(to: folder, using: access) { _ in
                throw SaveLocationError(.directoryUnavailable)
            }
        }
        #expect(access.isBalanced)
    }
}
