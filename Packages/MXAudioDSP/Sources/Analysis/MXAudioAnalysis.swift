import Accelerate
import Foundation

/// Measurement primitives shared by the latency calibrator and every test
/// suite. Living in `MXAudioDSP` keeps one implementation of "how loud is this"
/// so a pass criterion means the same thing everywhere.
public enum MXAudioAnalysis {

    // MARK: - Level

    public static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_rmsqv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    public static func peak(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        var result: Float = 0
        vDSP_maxmgv(samples, 1, &result, vDSP_Length(samples.count))
        return result
    }

    public static func decibels(_ linear: Float) -> Float {
        20 * log10(max(linear, 1e-9))
    }

    public static func rmsDB(_ samples: [Float]) -> Float {
        decibels(rms(samples))
    }

    public static func peakDB(_ samples: [Float]) -> Float {
        decibels(peak(samples))
    }

    /// Clipping check for I-01, which asks for a healthy but unclipped peak.
    public static func isClipped(_ samples: [Float], threshold: Float = 0.999) -> Bool {
        peak(samples) >= threshold
    }

    public static func isSilent(_ samples: [Float], floorDB: Float = -60) -> Bool {
        rmsDB(samples) <= floorDB
    }

    /// Sliding-window RMS. Used to prove a mute reaches silence inside a
    /// deadline rather than just eventually.
    public static func windowedRMS(_ samples: [Float], windowFrames: Int) -> [Float] {
        guard windowFrames > 0, samples.count >= windowFrames else { return [] }
        var result: [Float] = []
        result.reserveCapacity(samples.count / windowFrames)
        var index = 0
        while index + windowFrames <= samples.count {
            result.append(rms(Array(samples[index..<index + windowFrames])))
            index += windowFrames
        }
        return result
    }

    /// First frame at which the signal stays below `floorDB` for a full window.
    public static func firstSilentFrame(_ samples: [Float],
                                        windowFrames: Int = 512,
                                        floorDB: Float = -60) -> Int? {
        var index = 0
        while index + windowFrames <= samples.count {
            let window = Array(samples[index..<index + windowFrames])
            if rmsDB(window) <= floorDB { return index }
            index += windowFrames
        }
        return nil
    }

    // MARK: - Onsets

    /// Energy-rise onset detector.
    ///
    /// Reports the frame where a window's RMS jumps above `riseFactor` times the
    /// previous window and clears an absolute floor, which is robust enough for
    /// click tracks and drum hits without needing a spectral flux stage.
    public static func detectOnsets(_ samples: [Float],
                                    windowFrames: Int = 64,
                                    riseFactor: Float = 4,
                                    floor: Float = 0.005,
                                    minimumSpacingFrames: Int = 256) -> [Int] {
        guard samples.count > windowFrames * 2 else { return [] }
        var onsets: [Int] = []
        var previous = rms(Array(samples[0..<windowFrames]))
        var index = windowFrames
        var lastOnset = -minimumSpacingFrames

        while index + windowFrames <= samples.count {
            let current = rms(Array(samples[index..<index + windowFrames]))
            if current > floor,
               current > previous * riseFactor,
               index - lastOnset >= minimumSpacingFrames {
                onsets.append(refineOnset(samples, around: index, windowFrames: windowFrames))
                lastOnset = index
            }
            previous = max(current, 1e-9)
            index += windowFrames
        }
        return onsets
    }

    /// Walks back from a coarse window to the first sample that crosses a
    /// fraction of the window peak, which lands the onset within a sample or two.
    private static func refineOnset(_ samples: [Float], around index: Int, windowFrames: Int) -> Int {
        let start = max(0, index - windowFrames)
        let end = min(samples.count, index + windowFrames)
        guard start < end else { return index }
        let window = Array(samples[start..<end])
        let localPeak = peak(window)
        guard localPeak > 0 else { return index }
        let threshold = localPeak * 0.1
        for i in start..<end where abs(samples[i]) >= threshold {
            return i
        }
        return index
    }

    // MARK: - Cross-correlation

