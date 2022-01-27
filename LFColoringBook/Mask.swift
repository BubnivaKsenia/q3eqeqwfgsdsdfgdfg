
import UIKit
import simd

class Mask{
    let boundingRect:CGRect
    let pngData:NSMutableData
    
    init(boundingRect:CGRect, data:NSMutableData) {
        self.boundingRect = boundingRect
        self.pngData = data
    }
    
    func contains(_ point:CGPoint)->Bool{
        return self.boundingRect.contains(point)
    }
    
    func squaredDistanceFromOriginTo(_ point:CGPoint)->Float{
        let origin:vector_float2 = vector_float2(Float(self.boundingRect.origin.x),
                                                 Float(self.boundingRect.origin.y))
        
        let simdPoint:vector_float2 = vector_float2(Float(point.x), Float(point.y))
        
        return simd_distance_squared(origin, simdPoint)
    }
}
