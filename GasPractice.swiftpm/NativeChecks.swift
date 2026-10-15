import UIKit
import PencilKit

// Runs on the user's iPad; it is not a substitute for physical Pencil testing.
enum NativeChecks {
    static func run() -> String {
        var failures = SmoothingChecks.run()
        for turns in [3.0, -3.0, 3.2] {
            let points = (0...240).map { i in
                let angle = Double(i) / 240 * turns * 2 * .pi
                return CGPoint(x: 100 + 40 * cos(angle), y: 100 + 30 * sin(angle))
            }
            if CircleErase.region(points: points, duration: 2.5) == nil { failures.append("원 \(turns)회") }
        }
        for turns in [1.0, 2.0] {
            let points = (0...240).map { i in
                let angle = Double(i) / 240 * turns * 2 * .pi
                return CGPoint(x: 100 + 40 * cos(angle), y: 100 + 30 * sin(angle))
            }
            if CircleErase.region(points: points, duration: 1.5) != nil { failures.append("일반 원 보호") }
        }
        for scale in [CGFloat(0.25), 1, 2] {
            let loop = (0...160).map { i -> CGPoint in
                let angle = Double(i)/160*2.5*2*Double.pi
                return CGPoint(x:(150+90*cos(angle))/scale,y:(150+50*sin(angle))/scale)
            }
            if CircleErase.region(points: loop, duration: 0.35, scale: scale) == nil { failures.append("확대율별 빠른 원 \(scale)") }
        }
        let scribble = (0...120).map { i -> CGPoint in
            CGPoint(x:100+60*cos(Double(i)/120*7*Double.pi),y:80+CGFloat(i)/3)
        }
        if CircleErase.scribbleRegion(points:scribble,duration:1.2) == nil { failures.append("왕복 낙서 지우기") }
        for stroke in SmoothingChecks.fixture().strokes {
            if CircleErase.region(for:stroke) != nil || CircleErase.scribbleRegion(for:stroke) != nil { failures.append("일반 한글 획 보호") }
        }
        let points = (0...100).map { i in
            PKStrokePoint(location: CGPoint(x: CGFloat(20 + i * 2), y: 100), timeOffset: Double(i) * 0.01,
                          size: CGSize(width: 3, height: 3), opacity: 1, force: 0.5, azimuth: 0, altitude: .pi / 2)
        }
        let original = PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))])
        let result = CircleErase.erase(original, in: CGRect(x: 70, y: 70, width: 60, height: 60))
        if let mask = result.strokes.first?.mask {
            if mask.contains(CGPoint(x: 100, y: 100)) { failures.append("원 중심 마스크") }
            if !mask.contains(CGPoint(x: 40, y: 100)) { failures.append("원 밖 필기 보존") }
        } else { failures.append("부분 지우기 마스크") }
        do { _ = try PKDrawing(data: result.dataRepresentation()) } catch { failures.append("필기 저장 복원") }
        return failures.isEmpty ? "내부 확인 통과 (실제 펜슬 검증은 별도)" : "내부 확인 실패: " + failures.joined(separator: ", ")
    }
}
