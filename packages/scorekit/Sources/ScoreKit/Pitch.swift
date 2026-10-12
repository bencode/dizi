import Accelerate
import Foundation

/// The frequency of the note sounding in a window of microphone samples, by YIN (de Cheveigné and Kawahara, 2002);
/// nil for silence or a sound without a clear pitch. Searches 250–2500 Hz: the dizi, from 大G's 筒音 up.
public func detectedFrequency(_ samples: [Float], sampleRate: Double) -> Double? {
    let loudness = samples.isEmpty ? 0 : vDSP.rootMeanSquare(samples)
    let shortest = Int(sampleRate / 2500)
    let longest = Int(sampleRate / 250)
    guard loudness > 0.005, samples.count >= 2 * longest else { return nil }
    let window = samples.count - longest
    // d(τ): how unlike the signal is to itself τ samples later.
    let head = Array(samples[0..<window])
    let difference = (0...longest).map { lag in
        vDSP.sumOfSquares(vDSP.subtract(head, samples[lag..<(lag + window)]))
    }
    // d'(τ): normalised by its running mean, so the first dip below the threshold is the period, not an octave down.
    var normalised: [Float] = [1]
    var sum: Float = 0
    for lag in 1...longest {
        sum += difference[lag]
        normalised.append(difference[lag] * Float(lag) / max(sum, .leastNonzeroMagnitude))
    }
    guard
        let dip = (shortest..<longest).first(where: { normalised[$0] < 0.15 }),
        let period = (dip..<longest).first(where: { normalised[$0 + 1] >= normalised[$0] })
    else { return nil }
    return sampleRate / refined(period, in: normalised)
}

/// The lag of the minimum between whole samples, from a parabola through the neighbours.
private func refined(_ lag: Int, in values: [Float]) -> Double {
    guard lag > 0, lag + 1 < values.count else { return Double(lag) }
    let (before, middle, after) = (Double(values[lag - 1]), Double(values[lag]), Double(values[lag + 1]))
    let curve = before - 2 * middle + after
    return curve == 0 ? Double(lag) : Double(lag) + (before - after) / (2 * curve)
}