    /// Lag in frames that best aligns `signal` to `reference`.
    ///
    /// Positive means `signal` arrives later. This is the measurement behind
    /// the loopback calibrator and behind L-02 / L-03.
    public static func crossCorrelationLag(reference: [Float],
                                           signal: [Float],
                                           maxLag: Int) -> (lag: Int, correlation: Float) {
        guard !reference.isEmpty, !signal.isEmpty else { return (0, 0) }
        var bestLag = 0
        var bestValue: Float = -.greatestFiniteMagnitude

        for lag in -maxLag...maxLag {
            var sum: Float = 0
            var count = 0
            let start = max(0, -lag)
            let end = min(reference.count, signal.count - lag)
            guard start < end else { continue }
            for i in start..<end {
                sum += reference[i] * signal[i + lag]
                count += 1
            }
            guard count > 0 else { continue }
            let normalized = sum / Float(count)
            if normalized > bestValue {
                bestValue = normalized
                bestLag = lag
            }
        }
        return (bestLag, bestValue)
    }

    // MARK: - Spectrum

    /// Exact magnitude at one frequency via the Goertzel algorithm. Cheaper and
    /// more precise than reading an FFT bin when the target frequency is known.
    public static func magnitude(of samples: [Float],
                                 atFrequency frequency: Float,
                                 sampleRate: Double) -> Float {
        guard !samples.isEmpty, frequency > 0 else { return 0 }
        let n = samples.count
        let k = 2 * Double.pi * Double(frequency) / sampleRate
        let coefficient = Float(2 * cos(k))

        var s0: Float = 0, s1: Float = 0, s2: Float = 0
        for sample in samples {
            s0 = sample + coefficient * s1 - s2
            s2 = s1
            s1 = s0
        }
        let real = s1 - s2 * cos(Float(k))
        let imag = s2 * sin(Float(k))
        return 2 * sqrt(real * real + imag * imag) / Float(n)
    }

    /// Hann-windowed magnitude spectrum. Length is `fftSize / 2`.
    public static func magnitudeSpectrum(_ samples: [Float], fftSize: Int = 8192) -> [Float] {
        let n = min(fftSize, previousPowerOfTwo(samples.count))
        guard n >= 64 else { return [] }

        var input = Array(samples[0..<n])
        var window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        vDSP_vmul(input, 1, window, 1, &input, 1, vDSP_Length(n))

        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return [] }
        defer { vDSP_destroy_fftsetup(setup) }

