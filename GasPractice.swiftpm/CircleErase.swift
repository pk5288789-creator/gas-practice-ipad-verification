import UIKit
import PencilKit

enum CircleErase {
    // Finished PencilKit paths have no browser pointer capture or palm events.
    static func region(for stroke: PKStroke) -> CGRect? {
        guard stroke.path.count > 2 else { return nil }
        let duration = stroke.path[stroke.path.count - 1].timeOffset - stroke.path[0].timeOffset
        guard duration > 0.1, duration <= 4.5 else { return nil }
        let points = stroke.path.interpolatedPoints(by: .distance(3)).prefix(8192).map { $0.location.applying(stroke.transform) }
        return region(points: Array(points), duration: duration)
    }

    static func region(points: [CGPoint], duration: TimeInterval) -> CGRect? {
        guard points.count >= 24, points.count < 8192, duration > 0.1, duration <= 4.5,
              points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let xs = points.map(\.x), ys = points.map(\.y)
        let box = CGRect(x: xs.min()!, y: ys.min()!, width: xs.max()! - xs.min()!, height: ys.max()! - ys.min()!)
        guard min(box.width, box.height) >= 16, max(box.width, box.height) <= 360,
              box.width / box.height >= 0.4, box.width / box.height <= 2.5 else { return nil }
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
        guard turns >= 2.65, turns / duration >= 0.65, total > 0,
              abs(signed) / total >= 0.8, sqrt(variance) / mean <= 0.4 else { return nil }
        return box
    }

    static func erase(_ drawing: PKDrawing, in region: CGRect) -> PKDrawing {
        let ellipse = UIBezierPath(ovalIn: region).cgPath
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
