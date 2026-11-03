//
//  TranscriptSeal.swift
//  ScribeKit
//

import CryptoKit
import Foundation

/// Evidence of exactly which bytes a transcript held when ScribeKit closed it.
///
/// A seal is a statement about a file, not a copy of it: the name of the
/// digest algorithm, the digest of the file's bytes in lower-case hexadecimal,
/// and how many bytes were digested. It holds no transcript text and nothing
/// from which text could be recovered.
///
/// It is recorded once, in `.scribekit/session.json`, after the transcript has
/// been flushed and closed and in the same atomic write that records how the
/// meeting ended, so there is no moment at which a record claims a meeting
/// closed while carrying a seal for some other version of its file. It is
/// never written into the Markdown, never recomputed for a file ScribeKit did
/// not just close, and never updated to match a file that has since changed:
/// a seal that no longer matches is reported, and the seal and the transcript
/// both stay exactly as they are.
nonisolated struct TranscriptSeal: Codable, Equatable, Sendable {

    /// The name ``algorithm`` carries for SHA-256, the only digest this build
    /// writes or checks.
    static let sha256 = "sha256"

    /// Which digest ``digest`` is. Named rather than implied, so a seal a
    /// later build writes with another algorithm is reported as one this build
    /// cannot check rather than as a mismatch.
    let algorithm: String

    /// The digest of the file's bytes, as lower-case hexadecimal.
    let digest: String

    /// How many bytes the digest covers, which is the file's length when it
    /// was sealed.
    let byteCount: Int

    /// Creates a seal.
    ///
    /// - Parameters:
    ///   - algorithm: Which digest `digest` is.
    ///   - digest: The digest, as lower-case hexadecimal.
    ///   - byteCount: How many bytes it covers.
    init(algorithm: String = TranscriptSeal.sha256, digest: String, byteCount: Int) {
        self.algorithm = algorithm
        self.digest = digest
        self.byteCount = byteCount
    }

    /// Whether this build knows how to check the seal.
    var isSupported: Bool { algorithm == Self.sha256 }

    /// Seals bytes already in memory.
    ///
    /// The digest is computed over the buffer in place; nothing is copied.
    ///
    /// - Parameter data: The file's bytes.
    /// - Returns: Their SHA-256 seal.
    static func sealing(_ data: Data) -> TranscriptSeal {
        TranscriptSeal(digest: hex(SHA256.hash(data: data)), byteCount: data.count)
    }

    /// Seals a file by reading it in fixed-size chunks.
    ///
    /// Memory stays at one chunk however long the meeting was; the file is
    /// only read, never opened for writing.
    ///
    /// - Parameters:
    ///   - url: The file to seal.
    ///   - chunkSize: How many bytes are read at a time.
    /// - Returns: The file's SHA-256 seal.
    /// - Throws: The system error when the file cannot be opened or read.
    static func sealing(fileAt url: URL, chunkSize: Int = 64 * 1_024) throws -> TranscriptSeal {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count = 0
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
            count += chunk.count
        }
        return TranscriptSeal(digest: hex(hasher.finalize()), byteCount: count)
    }

    /// Renders a digest as lower-case hexadecimal.
    ///
    /// - Parameter digest: The digest.
    /// - Returns: Two characters per byte.
    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Seals a transcript ScribeKit has just closed.
///
/// A boundary of its own so the writer's ordering can be tested against a
/// double that fails on demand, and so the production implementation stays a
/// read with no decisions in it.
nonisolated protocol TranscriptSealing: Sendable {

    /// Reads a closed transcript and describes its bytes.
    ///
    /// - Parameter url: The transcript's location.
    /// - Returns: Its seal.
    /// - Throws: The system error when it cannot be read.
    func seal(transcriptAt url: URL) throws -> TranscriptSeal
}

/// Seals transcripts by reading them from the filesystem.
nonisolated struct FileTranscriptSealer: TranscriptSealing {

    /// Creates the system-backed sealer.
    init() {}

    func seal(transcriptAt url: URL) throws -> TranscriptSeal {
        try TranscriptSeal.sealing(fileAt: url)
    }
}
