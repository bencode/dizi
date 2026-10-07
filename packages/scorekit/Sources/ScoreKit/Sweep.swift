import CoreGraphics

/// A point the playhead passes through: a note's digit at the tick the note starts.
public struct Anchor: Sendable, Equatable {
    public let id: String
    public let tick: Int
    public let position: CGFloat
}

/// The monotone cubic curve (Fritsch–Butland) through `points`, evaluated at `tick`. It passes through every
/// point, never moves backwards, and its speed changes gradually instead of jumping at each point.
func smoothPosition(at tick: Double, through points: [(tick: Double, position: CGFloat)]) -> CGFloat {
    guard let first = points.first, let last = points.last, points.count > 1 else { return points.first?.position ?? 0 }
    guard tick > first.tick else { return first.position }
    guard tick < last.tick else { return last.position }
    let slopes = zip(points, points.dropFirst()).map { left, right in
        Double(right.position - left.position) / (right.tick - left.tick)
    }
    let segment = (points.lastIndex { $0.tick <= tick } ?? 0)
    let (start, end) = (points[segment], points[segment + 1])
    let span = end.tick - start.tick
    let unit = (tick - start.tick) / span
    let startTangent = tangent(at: segment, slopes: slopes)
    let endTangent = tangent(at: segment + 1, slopes: slopes)
    let position =
        (2 * pow(unit, 3) - 3 * pow(unit, 2) + 1) * Double(start.position)
        + (pow(unit, 3) - 2 * pow(unit, 2) + unit) * span * startTangent
        + (-2 * pow(unit, 3) + 3 * pow(unit, 2)) * Double(end.position)
        + (pow(unit, 3) - pow(unit, 2)) * span * endTangent
    return CGFloat(position)
}

/// The curve's slope at a point: the harmonic mean of the slopes on either side (zero at a turn), which
/// keeps the curve monotone.
private func tangent(at index: Int, slopes: [Double]) -> Double {
    guard index > 0 else { return slopes[0] }
    guard index < slopes.count else { return slopes[slopes.count - 1] }
    let (before, after) = (slopes[index - 1], slopes[index])
    return before * after > 0 ? 2 / (1 / before + 1 / after) : 0
}
