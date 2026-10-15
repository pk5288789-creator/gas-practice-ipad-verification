import UIKit
import PencilKit

extension CGFloat {
    func clamped(_ range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(range.upperBound, Swift.max(range.lowerBound, self)) }
}

enum PencilSmoothing {
    // Apply only to the newly committed stroke. Preserve pressure, timing,
    // stroke endpoints and masks; never rewrite already saved drawings.
    static func apply(_ stroke: PKStroke, strength: CGFloat) -> PKStroke {
        let amount = strength.clamped(0...1)
        let path = stroke.path
        guard amount > 0, path.count >= 5 else { return stroke }
        let points = (0..<path.count).map { path[$0] }
        var filtered = [PKStrokePoint]()
        for (i, p) in points.enumerated() {
            guard i >= 2, i < points.count - 2 else { filtered.append(p); continue }
            let a = points[i-2].location, b = points[i+2].location
            let incoming = CGPoint(x: p.location.x-a.x, y: p.location.y-a.y)
            let outgoing = CGPoint(x: b.x-p.location.x, y: b.y-p.location.y)
            let lengths = hypot(incoming.x,incoming.y) * hypot(outgoing.x,outgoing.y)
            // Keep deliberate sharp corners and reversals intact.
            if lengths > 0.001 && (incoming.x*outgoing.x + incoming.y*outgoing.y) / lengths < 0.25 { filtered.append(p); continue }
            let previous = points[i-1].location, next = points[i+1].location
            let tx: CGFloat = (a.x + b.x) / 8 + (previous.x + p.location.x + next.x) / 4
            let ty: CGFloat = (a.y + b.y) / 8 + (previous.y + p.location.y + next.y) / 4
            let location = CGPoint(x: p.location.x + (tx-p.location.x)*amount,
                                   y: p.location.y + (ty-p.location.y)*amount)
            let changed = PKStrokePoint(location: location, timeOffset: p.timeOffset, size: p.size,
                                 opacity: p.opacity, force: p.force, azimuth: p.azimuth, altitude: p.altitude)
            filtered.append(changed)
        }
        return PKStroke(ink: stroke.ink, path: PKStrokePath(controlPoints: filtered, creationDate: path.creationDate),
                        transform: stroke.transform, mask: stroke.mask)
    }
}
