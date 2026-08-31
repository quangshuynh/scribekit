//
//  CaptureAccessProbing.swift
//  ScribeKit
//

import CoreGraphics

/// Reports whether macOS currently grants ScribeKit the access application
/// audio capture needs.
///
/// The protocol exists so the answer can be substituted in tests, and so the
/// one place that asks the system is a value rather than a call scattered
/// through discovery. It answers one question and never asks for anything: a
/// probe must not prompt, because the permission flow belongs to the first
/// discovery attempt, not to a screen appearing.
protocol CaptureAccessProbing: Sendable {
    /// Whether Screen & System Audio Recording access is currently granted.
    ///
    /// - Returns: What macOS reports right now. It is a fact about this
    ///   moment, not a subscription: nothing here watches for it to change.
    func hasScreenRecordingAccess() -> Bool
}

/// The answer macOS gives for this process.
///
/// `CGPreflightScreenCaptureAccess` is the authoritative check for the
/// permission ScreenCaptureKit requires, and it is the reason ScribeKit can say
/// "access is not available" rather than repeating a framework error: a
/// discovery failure alone does not distinguish a missing permission from a
/// system that failed for another reason. It does not prompt, so it is safe to
/// call whenever a discovery attempt has just failed.
struct SystemCaptureAccessProbe: CaptureAccessProbing {
    func hasScreenRecordingAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}
