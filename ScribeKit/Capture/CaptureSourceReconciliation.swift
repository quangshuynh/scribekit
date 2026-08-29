//
//  CaptureSourceReconciliation.swift
//  ScribeKit
//

import Foundation

/// Matches remembered or selected source identities against what is running
/// right now.
///
/// A selection is a set of bundle identifiers, which survive relaunches; the
/// processes behind them do not. Capture therefore resolves identifiers afresh
/// at the moment it starts, and this policy — free of any capture framework —
/// decides what counts as a match.
nonisolated enum CaptureSourceReconciliation {

    /// The result of matching a selection against the running applications.
    struct Outcome: Equatable, Sendable {
        /// Requested identifiers that are running, in sorted order.
        let matched: [String]

        /// Requested identifiers that are not running, in sorted order.
        let missing: [String]

        /// Whether every requested identifier was found.
        var isComplete: Bool { missing.isEmpty }
    }

    /// Reconciles requested identifiers against those currently available.
    ///
    /// Matching is exact. A bundle identifier is an application's identity, so
    /// widening the match — by prefix, by name, by process ancestry — would
    /// risk capturing an application the user did not choose.
    ///
    /// - Parameters:
    ///   - requested: Bundle identifiers the user selected.
    ///   - available: Bundle identifiers the system currently reports.
    /// - Returns: Which of the requested identifiers were found and which were
    ///   not.
    static func reconcile(
        requested: Set<String>,
        available: Set<String>
    ) -> Outcome {
        Outcome(
            matched: requested.intersection(available).sorted(),
            missing: requested.subtracting(available).sorted()
        )
    }
}
