import UIKit
import AVFoundation

class Compression {
    var exportPresets: [String: String]
    
    init() {
        let dic: [String: String] = [
            "640x480": AVAssetExportPreset640x480,
            "960x540": AVAssetExportPreset960x540,
            "1280x720": AVAssetExportPreset1280x720,
            "1920x1080": AVAssetExportPreset1920x1080,
            "3840x2160": AVAssetExportPreset3840x2160,
            "LowQuality": AVAssetExportPresetLowQuality,
            "MediumQuality": AVAssetExportPresetMediumQuality,
            "HighestQuality": AVAssetExportPresetHighestQuality,
            "Passthrough": AVAssetExportPresetPassthrough
        ]
        self.exportPresets = dic
    }
    
    func compressImageDimensions(image: UIImage, maxWidth: CGFloat, maxHeight: CGFloat, into result: ImageResult) {
        let oldWidth = image.size.width
        let oldHeight = image.size.height
        
        var newWidth: Int = 0
        var newHeight: Int = 0
        
        if maxWidth < maxHeight {
            newWidth = Int(maxWidth)
            newHeight = Int((oldHeight / oldWidth) * CGFloat(newWidth))
        } else {
            newHeight = Int(maxHeight)
            newWidth = Int((oldWidth / oldHeight) * CGFloat(newHeight))
        }
        
        let newSize = CGSize(width: newWidth, height: newHeight)
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resizedImage = renderer.image { (context) in
            image.draw(in: CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height))
        }
        
        result.width = NSNumber(value: newWidth)
        result.height = NSNumber(value: newHeight)
        result.image = resizedImage
    }
    
    func compressImage(image: UIImage, with options: [String: Any]) -> ImageResult {
        let result = ImageResult()
        result.width = NSNumber(value: Float(image.size.width))
        result.height = NSNumber(value: Float(image.size.height))
        result.image = image
        result.mime = "image/jpeg"
        
        let compressImageMaxWidth = options["compressImageMaxWidth"] as? CGFloat
        let compressImageMaxHeight = options["compressImageMaxHeight"] as? CGFloat
        
        let shouldResizeWidth = compressImageMaxWidth != nil && compressImageMaxWidth! < image.size.width
        let shouldResizeHeight = compressImageMaxHeight != nil && compressImageMaxHeight! < image.size.height
        
        if shouldResizeWidth || shouldResizeHeight {
            let maxWidth = compressImageMaxWidth ?? image.size.width
            let maxHeight = compressImageMaxHeight ?? image.size.height
            
            compressImageDimensions(image: image, maxWidth: maxWidth, maxHeight: maxHeight, into: result)
        }
        
        let compressQuality = options["compressImageQuality"] as? CGFloat ?? 0.8
        
        result.data = image.jpegData(compressionQuality: compressQuality)
        
        return result
    }
    
    func compressVideo(inputURL: URL, outputURL: URL, with options: [String: Any], handler: @escaping (AVAssetExportSession) -> Void) {
        let presetKey = options["compressVideoPreset"] as? String ?? "MediumQuality"
        
        let preset = exportPresets[presetKey] ?? AVAssetExportPresetMediumQuality
        
        try? FileManager.default.removeItem(at: outputURL)
        let asset = AVURLAsset(url: inputURL, options: nil)
        if let exportSession = AVAssetExportSession(asset: asset, presetName: preset) {
            exportSession.shouldOptimizeForNetworkUse = true
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            
            exportSession.exportAsynchronously {
                handler(exportSession)
            }
        }
    }
    
}
