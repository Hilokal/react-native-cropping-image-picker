import UIKit

extension UIImage {
    func fixOrientation() -> UIImage {
        // No-op if the orientation is already correct.
        if self.imageOrientation == .up {
            return self
        }
        
        // We need to calculate the proper transformation to make the image upright.
        // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
        var transform = CGAffineTransform.identity
        
        switch self.imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: self.size.width, y: self.size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: self.size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: self.size.height)
            transform = transform.rotated(by: -.pi / 2)
        case .up, .upMirrored:
            break
        @unknown default:
            break
        }
        
        switch self.imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: self.size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: self.size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        @unknown default:
            break
        }
        
        // Now we draw the underlying CGImage into a new context, applying the transform calculated above.
        let ctx = CGContext(data: nil, width: Int(self.size.width), height: Int(self.size.height),
                            bitsPerComponent: self.cgImage!.bitsPerComponent,
                            bytesPerRow: 0,
                            space: self.cgImage!.colorSpace!,
                            bitmapInfo: self.cgImage!.bitmapInfo.rawValue)
        
        ctx?.concatenate(transform)
        
        switch self.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            ctx?.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: self.size.height, height: self.size.width))
        default:
            ctx?.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height))
        }
        
        // And now we just create a new UIImage from the drawing context.
        guard let cgImage = ctx?.makeImage() else { return self }
        return UIImage(cgImage: cgImage)
    }
    
    func resizedImageToSize(dstSize: CGSize) -> UIImage? {
        guard let cgImage = self.cgImage else {
            return nil
        }
        var destinationSize = dstSize
        
        let srcSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        if srcSize.equalTo(dstSize) {
            return self
        }
        
        var transform = CGAffineTransform.identity
        let scaleRatio = dstSize.width / srcSize.width
        switch imageOrientation {
        case .up:
            transform = CGAffineTransform.identity
        case .upMirrored:
            transform = CGAffineTransform(translationX: srcSize.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .down:
            transform = CGAffineTransform(translationX: srcSize.width, y: srcSize.height)
            transform = transform.rotated(by: .pi)
        case .downMirrored:
            transform = CGAffineTransform(translationX: 0, y: srcSize.height)
            transform = transform.scaledBy(x: 1, y: -1)
        case .leftMirrored:
            destinationSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(translationX: srcSize.height, y: srcSize.width)
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: 3 * .pi / 2)
        case .left:
            destinationSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(translationX: 0, y: srcSize.width)
            transform = transform.rotated(by: 3 * .pi / 2)
        case .rightMirrored:
            destinationSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(scaleX: -1, y: 1)
            transform = transform.rotated(by: .pi / 2)
        case .right:
            destinationSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(translationX: srcSize.height, y: 0)
            transform = transform.rotated(by: .pi / 2)
        @unknown default:
            fatalError("Invalid image orientation")
        }
        
        UIGraphicsBeginImageContextWithOptions(destinationSize, false, scale)
        guard let context = UIGraphicsGetCurrentContext() else {
            return nil
        }
        
        switch imageOrientation {
        case .right, .left:
            context.scaleBy(x: -scaleRatio, y: scaleRatio)
            context.translateBy(x: -srcSize.height, y: 0)
        default:
            context.scaleBy(x: scaleRatio, y: -scaleRatio)
            context.translateBy(x: 0, y: -srcSize.height)
        }
        
        context.concatenate(transform)
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: srcSize.width, height: srcSize.height))
        
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    func resizedImageToFitInSize(boundingSize: CGSize, scaleIfSmaller: Bool) -> UIImage? {
        guard let cgImage = self.cgImage else {
            return nil
        }
        
        let srcSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        var boundedSize = boundingSize
        switch imageOrientation {
        case .left, .right, .leftMirrored, .rightMirrored:
            boundedSize = CGSize(width: boundingSize.height, height: boundingSize.width)
        default:
            break
        }
        
        var dstSize: CGSize
        if !scaleIfSmaller && (srcSize.width < boundedSize.width && srcSize.height < boundedSize.height) {
            dstSize = srcSize
        } else {
            let wRatio = boundedSize.width / srcSize.width
            let hRatio = boundedSize.height / srcSize.height
            
            if wRatio < hRatio {
                dstSize = CGSize(width: boundedSize.width, height: srcSize.height * wRatio)
            } else {
                dstSize = CGSize(width: srcSize.width * hRatio, height: boundedSize.height)
            }
        }
        
        return resizedImageToSize(dstSize: dstSize)
    }
}
