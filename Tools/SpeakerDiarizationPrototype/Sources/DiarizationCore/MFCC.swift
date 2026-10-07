//
//  MFCC.swift
//  DiarizationCore
//

import Accelerate
import Foundation

/// Mel-frequency cepstral coefficients computed with Accelerate.
///
/// The classic hand-engineered speaker feature: 25 ms Hamming frames every
/// 10 ms, a 512-point FFT, 40 triangular mel bands from 20 Hz to 7.6 kHz, log
/// energies, and a DCT-II to 20 cepstra. Deterministic, dependency-free and
/// cheap. It describes the spectral envelope of the vocal tract, which is
/// speaker-dependent, but it describes the microphone and the room as well.
public struct MFCCExtractor: Sendable {
    public let sampleRate: Double
    public let frameLength = 400
    public let hop = 160
    public let fftSize = 512
    public let melBands = 40
    public let coefficients = 20

    private let window: [Float]
    private let filterbank: [[Float]]
    private let dct: [[Float]]

    public init(sampleRate: Double = 16_000) {
        self.sampleRate = sampleRate
        window = vDSP.window(ofType: Float.self, usingSequence: .hamming, count: frameLength, isHalfWindow: false)
        filterbank = Self.melFilterbank(bands: melBands, fftSize: fftSize, sampleRate: sampleRate, low: 20, high: 7_600)
        let bands = 40, cepstra = 20
        dct = (0..<cepstra).map { k in
            (0..<bands).map { n in Float(cos(Double.pi * Double(k) * (Double(n) + 0.5) / Double(bands))) }
        }
    }

    /// Seconds from the start of the signal to the centre of frame `index`.
    public func frameCenter(_ index: Int) -> Double {
        (Double(index * hop) + Double(frameLength) / 2) / sampleRate
    }

    /// Computes cepstra for every full frame of `samples`.
    ///
    /// - Returns: One row of ``coefficients`` values per frame; row 0 is c0
    ///   (overall log energy), which speaker embeddings normally discard.
    public func compute(_ samples: [Float]) -> [[Float]] {
        guard samples.count >= frameLength else { return [] }
        let frames = (samples.count - frameLength) / hop + 1
        let log2n = vDSP_Length(log2(Double(fftSize)))
        guard let fft = vDSP.FFT(log2n: log2n, radix: .radix2, ofType: DSPSplitComplex.self) else { return [] }

        var output = [[Float]]()
        output.reserveCapacity(frames)
        var padded = [Float](repeating: 0, count: fftSize)
        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var outReal = [Float](repeating: 0, count: fftSize / 2)
        var outImag = [Float](repeating: 0, count: fftSize / 2)
        var power = [Float](repeating: 0, count: fftSize / 2 + 1)
        var mel = [Float](repeating: 0, count: melBands)

        for frame in 0..<frames {
            let offset = frame * hop
            for i in 0..<frameLength { padded[i] = samples[offset + i] * window[i] }
            for i in frameLength..<fftSize { padded[i] = 0 }

            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    padded.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                    outReal.withUnsafeMutableBufferPointer { orp in
                        outImag.withUnsafeMutableBufferPointer { oip in
                            var out = DSPSplitComplex(realp: orp.baseAddress!, imagp: oip.baseAddress!)
                            fft.forward(input: split, output: &out)
                        }
                    }
                }
            }
            power[0] = outReal[0] * outReal[0]
            power[fftSize / 2] = outImag[0] * outImag[0]
            for k in 1..<(fftSize / 2) { power[k] = outReal[k] * outReal[k] + outImag[k] * outImag[k] }

            for b in 0..<melBands { mel[b] = log(max(vDSP.dot(filterbank[b], power), 1e-10)) }
            output.append(dct.map { vDSP.dot($0, mel) })
        }
        return output
    }

    private static func melFilterbank(bands: Int, fftSize: Int, sampleRate: Double, low: Double, high: Double) -> [[Float]] {
        func toMel(_ f: Double) -> Double { 2595 * log10(1 + f / 700) }
        func toHz(_ m: Double) -> Double { 700 * (pow(10, m / 2595) - 1) }
        let bins = fftSize / 2 + 1
        let lowMel = toMel(low), highMel = toMel(high)
        let edges = (0...(bands + 1)).map { toHz(lowMel + (highMel - lowMel) * Double($0) / Double(bands + 1)) }
        let binHz = sampleRate / Double(fftSize)
        return (0..<bands).map { b in
            (0..<bins).map { k in
                let f = Double(k) * binHz
                let (l, c, r) = (edges[b], edges[b + 1], edges[b + 2])
                if f <= l || f >= r { return 0 }
                return Float(f < c ? (f - l) / (c - l) : (r - f) / (r - c))
            }
        }
    }
}
