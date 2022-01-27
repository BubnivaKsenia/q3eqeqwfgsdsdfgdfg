
import UIKit
import simd
#if canImport(PhotosUI)
import PhotosUI
#endif

class ViewController: UIViewController {
    @IBOutlet var scrollView: UIScrollView!
    @IBOutlet var lineWidthSlider: UISlider!
    @IBOutlet var lastColor: UIButton!
    @IBOutlet var tools: [UIView]!
    @IBOutlet var undoButton: UIButton!
    @IBOutlet var redoButton: UIButton!
    
    var coloringBookView:ColoringBookView? = nil
    private var horizontalConstrains:[NSLayoutConstraint]? = nil
    private var verticalConstrains:[NSLayoutConstraint]? = nil
    
    private var toolsHiddenState:Bool = false
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.scrollView.delegate = self
        self.scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        
        if #available(iOS 14.0, *){
            self.lastColor.backgroundColor = .white
            self.lastColor.setTitle("*", for: .normal)
            self.lastColor.tag = 999
        }
        
        let (image,optimized) = self.retrieveSavedImage()
        if let image = image ?? UIImage(named:"mandala1.png"){
           let optimized = optimized ?? true
            self.createColoringBookView(with: image, optimized: optimized)
        }
        
    }


    @IBAction func createNewDrawing(_ sender: Any) {
        let alert = UIAlertController()
        alert.popoverPresentationController?.sourceView = sender as? UIView
        
        let action1 = UIAlertAction(title: "Test Image 1", style: .default) { (action) in
            DispatchQueue.main.async {
                if let testImage = UIImage(named: "mandala1.png"){
                    self.askOptimizationFor(testImage)
                }
            }
        }
        
        let action2 = UIAlertAction(title: "Test Image 2", style: .default) { (action) in
            DispatchQueue.main.async {
                if let testImage = UIImage(named: "mandala2.png"){
                    self.askOptimizationFor(testImage)
                }
            }
            
        }
        
        let action3 = UIAlertAction(title: "Test Image 3", style: .default) { (action) in
            DispatchQueue.main.async {
                if let testImage = UIImage(named: "testImage3.jpg"){
                    self.askOptimizationFor(testImage)
                }
            }
        }
        
        let action4 = UIAlertAction(title: "Custom Image", style: .default) { (action) in
            DispatchQueue.main.async {
                self.openImagePicker()
            }
        }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alert.addAction(action1)
        alert.addAction(action2)
        alert.addAction(action3)
        alert.addAction(action4)
        alert.addAction(cancel)
        
        self.present(alert, animated: true)
        
    }
    
    private func askOptimizationFor(_ image:UIImage){
        let alert = UIAlertController(title: nil, message: nil, preferredStyle: .alert)

        
        let action1 = UIAlertAction(title: "Optimized (+ Creation Time, + Performance)", style: .default) { (action) in
            DispatchQueue.main.async {
                self.createColoringBookView(with: image, optimized: true)
            }
        }
        
        let action2 = UIAlertAction(title: "Not Optimized (- Creation Time, - Performance)", style: .default) { (action) in
            DispatchQueue.main.async {
            self.createColoringBookView(with: image, optimized: false)
                }
            }
        
        let cancel = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
        
        alert.addAction(action1)
        alert.addAction(action2)
        alert.addAction(cancel)
        
        self.present(alert, animated: true)
        
    }
    
    private func openImagePicker(){
        if #available(iOS 14, *){
            var configuration = PHPickerConfiguration()
            configuration.selectionLimit = 1
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            self.present(picker, animated: true)
            
        }
        else{
            let picker = UIImagePickerController()
            picker.delegate = self
            picker.sourceType = .photoLibrary
            self.present(picker, animated: true)
        }
    }
    
    private func createColoringBookView(with image:UIImage, optimized:Bool = true){
        //Save the last stroke color we used, if none is found choose red
        let lastColor:UIColor = self.coloringBookView?.currentColor ?? .red
        self.coloringBookView?.removeFromSuperview()
        
        let messageView = UIView()
        messageView.translatesAutoresizingMaskIntoConstraints = false
        messageView.backgroundColor = .white
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .fillEqually
        
        let label = UILabel()
        label.text = "Currently proccesing your image, please wait"
        label.textAlignment = .center
        
        let indicator = UIActivityIndicatorView()
        indicator.startAnimating()
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(indicator)
        
        stack.fixInView(messageView)
        
        UIView.transition(with: self.view,
                          duration: 0.3,
                          options: .transitionCrossDissolve) {
            messageView.fixInView(self.view)
        }
        
        
        DispatchQueue.global(qos: .background).async{
            let coloringImage = ColoringImage(from: image, optimized: optimized)
            
            DispatchQueue.main.async{
                messageView.removeFromSuperview()
                self.coloringBookView = ColoringBookView(coloringImage: coloringImage)
                
                self.coloringBookView?.translatesAutoresizingMaskIntoConstraints = false
                self.scrollView.addSubview(self.coloringBookView!)
                let topC = self.coloringBookView?.topAnchor.constraint(equalTo: self.scrollView.topAnchor)
                let bottomC = self.coloringBookView?.bottomAnchor.constraint(equalTo: self.scrollView.bottomAnchor)
                let leadingC = self.coloringBookView?.leadingAnchor.constraint(equalTo: self.scrollView.leadingAnchor)
                let trailingC = self.coloringBookView?.trailingAnchor.constraint(equalTo: self.scrollView.trailingAnchor)
                
                topC!.isActive = true
                bottomC!.isActive = true
                leadingC!.isActive = true
                trailingC!.isActive = true
                
                self.horizontalConstrains = [leadingC!,trailingC!]
                self.verticalConstrains = [topC!,bottomC!]
                
                self.coloringBookView?.currentColor = lastColor
                self.coloringBookView?.currentWidth = CGFloat(simd_mix(1.0, 40.0, self.lineWidthSlider.value))
                
                self.coloringBookView?.delegate = self
                self.saveImage(image, optimized: optimized)
                self.checkColoringBookState()
            }
        }
    }
    
    @IBAction func colorPressed(_ sender: UIButton) {
        if sender.tag == 999{
            if #available(iOS 14, *){
                let colorPicker = UIColorPickerViewController()
                colorPicker.delegate = self
                colorPicker.selectedColor = self.coloringBookView?.currentColor ?? .white
                self.present(colorPicker, animated: true)
            }
            return
        }
        
        if let color = sender.backgroundColor{
            coloringBookView?.currentColor = color
        }
    }
    
    
    @IBAction func sliderChanged(_ sender: Any) {
        coloringBookView?.currentWidth = CGFloat(simd_mix(1.0, 40.0, lineWidthSlider.value))
    }
    
    @IBAction func clearDrawing(_ sender: Any) {
        self.coloringBookView?.clear()
        self.checkColoringBookState()
    }
    
    @IBAction func undo(_ sender: Any) {
        self.coloringBookView?.undo()
        self.checkColoringBookState()
    }
    
    @IBAction func redo(_ sender: Any) {
        self.coloringBookView?.redo()
        self.checkColoringBookState()
    }
    
    @IBAction func toggleImageLayer(_ sender: Any) {
        self.coloringBookView?.hideColoringLayer()
    }
    
    
    
    @IBAction func hideTools(_ sender: Any) {
        for tool in tools{
            tool.isHidden = !tool.isHidden
        }
    }
    
    private func saveImage(_ image:UIImage, optimized:Bool){
        guard let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("savedImage.png")
        else {return}
        
        guard let pngData = image.pngData() else {return}
        
        do{
           try pngData.write(to: url)
        }
        catch{
            NSLog("Image couldn't be saved to disk!!!!!!")
        }
        
        UserDefaults.standard.set(optimized, forKey: "optimized")
        
        
    }
    
    private func retrieveSavedImage()->(UIImage?, Bool?){
        let image:UIImage?
        let optimized:Bool?
        if let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("savedImage.png"){
            image = UIImage(contentsOfFile: url.path)
        }
        else{
            image = nil
        }
        
        optimized = UserDefaults.standard.value(forKey: "optimized") as? Bool
        
        return (image,optimized)
        
    }
    
    private func checkColoringBookState(){
        self.undoButton.isEnabled = coloringBookView?.canUndo ?? false
        self.redoButton.isEnabled = coloringBookView?.canRedo ?? false
    }
}

