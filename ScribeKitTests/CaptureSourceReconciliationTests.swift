//
//  CaptureSourceReconciliationTests.swift
//  ScribeKitTests
//

import Testing
@testable import ScribeKit

@Suite("CaptureSourceReconciliation")
struct CaptureSourceReconciliationTests {

    @Test("A selection whose applications are all running matches completely")
    func matchesRunningSelection() {
        let outcome = CaptureSourceReconciliation.reconcile(
            requested: ["com.example.Meet", "com.example.Browser"],
            available: ["com.example.Meet", "com.example.Browser", "com.example.Editor"]
        )

        #expect(outcome.matched == ["com.example.Browser", "com.example.Meet"])
        #expect(outcome.missing.isEmpty)
        #expect(outcome.isComplete)
    }

    @Test("An application that is no longer running is reported as missing")
    func reportsMissingSelection() {
        let outcome = CaptureSourceReconciliation.reconcile(
            requested: ["com.example.Meet", "com.example.Browser"],
            available: ["com.example.Browser"]
        )

        #expect(outcome.matched == ["com.example.Browser"])
        #expect(outcome.missing == ["com.example.Meet"])
        #expect(!outcome.isComplete)
    }

    @Test("Matching is exact, so a related identifier is not treated as the selection")
    func doesNotMatchRelatedIdentifiers() {
        let outcome = CaptureSourceReconciliation.reconcile(
            requested: ["com.example.Browser"],
            available: ["com.example.Browser.helper", "com.example.BrowserBeta"]
        )

        #expect(outcome.matched.isEmpty)
        #expect(outcome.missing == ["com.example.Browser"])
    }

    @Test("An empty selection matches nothing and misses nothing")
    func emptySelection() {
        let outcome = CaptureSourceReconciliation.reconcile(
            requested: [],
            available: ["com.example.Browser"]
        )

        #expect(outcome.matched.isEmpty)
        #expect(outcome.missing.isEmpty)
        #expect(outcome.isComplete)
    }
}
