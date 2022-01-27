

import UIKit
import MobileCoreServices

protocol ColoringBookViewDelegate:class {
    func viewWillStartDrawing()
    func viewDidEndDrawing()
}

class ColoringBookView: UIView {

    private (set) var pixelSize:CGSize!
    
    private (set) var strokes:[Stroke] = [Stroke](){
        didSet{
            self.reduceHistory()
        }
    }
    private (set) var redoStrokes:[Stroke] = [Stroke]()
    
    private (set) var activeStroke:Stroke? = nil
    private var frozenContext:CGContext!
    
    private var coloringImage:ColoringImage!
    private var savedImage:NSMutableData? = nil
    
    private var generatingMask:Bool = false
    private var coloringLayer:CALayer!
    
    public var currentColor:UIColor = .black
    public var currentWidth:CGFloat = 5.0
    
    
    private let cancellationTimeInterval = TimeInterval(0.1)
    private let pencilWaitTimeInterval = TimeInterval(0.042)
    private var initialTimestamp: TimeInterval?
    
    private var pointAccumulator:[CGPoint] = [CGPoint]()
    private var touchIsPencil:Bool = false
    
    
    public var canRedo:Bool{
        return !redoStrokes.isEmpty
    }
    
    public var canUndo:Bool{
        return !strokes.isEmpty
    }
    
    public weak var delegate:ColoringBookViewDelegate? = nil
    
    
    override var intrinsicContentSize: CGSize{
        return CGSize(width: pixelSize.width / UIScreen.main.scale,
                      height: pixelSize.height / UIScreen.main.scale)
    }
    
