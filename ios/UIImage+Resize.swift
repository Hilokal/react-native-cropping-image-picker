import UIKit

extension UIImage {
    
    func resizedImageToSize(dstSize: CGSize) -> UIImage? {
        guard let cgImage = self.cgImage else {
            return nil
        }
        
        var srcSize = CGSize(width: cgImage.width, height: cgImage.height)
        
        if srcSize.equalTo(dstSize) {
            return self
        }
        
        var transform = CGAffineTransform.identity
        var scaleRatio = dstSize.width / srcSize.width
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
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(translationX: srcSize.height, y: srcSize.width)
            transform = transform.scaledBy(x: -1, y: 1)
            transform = transform.rotated(by: 3 * .pi / 2)
        case .left:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(translationX: 0, y: srcSize.width)
            transform = transform.rotated(by: 3 * .pi / 2)
        case .rightMirrored:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(scaleX: -1, y: 1)
            transform = transform.rotated(by: .pi / 2)
        case .right:
            dstSize = CGSize(width: dstSize.height, height: dstSize.width)
            transform = CGAffineTransform(translationX: srcSize.height, y: 0)
            transform = transform.rotated(by: .pi / 2)
        @unknown default:
            fatalError("Invalid image orientation")
        }
        
        UIGraphicsBeginImageContextWithOptions(dstSize, false, scale)
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
        
        var srcSize = CGSize(width: cgImage.width, height: cgImage.height)
        
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
