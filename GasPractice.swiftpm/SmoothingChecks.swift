import UIKit
import PencilKit

enum SmoothingChecks {
    // Hand-authored Korean-shaped test trajectories, not recorded human input.
    static func fixture() -> PKDrawing {
        let paths: [[CGPoint]] = [
            [CGPoint(x:20,y:25),CGPoint(x:65,y:25),CGPoint(x:65,y:75)],
            [CGPoint(x:85,y:15),CGPoint(x:85,y:90)],
            [CGPoint(x:85,y:48),CGPoint(x:110,y:48)],
            [CGPoint(x:165,y:22),CGPoint(x:135,y:60)],
            [CGPoint(x:165,y:22),CGPoint(x:195,y:60)],
            [CGPoint(x:130,y:85),CGPoint(x:200,y:85)]
        ]
        return PKDrawing(strokes: paths.map { path in
            var points = [PKStrokePoint]()
            for segment in 1..<path.count {
                let a = path[segment-1], b = path[segment]
                for j in 0..<32 {
                    let t = CGFloat(j)/31, jitter = j == 0 || j == 31 ? 0 : sin(CGFloat(j)*1.6)*1.8
                    let dx = b.x-a.x, dy = b.y-a.y, length = max(1,hypot(dx,dy))
                    points.append(PKStrokePoint(location: CGPoint(x:a.x+dx*t-dy/length*jitter,y:a.y+dy*t+dx/length*jitter),
                        timeOffset: Double(points.count)*0.015, size: CGSize(width:2,height:2), opacity:1,force:0.5,azimuth:0,altitude:.pi/2))
                }
            }
            return PKStroke(ink: PKInk(.pen,color:.black),path:PKStrokePath(controlPoints:points,creationDate:Date(timeIntervalSince1970:0)))
        })
    }
    static func run() -> [String] {
        let original = fixture(), first = original.strokes[0]
        let zero = PencilSmoothing.apply(first,strength:0), half = PencilSmoothing.apply(first,strength:0.5), full = PencilSmoothing.apply(first,strength:1)
        var failures = [String]()
        func displacement(_ stroke: PKStroke) -> CGFloat {
            (0..<first.path.count).reduce(0) { $0 + hypot(stroke.path[$1].location.x-first.path[$1].location.x,stroke.path[$1].location.y-first.path[$1].location.y) }
        }
        if displacement(zero) != 0 { failures.append("보정 0% 원본 유지") }
        if displacement(half) < 1 || displacement(full) <= displacement(half)*1.5 { failures.append("보정률에 따른 실제 좌표 변화") }
        for stroke in [half,full] {
            if stroke.path.first?.location != first.path.first?.location || stroke.path.last?.location != first.path.last?.location { failures.append("획 끝 보존") }
            for i in 0..<first.path.count {
                if abs(stroke.path[i].timeOffset-first.path[i].timeOffset) > 0.001 || abs(stroke.path[i].force-first.path[i].force)>0.001 { failures.append("필압·시간 보존"); break }
            }
        }
        let dark = InkAppearance.adapt(original,dark:true)
        if dark.strokes[0].ink.color != UIColor.white { failures.append("다크모드 흰색") }
        if InkAppearance.adapt(dark,dark:false).strokes[0].ink.color != UIColor.black { failures.append("밝은모드 검정") }
        return failures
    }
    static func comparisonImage() -> UIImage {
        let source = fixture()
        return UIGraphicsImageRenderer(size:CGSize(width:720,height:420)).image { renderer in
            UIColor.white.setFill(); renderer.fill(CGRect(x:0,y:0,width:720,height:420))
            for (index,strength) in [CGFloat(0),0.5,1].enumerated() {
                let x = CGFloat(index)*240
                let text = "보정 \(Int(strength*100))%"
                (text as NSString).draw(at:CGPoint(x:x+20,y:20),withAttributes:[.font:UIFont.systemFont(ofSize:20,weight:.semibold),.foregroundColor:UIColor.black])
                let drawing = PKDrawing(strokes:source.strokes.map { PencilSmoothing.apply($0,strength:strength) })
                drawing.image(from:CGRect(x:0,y:0,width:220,height:110),scale:3).draw(in:CGRect(x:x+10,y:70,width:220,height:110))
                // Enlarged same stroke makes correction visible without inventing font recognition.
                drawing.image(from:CGRect(x:15,y:18,width:60,height:30),scale:5).draw(in:CGRect(x:x+10,y:220,width:220,height:110))
            }
            ("동일한 ‘가스’ 테스트 획 · 아래는 첫 획 확대 · 실제 펜슬 녹화가 아님" as NSString).draw(at:CGPoint(x:20,y:380),withAttributes:[.font:UIFont.systemFont(ofSize:14),.foregroundColor:UIColor.darkGray])
        }
    }
}
