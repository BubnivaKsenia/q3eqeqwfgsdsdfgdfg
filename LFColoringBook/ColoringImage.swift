

import UIKit
import MobileCoreServices

struct ColoringImage {
    let isOptimized:Bool
    
    let cgImage:CGImage
    
    let width:Int
    let height:Int
    
    
    let bytesPerPixel:Int
    let bytesPerRow:Int
    
    static let ciContext = CIContext()
    
    static let byteFormatter:ByteCountFormatter = ByteCountFormatter()
    
    var spatialSearch:SpatialHashMask
    private (set) var maskBytes:Int64 = 0
    private (set) var totalMasks:Int = 0
    
    init(from image:UIImage, optimized:Bool = true){
        guard let bwFilter = CIFilter(name: "CIPhotoEffectTonal")
        else {
            fatalError("There is no B&W filter!!!!!!!")
        }
        
        guard let posterizeFilter = CIFilter(name: "CIColorPosterize")
        else {
            fatalError("There is no Color Posterize filter!!!!!!!")
        }
        
        guard let colorInvert = CIFilter(name: "CIColorInvert")
        else {
            fatalError("There is no Color Invert filter!!!!!!!")
        }
        
        guard let secondColorInvert = CIFilter(name: "CIColorInvert")
        else {
            fatalError("There is no Color Invert filter!!!!!!!")
        }
        
        guard let maskToAlpha = CIFilter(name: "CIMaskToAlpha")
        else {
            fatalError("There is no Mask to Alpha filter!!!!!!!")
        }
        
        guard let ciimage = CIImage(image: image) else{
            fatalError("Couldn transform UIImage to CIImage!!!!!!")
        }
        
        self.isOptimized = optimized
        
        
        bwFilter.setValue(ciimage, forKey: kCIInputImageKey)
        
        posterizeFilter.setValue(bwFilter.outputImage!, forKey: kCIInputImageKey)
        posterizeFilter.setValue(NSNumber(integerLiteral: 2),
                                 forKey: "inputLevels")
        
        colorInvert.setValue(posterizeFilter.outputImage!, forKey: kCIInputImageKey)
        
        maskToAlpha.setValue(colorInvert.outputImage!, forKey: kCIInputImageKey)
        
        secondColorInvert.setValue(maskToAlpha.outputImage!, forKey: kCIInputImageKey)
        
        self.cgImage = ColoringImage.ciContext.createCGImage(secondColorInvert.outputImage!,
                                                             from: secondColorInvert.outputImage!.extent)!
        self.width = Int(image.size.width * image.scale)
        self.height = Int(image.size.height * image.scale)
        
        self.bytesPerPixel = 4
        self.bytesPerRow = self.cgImage.bytesPerRow
        
        self.spatialSearch = SpatialHashMask(xDivisions: 4, yDivisions: 4,
                                             boundingRect: CGRect(origin: .zero,
                                                                  size: CGSize(width: self.width, height: self.height)))
        
        if self.isOptimized{
            self.createMasks()
        }
        
    }
    
    private mutating func createMasks(){
        guard let data = self.cgImage.dataProvider?.data else {return}
        let dataLenght:Int = CFDataGetLength(data) as Int

        
        var bitmapCopy:[UInt8] = [UInt8].init(repeating: 0, count: dataLenght)
        
        CFDataGetBytes(data, CFRangeMake(0, dataLenght),
                       &bitmapCopy)
        
        let maskBytes:Int = 1 * self.width * self.height
        
        for y in 0..<self.height{
            for x in 0..<self.width{
                if bitmapCopy[(bytesPerRow * y ) + (bytesPerPixel * x) + 3] != 255{
                    autoreleasepool {
                        var maskBitmap:[UInt8] = [UInt8].init(repeating: 0,
                                                              count: maskBytes)
                        
                        let boundingRect = self.maskFillScanLine(x: x, y: y,
                                              bitmap: &bitmapCopy,
                                              mask: &maskBitmap)
                        if boundingRect.isNull {return}
                        
                        let maskData:CFData = Data(bytes: &maskBitmap,
                                                   count: maskBitmap.count * MemoryLayout<UInt8>.size) as CFData
                        
                        guard let provider:CGDataProvider = CGDataProvider(data: maskData) else {return}
                        
                        guard let maskImage = CGImage(width: self.width,
                                       height: self.height,
                                       bitsPerComponent: 8,
                                       bitsPerPixel: 8,
                                       bytesPerRow: self.width,
                                       space: CGColorSpaceCreateDeviceGray(),
                                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                                       provider: provider, decode: nil,
                                       shouldInterpolate: true, intent: .defaultIntent)?.cropping(to: boundingRect)
                        else{return}
                        
                        let pngData:NSMutableData = NSMutableData()
                        
                        if let dest = CGImageDestinationCreateWithData(pngData,
                                                                       kUTTypePNG,
                                                                       1, nil){
                            CGImageDestinationAddImage(dest,
                                                       maskImage, nil)
                            if CGImageDestinationFinalize(dest){
                                
                                let newMask = Mask(boundingRect: boundingRect,
                                                   data: pngData)
                                
                                self.spatialSearch.add(newMask)
                                let originalBytes = ColoringImage.byteFormatter.string(fromByteCount: Int64(maskBitmap.count))
                                let pngBytes = ColoringImage.byteFormatter.string(fromByteCount: Int64(pngData.count))
                                
                                NSLog("Created Mask, compressed from \(originalBytes) to \(pngBytes)")
                                
                                self.maskBytes += Int64(pngData.count)
                                self.totalMasks += 1
                            }
                        }
                    }
                }
            }
        }
        
        let totalSize = ColoringImage.byteFormatter.string(fromByteCount: self.maskBytes)
        NSLog("Created \(totalMasks) masks with a size of \(totalSize)")
    }
    
