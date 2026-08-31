//
//  DiagnosticReportWriter.swift
//  ScribeKit
//

import Foundation

/// Why a diagnostic report could not be saved.
nonisolated enum DiagnosticReportWriteError: Error, Equatable, LocalizedError {

    /// The report could not be turned into JSON. Nothing in the report can
    /// cause this; it exists so that a failure is reported rather than
    /// swallowed.
    case encodingFailed

    /// The bytes could not be written where the user asked.
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The diagnostic report could not be prepared."
        case .writeFailed:
            "The diagnostic report could not be written to that location."
        }
    }
}

/// Writes a diagnostic report to a location the user picked.
///
/// The writer is given a ``DiagnosticReport`` and nothing else. It holds no
/// reference to a meeting, a transcript, a recording or a session folder, so
/// there is no path by which canonical content could reach a report through it:
/// what it writes is exactly what was assembled, and what was assembled has
/// already passed ``DiagnosticSafety``'s contract.
///
/// The write is atomic. A report that fails halfway is not a shorter report, it
/// is a file that says something untrue about a Mac, and the caller is told the
/// write failed rather than being handed a partial one.
nonisolated struct DiagnosticReportWriter {

    /// How bytes reach the filesystem. Substituted in tests to prove that a
    /// failure is reported rather than reported as a success.
    private let store: @Sendable (Data, URL) throws -> Void

    /// Creates a writer.
    ///
    /// - Parameter store: Writes data to a URL. The default writes atomically.
    init(
        store: @escaping @Sendable (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        }
    ) {
        self.store = store
    }

    /// Encodes a report and writes it.
    ///
    /// An existing file at the destination is replaced, because the user chose
    /// that destination in a save panel that asked them about it. Replacement
    /// is part of the atomic write, so a destination that already held a report
    /// still holds the old one if this fails.
    ///
    /// - Parameters:
    ///   - report: The assembled report.
    ///   - url: Where the user asked for it.
    /// - Returns: How many bytes were written.
    /// - Throws: ``DiagnosticReportWriteError`` when it could not be prepared
    ///   or could not be written.
    @discardableResult
    func write(_ report: DiagnosticReport, to url: URL) throws -> Int {
        let data: Data
        do {
            data = try report.encoded()
        } catch {
            throw DiagnosticReportWriteError.encodingFailed
        }
        do {
            try store(data, url)
        } catch {
            throw DiagnosticReportWriteError.writeFailed
        }
        return data.count
    }

    /// The name a report is offered under, which sorts and never collides for
    /// two exports a second apart.
    ///
    /// - Parameter date: When the report was made.
    /// - Returns: A filename with no meeting title and no user name in it.
    static func filename(for date: Date) -> String {
        var formatter = Date.ISO8601FormatStyle(timeZone: .current)
        formatter = formatter.year().month().day()
            .dateTimeSeparator(.standard)
            .time(includingFractionalSeconds: false)
        let stamp = date.formatted(formatter)
            .replacingOccurrences(of: ":", with: "-")
        return "ScribeKit-Diagnostics-\(stamp).json"
    }
}
