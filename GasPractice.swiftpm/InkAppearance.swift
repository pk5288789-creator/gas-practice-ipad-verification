import UIKit
import PencilKit

enum InkAppearance {
    static func sameColor(_ color: UIColor?, _ expected: UIColor) -> Bool {
        guard let color else { return false }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        var er: CGFloat = 0, eg: CGFloat = 0, eb: CGFloat = 0, ea: CGFloat = 0
        guard color.getRed(&r, green: &g, blue: &b, alpha: &a), expected.getRed(&er, green: &eg, blue: &eb, alpha: &ea) else { return false }
        return abs(r-er) < 0.005 && abs(g-eg) < 0.005 && abs(b-eb) < 0.005 && abs(a-ea) < 0.005
    }
    // Keep monochrome ink readable on either paper. Persist it as black so
    // changing appearance does not make a backup depend on the active theme.
    static func adapt(_ drawing: PKDrawing, dark: Bool) -> PKDrawing {
        PKDrawing(strokes: drawing.strokes.map { stroke in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            guard stroke.ink.color.getRed(&r, green: &g, blue: &b, alpha: &a) else { return stroke }
            let monochrome = max(r,g,b)-min(r,g,b) < 0.04 && (max(r,g,b) < 0.15 || min(r,g,b) > 0.85)
            let oldDefault = abs(r-0.12) < 0.015 && abs(g-0.25) < 0.015 && abs(b-0.22) < 0.015
            guard monochrome || oldDefault else { return stroke }
            return PKStroke(ink: PKInk(stroke.ink.inkType, color: (dark ? UIColor.white : .black).withAlphaComponent(a)),
                            path: stroke.path, transform: stroke.transform, mask: stroke.mask)
        })
    }
}
