

import UIKit
import simd

struct Stroke {
    private static var currentID:UInt64 = 0
    private (set) var points:[CGPoint] = [CGPoint]()
    private (set) var strokeRect:CGRect = .null
    
    let lineWidth:CGFloat
    let color:UIColor
    let id:UInt64
    
    private (set) var lastDrawnPoint:Int = -1
    
    init(color:UIColor = .black, lineWidth:CGFloat = 5.0){
        self.color = color
        self.lineWidth = lineWidth
        
        self.id = Stroke.currentID
        Stroke.currentID += 1
    }
    
    mutating func addPoint(_ point:CGPoint){
        if let lastPoint = self.points.last{
            let lastSimd = simd_float2(x: Float(lastPoint.x), y: Float(lastPoint.y))
            let newSimd = simd_float2(x:Float(point.x), y:Float(point.y))
            if simd_distance(lastSimd, newSimd) < 1.0{
                return
            }
        }
        
        let pointRect = CGRect(x: point.x - self.lineWidth / 2.0 - 4.0,
                               y: point.y - self.lineWidth / 2.0 - 4.0,
                               width: self.lineWidth + 4.0,
                               height: self.lineWidth + 4.0)
        strokeRect = strokeRect.union(pointRect)
        self.points.append(point)
    }
    
    func drawInContext(_ context:CGContext){
        if CommandLine.arguments.contains("-debugStrokes"){
            context.setFillColor(UIColor.red.cgColor)
            for point in self.points{
                context.fillEllipse(in: CGRect(x: point.x - 1.0,
                                               y: point.y - 1.0,
                                               width: 2.0, height: 2.0))
            }
        }
        else{
            context.setStrokeColor(self.color.cgColor)
            context.setLineWidth(self.lineWidth)
            context.addLines(between: self.points)
            context.strokePath()
        }

    }
    
    mutating func drawSinceLastIn( _ context:CGContext)->CGRect?{
        guard !self.points.isEmpty else {return nil}
        if self.lastDrawnPoint == (self.points.count - 1) {return nil}
        
        let arrayStart:Int = lastDrawnPoint >= 0 ? lastDrawnPoint:0
        let arrayEnd:Int = self.points.count - 1
        self.lastDrawnPoint = arrayEnd

        var updateRect:CGRect = .null
        var linePoints:[CGPoint] = [CGPoint]()
        
        for point in self.points[arrayStart...arrayEnd]{
            linePoints.append(point)
            
            let pointRect = CGRect(x: point.x - self.lineWidth / 2.0 - 4.0,
                                   y: point.y - self.lineWidth / 2.0 - 4.0,
                                   width: self.lineWidth + 4.0,
                                   height: self.lineWidth + 4.0)
            updateRect = updateRect.union(pointRect)
        }
            
        if CommandLine.arguments.contains("-debugStrokes"){
            context.setFillColor(UIColor.red.cgColor)
            for point in linePoints{
                context.fillEllipse(in: CGRect(x: point.x - 1.0,
                                               y: point.y - 1.0,
                                               width: 2.0, height: 2.0))
            }
        }
        else{
            context.setStrokeColor(self.color.cgColor)
            context.setLineWidth(self.lineWidth)
            context.addLines(between: linePoints)
            context.strokePath()
        }
        
        return updateRect
    }
}
