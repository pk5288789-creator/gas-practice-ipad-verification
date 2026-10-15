import UIKit
import PencilKit

enum CircleErase {
    // Finished PencilKit paths have no browser pointer capture or palm events.
    static func region(for stroke: PKStroke, scale: CGFloat = 1) -> CGRect? {
        guard stroke.path.count > 2 else { return nil }
        let duration = stroke.path[stroke.path.count - 1].timeOffset - stroke.path[0].timeOffset
        guard duration > 0.03, duration <= 8 else { return nil }
        let points = stroke.path.interpolatedPoints(by: .distance(3)).prefix(8192).map { $0.location.applying(stroke.transform) }
        return region(points: Array(points), duration: duration, scale: scale)
    }

    static func region(points: [CGPoint], duration: TimeInterval, scale: CGFloat = 1) -> CGRect? {
        guard points.count >= 12, points.count < 8192, duration > 0.03, duration <= 8,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        guard min(box.width, box.height) * scale >= 8, max(box.width, box.height) * scale <= 600,
              box.width / box.height >= 0.2, box.width / box.height <= 5 else { return nil }
        var signed = 0.0, total = 0.0, radii = [Double](), previous: Double?
        for point in points {
            let x = Double((point.x - box.midX) / (box.width / 2))
            let y = Double((point.y - box.midY) / (box.height / 2))
            let angle = atan2(y, x)
            if let p = previous {
                let delta = atan2(sin(angle - p), cos(angle - p))
                guard abs(delta) < .pi / 2 else { return nil }
                signed += delta; total += abs(delta)
            }
            previous = angle; radii.append(hypot(x, y))
        }
        let turns = abs(signed) / (2 * .pi), mean = radii.reduce(0, +) / Double(radii.count)
        let variance = radii.reduce(0) { $0 + pow($1 - mean, 2) } / Double(radii.count)
        guard turns >= 2.3, total > 0,
              abs(signed) / total >= 0.55, mean > 0, sqrt(variance) / mean <= 0.8 else { return nil }
        return box
    }

    static func scribbleRegion(for stroke: PKStroke, scale: CGFloat = 1) -> CGRect? {
        guard stroke.path.count > 2 else { return nil }
        let duration = stroke.path[stroke.path.count - 1].timeOffset - stroke.path[0].timeOffset
        let points = stroke.path.interpolatedPoints(by: .distance(3)).prefix(8192).map { $0.location.applying(stroke.transform) }
        return scribbleRegion(points: Array(points), duration: duration, scale: scale)
    }
    static func scribbleRegion(points: [CGPoint], duration: TimeInterval, scale: CGFloat = 1) -> CGRect? {
        guard points.count >= 12, points.count < 8192, duration > 0.03, duration <= 5,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()!-xs.min()!, height: ys.max()!-ys.min()!)
        guard min(box.width,box.height)*scale >= 6, max(box.width,box.height)*scale >= 24,
              max(box.width,box.height)*scale <= 600 else { return nil }
        let values = box.width >= box.height ? xs : ys
        let span = max(box.width,box.height), threshold = span * 0.35
        var pivot = values[0], extreme = pivot, direction = 0, reversals = 0
        var travel: CGFloat = 0
        for i in 1..<values.count {
            let value = values[i]; travel += abs(value-values[i-1])
            if direction == 0 {
                if abs(value-pivot) >= threshold { direction = value > pivot ? 1 : -1; extreme = value }
            } else if direction > 0 {
                if value > extreme { extreme = value }
                else if extreme-value >= threshold { reversals += 1; direction = -1; pivot = extreme; extreme = value }
            } else {
                if value < extreme { extreme = value }
                else if value-extreme >= threshold { reversals += 1; direction = 1; pivot = extreme; extreme = value }
            }
        }
        guard reversals >= 5, travel >= span*5 else { return nil }
        return box
    }

    static func erase(_ drawing: PKDrawing, in region: CGRect, rectangular: Bool = false) -> PKDrawing {
        let ellipse = (rectangular ? UIBezierPath(rect: region) : UIBezierPath(ovalIn: region)).cgPath
        let strokes = drawing.strokes.compactMap { stroke -> PKStroke? in
            guard stroke.renderBounds.intersects(region) else { return stroke }
            guard abs(stroke.transform.a * stroke.transform.d - stroke.transform.b * stroke.transform.c) > 0.00001 else { return stroke }
            var inverse = stroke.transform.inverted()
            guard let localErase = ellipse.copy(using: &inverse) else { return stroke }
            let base = stroke.mask?.cgPath ?? UIBezierPath(rect: stroke.renderBounds.insetBy(dx: -8, dy: -8).applying(inverse)).cgPath
            let remaining = base.subtracting(localErase, using: .winding)
            guard !remaining.isEmpty else { return nil }
            return PKStroke(ink: stroke.ink, path: stroke.path, transform: stroke.transform, mask: UIBezierPath(cgPath: remaining))
        }
        return PKDrawing(strokes: strokes)
    }
}