extension ViewController:UIScrollViewDelegate{
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return self.coloringBookView
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        centerColoringView()
    }
    
    func centerColoringView(){
        let offsetX = max(0,(scrollView.bounds.width - scrollView.contentSize.width) / 2.0)
        let offsetY = max(0,(scrollView.bounds.height - scrollView.contentSize.height) / 2.0)
        
        self.horizontalConstrains?.forEach{
            $0.constant = offsetX
        }
        
        self.verticalConstrains?.forEach{
            $0.constant = offsetY
        }
    }
}

extension ViewController:UIColorPickerViewControllerDelegate{
    @available(iOS 14.0, *)
    func colorPickerViewControllerDidSelectColor(_ viewController: UIColorPickerViewController) {
        self.coloringBookView?.currentColor = viewController.selectedColor
    }
}

extension ViewController:UIImagePickerControllerDelegate & UINavigationControllerDelegate{
    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(animated: true)
        
    }
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image:UIImage = info[.originalImage] as? UIImage ??
                                info[.editedImage] as? UIImage{
            DispatchQueue.main.async {
                self.askOptimizationFor(image)
            }
        }
        dismiss(animated: true)
    }
}

extension ViewController:PHPickerViewControllerDelegate{
    @available(iOS 14, *)
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        if let provider = results.first?.itemProvider{
            if provider.canLoadObject(ofClass: UIImage.self){
                provider.loadObject(ofClass: UIImage.self) { (image, error) in
                    if let image = image as? UIImage{
                        DispatchQueue.main.async {
                            self.askOptimizationFor(image)
                        }
                    }
                }
            }}
        
        dismiss(animated: true)
    }
    
    
}

extension ViewController:ColoringBookViewDelegate{
    func viewWillStartDrawing() {
        if let firstTool = tools.first{
            self.toolsHiddenState = firstTool.isHidden
        }
        
        for tool in tools{
            tool.isHidden = true
        }
    }
    
    func viewDidEndDrawing() {
        for tool in tools{
            tool.isHidden = self.toolsHiddenState
        }
        self.checkColoringBookState()
    }
    
    
}