        let half = n / 2
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var magnitudes = [Float](repeating: 0, count: half)

        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!,
                                            imagp: imagPtr.baseAddress!)
                input.withUnsafeBufferPointer { inputPtr in
                    inputPtr.baseAddress!.withMemoryRebound(to: DSPComplex.self,
                                                            capacity: half) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(half))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(half))
            }
        }

        // vDSP's real FFT carries a factor of 2.
        var scale: Float = 1 / (2 * Float(n))
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(half))
        return magnitudes
    }

    /// Loudest frequency present, in Hz. Backs SY-01.
    public static func dominantFrequency(_ samples: [Float],
                                         sampleRate: Double,
                                         fftSize: Int = 8192) -> Float {
        let spectrum = magnitudeSpectrum(samples, fftSize: fftSize)
        guard !spectrum.isEmpty else { return 0 }
        // Skip DC and the first couple of bins, which carry window leakage.
        var bestBin = 1
        var bestValue: Float = 0
        for bin in 2..<spectrum.count where spectrum[bin] > bestValue {
            bestValue = spectrum[bin]
            bestBin = bin
        }
        let binWidth = Float(sampleRate) / Float(spectrum.count * 2)
        return Float(bestBin) * binWidth
    }

    /// Brightness measure. AS-02 uses the difference between two programs to
    /// prove the sampler actually changed timbre.
    public static func spectralCentroid(_ samples: [Float],
                                        sampleRate: Double,
                                        fftSize: Int = 8192) -> Float {
        let spectrum = magnitudeSpectrum(samples, fftSize: fftSize)
        guard !spectrum.isEmpty else { return 0 }
        let binWidth = Float(sampleRate) / Float(spectrum.count * 2)
        var weighted: Float = 0
        var total: Float = 0
        for (bin, magnitude) in spectrum.enumerated() {
            weighted += Float(bin) * binWidth * magnitude
            total += magnitude
        }
        guard total > 0 else { return 0 }
        return weighted / total
    }

    /// Energy in a frequency band, in dB. FX-07 asserts a high-pass drops
    /// everything below its corner by at least 12 dB.
    public static func bandEnergyDB(_ samples: [Float],
                                    from lowHz: Float,
                                    to highHz: Float,
                                    sampleRate: Double,
                                    fftSize: Int = 8192) -> Float {
        let spectrum = magnitudeSpectrum(samples, fftSize: fftSize)
        guard !spectrum.isEmpty else { return -120 }
        let binWidth = Float(sampleRate) / Float(spectrum.count * 2)
        var energy: Float = 0
        for (bin, magnitude) in spectrum.enumerated() {
            let frequency = Float(bin) * binWidth
            guard frequency >= lowHz, frequency <= highHz else { continue }
            energy += magnitude * magnitude
        }
        return 10 * log10(max(energy, 1e-12))
    }

    /// Harmonic distortion of a known fundamental, as a ratio. FX-01 asserts
    /// distortion raises it.
    public static func totalHarmonicDistortion(_ samples: [Float],
                                               fundamental: Float,
                                               sampleRate: Double,
                                               harmonics: Int = 8) -> Float {
        let fundamentalMagnitude = magnitude(of: samples,
                                             atFrequency: fundamental,
                                             sampleRate: sampleRate)
        guard fundamentalMagnitude > 1e-6 else { return 0 }
        var harmonicEnergy: Float = 0
        for h in 2...max(2, harmonics) {
            let frequency = fundamental * Float(h)
            guard Double(frequency) < sampleRate / 2 else { break }
            let m = magnitude(of: samples, atFrequency: frequency, sampleRate: sampleRate)
            harmonicEnergy += m * m
        }
        return sqrt(harmonicEnergy) / fundamentalMagnitude
    }

    /// Energy above `aboveHz` in the *envelope* of the signal.
    ///
    /// Zipper noise from a stepped parameter shows up as high-frequency
    /// modulation of the amplitude envelope rather than in the audio spectrum
    /// itself, so FX-06 measures it here.
    public static func envelopeModulationEnergy(_ samples: [Float],
                                                sampleRate: Double,
                                                aboveHz: Float = 200) -> Float {
        guard samples.count > 1024 else { return 0 }
        let windowFrames = 32
        var envelope: [Float] = []
        envelope.reserveCapacity(samples.count / windowFrames)
        var index = 0
        while index + windowFrames <= samples.count {
            envelope.append(rms(Array(samples[index..<index + windowFrames])))
            index += windowFrames
        }
        guard envelope.count >= 64 else { return 0 }

        let envelopeRate = sampleRate / Double(windowFrames)
        // Remove the DC and slow trend so only fast steps remain.
        let mean = envelope.reduce(0, +) / Float(envelope.count)
        var centred = envelope.map { $0 - mean }
        let count = previousPowerOfTwo(centred.count)
        centred = Array(centred[0..<count])

        return bandEnergyDB(centred,
                            from: aboveHz,
                            to: Float(envelopeRate / 2),
                            sampleRate: envelopeRate,
                            fftSize: count)
    }

    // MARK: - Helpers

    public static func previousPowerOfTwo(_ value: Int) -> Int {
        guard value > 1 else { return 1 }
        var result = 1
        while result * 2 <= value { result *= 2 }
        return result
    }

    /// Deterministic content fingerprint. SFZ-01 and SFZ-02 use it to prove two
    /// hits used *different* samples without needing golden WAVs per layer.
    public static func fingerprint(_ samples: [Float], precision: Float = 10_000) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for sample in samples {
            let quantised = Int32((sample * precision).rounded())
            var bits = UInt64(bitPattern: Int64(quantised))
            bits ^= bits >> 33
            hash = (hash ^ bits) &* 0x100000001b3
        }
        return hash
    }
}