    init(coloringImage:ColoringImage){
        super.init(frame: .zero)
        
        self.isOpaque = false
        self.backgroundColor = .white
        
        self.coloringImage = coloringImage
        self.pixelSize = CGSize(width: coloringImage.width,
                                height: coloringImage.height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        
        self.frozenContext = CGContext(data: nil,
                                       width: Int(self.pixelSize.width),
                                       height: Int(self.pixelSize.height),
                                       bitsPerComponent: 8,
                                       bytesPerRow: 0,
                                       space: colorSpace,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        let transform = CGAffineTransform.init(scaleX:UIScreen.main.scale, y: UIScreen.main.scale)
        self.frozenContext.concatenate(transform)
        
        self.frozenContext.setLineCap(.round)
        self.frozenContext.setLineJoin(.round)
        
        
        self.coloringLayer = CALayer()
        coloringLayer.frame = CGRect(origin: .zero,
                                            size: CGSize(width: pixelSize.width / UIScreen.main.scale,
                                                         height: pixelSize.height / UIScreen.main.scale))
        coloringLayer.contents = self.coloringImage.cgImage
        self.layer.addSublayer(coloringLayer)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func draw(_ rect: CGRect) {
        guard let currentContext = UIGraphicsGetCurrentContext() else {return}
        
        if let frozenImage = frozenContext.makeImage(){
            currentContext.draw(frozenImage, in: bounds)
        }
        
        if generatingMask{
            currentContext.setLineCap(.round)
            currentContext.setLineJoin(.round)
            activeStroke?.drawInContext(currentContext)
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.viewWillStartDrawing()
        
        self.redoStrokes.removeAll()
        
        activeStroke = Stroke(color: self.currentColor,
                              lineWidth: self.currentWidth)
        
        let firstLocation = touches.first!.location(in: self)
        
        self.initialTimestamp = ProcessInfo.processInfo.systemUptime
        self.pointAccumulator = []
        self.touchIsPencil = touches.first!.type == .pencil
        self.generatingMask = true
        let strokeID = activeStroke?.id
        DispatchQueue.global(qos: .background).async {
             let (clipRect, mask) = self.coloringImage.getFillMaskAt(x: Int(firstLocation.x * UIScreen.main.scale),
                                                           y: Int(firstLocation.y * UIScreen.main.scale))
            
            self.generatingMask = false
            if let mask = mask{
                if self.activeStroke?.id == strokeID{
                    DispatchQueue.main.async {
                        self.setNeedsDisplay(self.bounds)
                        self.setClip(clipRect, maskImage: mask)
                    }
                }
            }
            else{
                if self.activeStroke?.id == strokeID{
                    DispatchQueue.main.async {
                        self.setNeedsDisplay(self.bounds)
                        self.activeStroke = nil
                    }
                }
            }
            
        }
        
        if let coalescedTouches = event?.coalescedTouches(for: touches.first!){
            for touch in coalescedTouches{
                pointAccumulator.append(touch.location(in: self))
            }
        }
        
        drawActiveFrozenContext()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let coalescedTouches = event?.coalescedTouches(for: touches.first!){
            for touch in coalescedTouches{
                pointAccumulator.append(touch.location(in: self))
            }
        }
        
        drawActiveFrozenContext()
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeStroke = nil
        frozenContext.resetClip()
        
        pointAccumulator = []
        initialTimestamp = nil
        
        
        delegate?.viewDidEndDrawing()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if let activeStroke = self.activeStroke{
            strokes.append(activeStroke)
        }
        
        activeStroke = nil
        frozenContext.resetClip()
        
        pointAccumulator = []
        initialTimestamp = nil
        
        delegate?.viewDidEndDrawing()
    }
    
    private func drawActiveFrozenContext(){
        
        if let initialTimeStamp = self.initialTimestamp{
            let dif = ProcessInfo.processInfo.systemUptime - initialTimeStamp
            
            if touchIsPencil && dif < self.pencilWaitTimeInterval ||
                !touchIsPencil && dif < self.cancellationTimeInterval{
                return
            }
            initialTimestamp = nil
        }
        
        for point in pointAccumulator{
            activeStroke?.addPoint(point)
        }
        
        pointAccumulator = []
        
        
        if generatingMask{
            if let strokeRect = activeStroke?.strokeRect{
                self.setNeedsDisplay(strokeRect)
            }
            
        }
        else{
            if let updateRect = activeStroke?.drawSinceLastIn(frozenContext){
                self.setNeedsDisplay(updateRect)
            }
        }
    }
    
    public func undo(){
        if let last = self.strokes.popLast(){
            self.redoStrokes.append(last)
            redrawInFrozenContext()
        }
    }
    
    public func redo(){
        if let last = self.redoStrokes.popLast(){
            self.strokes.append(last)
            redrawInFrozenContext()
        }
    }
    
    public func clear(){
        self.strokes.removeAll()
        self.savedImage = nil
        redrawInFrozenContext()
    }
    
    public func hideColoringLayer(){
        self.coloringLayer.isHidden.toggle()
    }
    
    private func redrawInFrozenContext(updateScreen:Bool = true){
        let begin = ProcessInfo.processInfo.systemUptime
        
        frozenContext.clear(self.bounds)
        
        if let savedImageData = self.savedImage,
           let dataProvider = CGDataProvider(data: savedImageData as CFData),
           let startImage = CGImage(pngDataProviderSource: dataProvider,
                                    decode: nil,
                                    shouldInterpolate: true,
                                    intent: .defaultIntent){
            frozenContext.draw(startImage, in: self.bounds)
        }
        
        for stroke in strokes{
            if let firstPoint = stroke.points.first{
                let (clipRect,mask) = self.coloringImage.getFillMaskAt(x: Int(firstPoint.x * UIScreen.main.scale),
                                                               y: Int(firstPoint.y * UIScreen.main.scale))
                if let mask = mask{
                    self.setClip(clipRect, maskImage: mask)
                }
                else{
                    continue
                }
            }
            stroke.drawInContext(frozenContext)
            frozenContext.resetClip()
        }
        
        let dif = ProcessInfo.processInfo.systemUptime - begin
        NSLog("Took \(dif) seconds to redraw \(self.strokes.count) strokes")
        
        if updateScreen{
            self.setNeedsDisplay()
        }
    }
    
    private func setClip(_ rect:CGRect, maskImage:CGImage){

        if coloringImage.isOptimized{
            self.frozenContext.translateBy(x: 0, y: rect.origin.y + rect.height)
            self.frozenContext.scaleBy(x: 1.0, y: -1.0)
            self.frozenContext.clip(to: CGRect(x: rect.origin.x,
                                               y: 0,
                                               width: rect.width,
                                               height: rect.height),
                                    mask: maskImage)
            
            self.frozenContext.scaleBy(x: 1.0, y: -1.0)
            self.frozenContext.translateBy(x: 0, y: -(rect.origin.y + rect.height))
        }
        else{
            self.frozenContext.clip(to: rect,
                                    mask: maskImage)
        }


    }
    
    private func reduceHistory(){
        guard (coloringImage.isOptimized && strokes.count > 100) ||
                (!coloringImage.isOptimized && strokes.count > 8)else{
            return
        }
        
        if coloringImage.isOptimized{
            
            guard let currentImage = frozenContext.makeImage() else {return}
            
            let numberToKeep:Int = 30
            let indexStart:Int = self.strokes.count - numberToKeep
            let strokesToKeep:[Stroke] = Array(self.strokes[indexStart...(self.strokes.count - 1)])
            self.strokes.removeLast(numberToKeep)
            
            self.redrawInFrozenContext(updateScreen: false)
            
            guard let imageToSave = frozenContext.makeImage() else {return}
            self.savedImage = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(self.savedImage!,
                                                           kUTTypePNG,
                                                           1, nil){
                CGImageDestinationAddImage(dest,
                                           imageToSave, nil)
                if CGImageDestinationFinalize(dest){
                    self.strokes.removeAll()
                }
            }
            
            self.strokes = strokesToKeep
            
            frozenContext.draw(currentImage, in: self.bounds)
        }
        else{
            guard let imageToSave = frozenContext.makeImage() else {return}
            self.savedImage = NSMutableData()
            if let dest = CGImageDestinationCreateWithData(self.savedImage!,
                                                           kUTTypePNG,
                                                           1, nil){
                CGImageDestinationAddImage(dest,
                                           imageToSave, nil)
                if CGImageDestinationFinalize(dest){
                    self.strokes.removeAll()
                }
            }
        }
    }
    
    
}
