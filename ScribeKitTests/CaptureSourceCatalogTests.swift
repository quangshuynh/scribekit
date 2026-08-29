//
//  CaptureSourceCatalogTests.swift
//  ScribeKitTests
//

import Foundation
import Testing
@testable import ScribeKit

@Suite("CaptureSourceCatalog")
struct CaptureSourceCatalogTests {

    private func application(
        _ bundleIdentifier: String,
        _ name: String,
        pid: pid_t = 1,
        onScreen: Bool = true
    ) -> DiscoveredApplication {
        DiscoveredApplication(
            bundleIdentifier: bundleIdentifier,
            applicationName: name,
            processIdentifier: pid,
            ownsOnScreenWindow: onScreen
        )
    }

    @Test("Applications with on-screen windows become sources")
    func mapsApplications() {
        let sources = CaptureSourceCatalog.sources(from: [application("com.example.Meet", "Meet")])
        #expect(sources == [.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")])
    }

    @Test("Background processes without on-screen windows are excluded")
    func excludesBackgroundProcesses() {
        let sources = CaptureSourceCatalog.sources(from: [
            application("com.example.Meet", "Meet"),
            application("com.example.Helper", "Meet Helper", pid: 2, onScreen: false)
        ])
        #expect(sources.map(\.id) == ["com.example.Meet"])
    }

    @Test("Entries without a usable identity or name are excluded")
    func excludesUnusableEntries() {
        let sources = CaptureSourceCatalog.sources(from: [
            application("", "Nameless bundle"),
            application("com.example.Blank", "   ", pid: 2),
            application("com.example.Meet", "Meet", pid: 3)
        ])
        #expect(sources.map(\.id) == ["com.example.Meet"])
    }

    @Test("ScribeKit itself is excluded")
    func excludesSelf() {
        let sources = CaptureSourceCatalog.sources(
            from: [application("com.example.ScribeKit", "ScribeKit"), application("com.example.Meet", "Meet", pid: 2)],
            excludingBundleIdentifiers: ["com.example.ScribeKit"]
        )
        #expect(sources.map(\.id) == ["com.example.Meet"])
    }

    @Test("Several processes of one application produce a single source")
    func deduplicatesByBundleIdentifier() {
        let sources = CaptureSourceCatalog.sources(from: [
            application("com.example.Browser", "Browser", pid: 10),
            application("com.example.Browser", "Browser", pid: 11)
        ])
        #expect(sources.count == 1)
    }

    @Test("Results are ordered by name and stable across passes")
    func ordersResults() {
        let discovered = [
            application("com.example.Zed", "Zed", pid: 1),
            application("com.example.Meet", "meet", pid: 2),
            application("com.example.Arc", "Arc", pid: 3)
        ]
        let first = CaptureSourceCatalog.sources(from: discovered)
        let second = CaptureSourceCatalog.sources(from: discovered.reversed())
        #expect(first.map(\.displayName) == ["Arc", "meet", "Zed"])
        #expect(first == second)
    }
}