    func getFillMaskAt(x:Int, y:Int)->(CGRect, CGImage?){
        if self.isOptimized{
            return self.getFillMaskOptimizedAt(x: x, y: y)
        }
        else{
            return self.getFillMaskNotOptimizedAt(x: x, y: y)
        }
    }
    
    private func getFillMaskNotOptimizedAt(x:Int, y:Int)->(CGRect, CGImage?){
        guard let data = self.cgImage.dataProvider?.data else {return (.null,nil)}
        
        guard var bitmapPointer = CFDataGetBytePtr(data) else {return (.null,nil)}
        
        let maskBytes:Int = 1 * self.width * self.height
        
        var maskBitmap:[UInt8] = [UInt8].init(repeating: 0,
                                              count: maskBytes)
        
        let start = ProcessInfo.processInfo.systemUptime
        if CommandLine.arguments.contains("-FloodFillRecursive"){
            self.fillFloodRecursive(x: x, y: y, bitmap: &bitmapPointer, mask: &maskBitmap)
        }
        else if CommandLine.arguments.contains("-FloodFillNonRecursive"){
            self.fillFloodNonRecursive(x: x, y: y, bitmap: &bitmapPointer, mask: &maskBitmap)
        }
        else{
            self.fillFloodScanLine(x: x, y: y, bitmap: &bitmapPointer, mask: &maskBitmap)
        }
        
        let dif = ProcessInfo.processInfo.systemUptime - start
        NSLog("Took \(dif) seconds to create mask")
    
        let maskData:CFData = Data(bytes: &maskBitmap,
                                   count: maskBitmap.count * MemoryLayout<UInt8>.size) as CFData
        
        guard let provider:CGDataProvider = CGDataProvider(data: maskData) else {return (.null,nil)}
        
        let scale = UIScreen.main.scale
        return (CGRect(x: 0, y: 0,
                       width: self.width / Int(scale),
                       height: self.height / Int(scale))
                ,CGImage(width: self.width,
                       height: self.height,
                       bitsPerComponent: 8,
                       bitsPerPixel: 8,
                       bytesPerRow: self.width,
                       space: CGColorSpaceCreateDeviceGray(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                       provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent))
    }
    
    private func getFillMaskOptimizedAt(x:Int, y:Int)->(CGRect, CGImage?){
        guard let data = self.cgImage.dataProvider?.data else {return (.null,nil)}
        
        guard let bitmapPointer = CFDataGetBytePtr(data) else {return (.null,nil)}
        
        if bitmapPointer[(self.bytesPerRow * y) + (bytesPerPixel * x) + 3] == 255{
            print("Touched black line")
            return (.null,nil)
        }
        
        let start = ProcessInfo.processInfo.systemUptime
        
        defer {
            let dif = ProcessInfo.processInfo.systemUptime - start
            NSLog("Took \(dif) seconds to find correct mask")
        }
        
        guard var masks = spatialSearch.masksAt(CGPoint(x: x, y: y)) else {return (.null,nil)}
        
        masks = masks.compactMap{
            if $0.contains(CGPoint(x: x, y: y)){
                return $0
            }
            else{
                return nil
            }
        }
        
        masks = masks.sorted(by: { (mask0, mask1) -> Bool in
            return mask0.squaredDistanceFromOriginTo(CGPoint(x: x, y: y)) <
            mask1.squaredDistanceFromOriginTo(CGPoint(x: x, y: y))
        })
        
        NSLog("\(masks.count) masks detected")
        
        for mask in masks{
            var returnRect:CGRect? = nil
            var returnMask:CGImage? = nil
            autoreleasepool {
                guard let dataProvider = CGDataProvider(data: mask.pngData as CFData)
                else {return}
                
                guard let maskImage = CGImage(pngDataProviderSource: dataProvider,
                                              decode: nil,
                                              shouldInterpolate: true,
                                              intent: .defaultIntent) else {return}
                
                guard let bitmapData = maskImage.dataProvider?.data else {return}
                
                guard let bitmapPointer = CFDataGetBytePtr(bitmapData) else {return}
                
                let translatedX = x - Int(mask.boundingRect.origin.x)
                let translatedY = y - Int(mask.boundingRect.origin.y)
                
                let index = (maskImage.bytesPerRow * translatedY) + translatedX
                if bitmapPointer[index] == 255{
                    returnRect = mask.boundingRect
                    returnMask = maskImage
                }
            }
            
            if let boundingRect = returnRect, let imageMask = returnMask{
                let scale = UIScreen.main.scale
                return(CGRect(x: boundingRect.origin.x / scale ,
                              y: boundingRect.origin.y / scale,
                              width: boundingRect.width / scale,
                              height: boundingRect.height / scale),
                       imageMask)
            }
        }
        
        let scale = UIScreen.main.scale
        return (CGRect(x: 0, y: 0,
                       width: self.width / Int(scale),
                       height: self.height / Int(scale)),nil)
    }
    
    func fillFloodRecursive(x:Int, y:Int, bitmap: inout UnsafePointer<UInt8>, mask: inout [UInt8]){
        
        if x < 0 || x >= self.width ||
            y < 0 || y >= self.height{
            return
        }
        
        let pixelStart:Int = (self.bytesPerRow * y) + (bytesPerPixel * x)
        let originalR:UInt8 = bitmap[pixelStart]
        let originalG:UInt8 = bitmap[pixelStart + 1]
        let originalB:UInt8 = bitmap[pixelStart + 2]
        let originalA:UInt8 = bitmap[pixelStart + 3]
        
        let maskIndex = (self.width * ((self.height - 1) - y)) + (x)
        let maskPixel:UInt8 = mask[maskIndex]
        
        if originalR == 0 && originalG == 0 && originalB == 0 && originalA == 255{
            return
        }
        
        if maskPixel == 255{
            return
        }
        
        mask[maskIndex] = 255
        
        
        self.fillFloodRecursive(x: x - 1, y: y, bitmap: &bitmap, mask: &mask)
        self.fillFloodRecursive(x: x + 1, y: y, bitmap: &bitmap, mask: &mask)
        self.fillFloodRecursive(x: x, y: y - 1, bitmap: &bitmap, mask: &mask)
        self.fillFloodRecursive(x: x, y: y + 1, bitmap: &bitmap, mask: &mask)
    }
    
    func fillFloodNonRecursive(x:Int, y:Int, bitmap: inout UnsafePointer<UInt8>, mask: inout [UInt8]){
        
        var positions = Queue<PixelPosition>()
        
        positions.enqueue(PixelPosition(x: x, y: y))
        
        while !positions.isEmpty {
            
            guard let position = positions.dequeue() else {break}
            
            if position.x < 0 || position.x >= self.width ||
                position.y < 0 || position.y >= self.height{
                continue
            }
            
            let pixelStart:Int = (self.bytesPerRow * position.y) + (bytesPerPixel * position.x)
            let originalR:UInt8 = bitmap[pixelStart]
            let originalG:UInt8 = bitmap[pixelStart + 1]
            let originalB:UInt8 = bitmap[pixelStart + 2]
            let originalA:UInt8 = bitmap[pixelStart + 3]
            
            let maskIndex = (self.width * ((self.height - 1) - position.y)) + (position.x)
            let maskPixel:UInt8 = mask[maskIndex]
            
            if originalR == 0 && originalG == 0 && originalB == 0 && originalA == 255{
                continue
            }
            
            if maskPixel == 255{
                continue
            }
            
            mask[maskIndex] = 255
            
            positions.enqueue(PixelPosition(x: position.x - 1, y: position.y))
            positions.enqueue(PixelPosition(x: position.x + 1, y: position.y))
            positions.enqueue(PixelPosition(x: position.x, y: position.y - 1))
            positions.enqueue(PixelPosition(x: position.x, y: position.y + 1))
            
        }
        
    }
    
    func fillFloodScanLine(x:Int, y:Int, bitmap: inout UnsafePointer<UInt8>, mask: inout [UInt8]){
        
        var x1:Int = 0
        var spanAbove:Bool = false
        var spanBelow:Bool = false
        
        var stack:Stack<PixelPosition> = Stack<PixelPosition>()
        
        stack.push(PixelPosition(x: x, y: y))
        while let position = stack.pop() {
            x1 = position.x
            
            while( x1 >= 0 &&
                    bitmap[(bytesPerRow * position.y ) + (bytesPerPixel * x1) + 3] != 255 &&
                    mask[(self.width * ((self.height - 1) - position.y)) + x1] != 255){
                x1 -= 1
            }
            x1 += 1
            
            spanAbove = false
            spanBelow = false
            
            while ( x1 < self.width &&
                        bitmap[(bytesPerRow * position.y ) + (bytesPerPixel * x1) + 3] != 255 &&
                        mask[(self.width * ((self.height - 1) - position.y)) + x1] != 255){
                
                let maskIndex = (self.width * ((self.height - 1) - position.y)) + (x1)
                mask[maskIndex] = 255
                
                if !spanAbove && position.y > 0 &&
                    bitmap[self.bytesPerRow * (position.y - 1) + (bytesPerPixel * x1) + 3] != 255
                   && mask[(self.width * ((self.height - 1) - (position.y - 1))) + x1] != 255{
                    stack.push(PixelPosition(x: x1, y: position.y - 1))
                    spanAbove = true
                }
                else if spanAbove && position.y > 0 &&
                bitmap[self.bytesPerRow * (position.y - 1) + (bytesPerPixel * x1) + 3] == 255
                {
                    spanAbove = false
                }
                
                if !spanBelow && position.y < (self.height - 1) &&
                    bitmap[self.bytesPerRow * (position.y + 1) + (bytesPerPixel * x1) + 3] != 255
                    && mask[(self.width * ((self.height - 1) - (position.y + 1))) + x1] != 255{
                    stack.push(PixelPosition(x: x1, y: position.y + 1))
                    spanBelow = true
                }
                else if spanBelow && position.y < (self.height - 1) &&
                    bitmap[self.bytesPerRow * (position.y + 1) + (bytesPerPixel * x1) + 3] == 255{
                    spanBelow = false
                }
                
                x1 += 1
            }
        }
    }
    
    func maskFillScanLine(x:Int, y:Int, bitmap: inout [UInt8], mask: inout [UInt8])->CGRect{
        
        var x1:Int = 0
        var spanAbove:Bool = false
        var spanBelow:Bool = false
        
        var minX:Int? = nil
        var minY:Int? = nil
        var maxX:Int? = nil
        var maxY:Int? = nil
        
        var stack:Stack<PixelPosition> = Stack<PixelPosition>()
        
        stack.push(PixelPosition(x: x, y: y))
        while let position = stack.pop() {
            x1 = position.x
            
            while( x1 >= 0 &&
                    bitmap[(bytesPerRow * position.y ) + (bytesPerPixel * x1) + 3] != 255){
                x1 -= 1
            }
            x1 += 1
            
            spanAbove = false
            spanBelow = false
            
            while ( x1 < self.width &&
                        bitmap[(bytesPerRow * position.y ) + (bytesPerPixel * x1) + 3] != 255){
                
                let maskIndex = (self.width *  position.y) + (x1)
                mask[maskIndex] = 255
                bitmap[(bytesPerRow * position.y ) + (bytesPerPixel * x1) + 3] = 255
                
                minX = minX == nil ? x1:min(minX!,x1)
                minY = minY == nil ? position.y:min(minY!,position.y)
                maxX = maxX == nil ? x1:max(maxX!,x1)
                maxY = maxY == nil ? position.y:max(maxY!,position.y)
                
                if !spanAbove && position.y > 0 &&
                    bitmap[self.bytesPerRow * (position.y - 1) + (bytesPerPixel * x1) + 3] != 255{
                    stack.push(PixelPosition(x: x1, y: position.y - 1))
                    spanAbove = true
                }
                else if spanAbove && position.y > 0 &&
                bitmap[self.bytesPerRow * (position.y - 1) + (bytesPerPixel * x1) + 3] == 255
                {
                    spanAbove = false
                }
                
                if !spanBelow && position.y < (self.height - 1) &&
                    bitmap[self.bytesPerRow * (position.y + 1) + (bytesPerPixel * x1) + 3] != 255{
                    stack.push(PixelPosition(x: x1, y: position.y + 1))
                    spanBelow = true
                }
                else if spanBelow && position.y < (self.height - 1) &&
                    bitmap[self.bytesPerRow * (position.y + 1) + (bytesPerPixel * x1) + 3] == 255{
                    spanBelow = false
                }
                
                x1 += 1
            }
        }
        
        if let maxX = maxX, let maxY = maxY, let minX = minX, let minY = minY{
            return CGRect(x: minX,
                          y: minY,
                          width: (maxX - minX) + 1,
                          height: (maxY - minY) + 1)
        }
        else{
            return .null
        }
    }
}

struct PixelPosition {
    let x:Int
    let y:Int
}
