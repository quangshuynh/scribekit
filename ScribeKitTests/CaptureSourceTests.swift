//
//  CaptureSourceTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("CaptureSource")
struct CaptureSourceTests {

    @Test("Application sources are identified by bundle identifier")
    func applicationIdentity() {
        let source = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        #expect(source.id == "com.example.Meet")
        #expect(source.kind == .application)
    }

    @Test("Sources are compared by value and deduplicated")
    func valueSemantics() {
        let source = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        let duplicate = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet")
        let renamed = CaptureSource.application(bundleIdentifier: "com.example.Meet", displayName: "Meet Beta")
        #expect(source == duplicate)
        #expect(source != renamed)
        #expect(Set([source, duplicate]).count == 1)
    }
}
