//
//  MainWindowPresenceTests.swift
//  ScribeKitTests
//

import AppKit
import Testing
@testable import ScribeKit

/// Whether the main window's interface should exist, which is the whole of
/// what decides between paying for a view hierarchy and not having one.
///
/// The windows here are real `NSWindow`s, because the question is what AppKit
/// does when one is closed, miniaturised or opened again — not what a double
/// would do.
@MainActor
@Suite("Main window presence")
struct MainWindowPresenceTests {

    /// A window to watch, never released while it is closed so it can be
    /// opened again the way the application's single window scene is.
    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        return window
    }

    /// Lets the deferred re-read of the window run.
    private func settle() async {
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(5))
            await Task.yield()
        }
    }

    @Test("A presence with no window yet presents nothing")
    func detachedByDefault() {
        let presence = MainWindowPresence()

        #expect(!presence.isPresenting)
        #expect(presence.observerCount == 0)
    }

    @Test("A window on screen presents; closing it stops presenting")
    func closingDetaches() async {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        let presence = MainWindowPresence()
        presence.attach(to: window)

        #expect(presence.isPresenting)

        window.close()
        await settle()

        #expect(!window.isVisible)
        #expect(!presence.isPresenting, "a closed window pays for no view hierarchy")
    }

    @Test("Opening the window again presents again")
    func reopeningAttaches() async {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        let presence = MainWindowPresence()
        presence.attach(to: window)
        window.close()
        await settle()
        #expect(!presence.isPresenting)

        window.makeKeyAndOrderFront(nil)
        await settle()

        #expect(presence.isPresenting, "a reopened window builds its interface again")
    }

    @Test("Opening and closing repeatedly accumulates no observers")
    func repeatedCyclesAreBounded() async {
        let window = makeWindow()
        let presence = MainWindowPresence()
        presence.attach(to: window)
        let registered = presence.observerCount
        #expect(registered > 0)

        for _ in 0..<5 {
            window.makeKeyAndOrderFront(nil)
            await settle()
            #expect(presence.isPresenting)
            window.close()
            await settle()
            #expect(!presence.isPresenting)
        }

        #expect(presence.observerCount == registered, "one set of observers, not one per cycle")
    }

    @Test("Reporting the same window again registers nothing new")
    func attachingIsIdempotent() {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        let presence = MainWindowPresence()

        presence.attach(to: window)
        let registered = presence.observerCount
        presence.attach(to: window)
        presence.attach(to: window)

        #expect(presence.observerCount == registered)
        #expect(presence.isPresenting)
        window.close()
    }

    @Test("A view that leaves its window stops presenting and lets the window go")
    func detachingReleasesObservers() {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        let presence = MainWindowPresence()
        presence.attach(to: window)
        #expect(presence.isPresenting)

        presence.attach(to: nil)

        #expect(!presence.isPresenting)
        #expect(presence.observerCount == 0)
        window.close()
    }

    @Test("A miniaturised window is not on screen, so it presents nothing")
    func miniaturisingDetaches() async {
        let window = makeWindow()
        window.makeKeyAndOrderFront(nil)
        let presence = MainWindowPresence()
        presence.attach(to: window)
        #expect(presence.isPresenting)

        window.miniaturize(nil)
        await settle()
        // Miniaturising is refused in some test environments; the presence has
        // to agree with the window either way rather than with the request.
        #expect(presence.isPresenting == (window.isVisible && !window.isMiniaturized))

        window.deminiaturize(nil)
        await settle()
        #expect(presence.isPresenting)
        window.close()
    }
}
