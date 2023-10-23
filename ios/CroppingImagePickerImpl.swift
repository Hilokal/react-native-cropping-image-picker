import UIKit
import AVFoundation
import MobileCoreServices
import Photos
import CropViewController
import PhotosUI
import React

class CroppingImagePickerImpl: NSObject,
                               PHPickerViewControllerDelegate,
                               UIImagePickerControllerDelegate,
                               UINavigationControllerDelegate,
                               CropViewControllerDelegate {
    
    static let shared = CroppingImagePickerImpl()
    
    enum SelectionMode {
        case camera, cropping, picker
    }
    
    var croppingFile: [String: Any]?
    var defaultOptions: [String: Any] = [
        "multiple": false,
        "cropping": false,
        "cropperCircleOverlay": false,
        "writeTempFile": true,
        "includeBase64": false,
        "includeExif": false,
        "compressVideo": true,
        "minFiles": 1,
        "maxFiles": 5,
        "width": 200,
        "height": 200,
        "useFrontCamera": false,
        "avoidEmptySpaceAroundImage": true,
        "compressImageQuality": 0.8,
        "compressVideoPreset": "MediumQuality",
        "loadingLabelText": "Processing assets...",
        "mediaType": "any",
        "showsSelectedCount": true,
        "forceJpg": false,
        "sortOrder": "none",
        "cropperCancelText": "Cancel",
        "cropperChooseText": "Choose",
        "cropperRotateButtonsHidden": false
    ]
    var compression: Compression?
    var options: [String: Any] = [:]
    
    var resolve: RCTPromiseResolveBlock?
    var reject: RCTPromiseRejectBlock?
    
    var currentSelectionMode: SelectionMode = .picker
    
    override init() {
        super.init()
        self.compression = Compression()
    }
    
    func waitAnimationEnd(completion: (() -> Void)? = nil) -> (() -> Void)? {
        if let waitAnimationEnd = options["waitAnimationEnd"] as? Bool, waitAnimationEnd {
            return completion
        }
        
        completion?()
        return nil
    }
    
    func checkCameraPermissions(callback: @escaping (Bool) -> Void) {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        
        switch status {
        case .authorized:
            callback(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                callback(granted)
            }
        default:
            callback(false)
        }
    }
    
    
    func setConfiguration(options: [String: Any],
                          resolver: @escaping RCTPromiseResolveBlock,
                          rejecter: @escaping RCTPromiseRejectBlock) {
        self.resolve = resolver
        self.reject = rejecter
        self.options = defaultOptions.merging(options) { (_, new) in new }
    }
    
    
    func getRootVC() -> UIViewController {
        var root = UIApplication.shared.delegate?.window??.rootViewController
        while root?.presentedViewController != nil {
            root = root?.presentedViewController
        }
        return root!
    }
    
    func openCamera(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        setConfiguration(options: options, resolver: resolver, rejecter: rejecter)
        currentSelectionMode = .camera
        
#if TARGET_IPHONE_SIMULATOR
        rejecter(CPIErrors.cannotRunCameraOnSimulatorKey, CPIErrors.cannotRunCameraOnSimulatorMsg, nil)
        return
#else
        checkCameraPermissions { granted in
            if !granted {
                rejecter(CIPErrors.noCameraPermissionKey, CIPErrors.noCameraPermissionMsg, nil)
                return
            }
            
            DispatchQueue.main.async {
                let picker = UIImagePickerController()
                picker.delegate = self
                picker.allowsEditing = false
                picker.sourceType = .camera
                
                if let mediaType = self.options["mediaType"] as? String, mediaType == "video",
                   let availableTypes = UIImagePickerController.availableMediaTypes(for: .camera),
                   availableTypes.contains(kUTTypeMovie as String) {
                    picker.mediaTypes = [kUTTypeMovie as String]
                    picker.videoQuality = .typeHigh
                }
                
                if let useFrontCamera = self.options["useFrontCamera"] as? Bool, useFrontCamera {
                    picker.cameraDevice = .front
                }
                
                self.getRootVC().present(picker, animated: true, completion: nil)
            }
        }
#endif
    }
    
    func imagePickerControllerDidCancel(_ imagePickerController: UIImagePickerController) {
        imagePickerController.dismiss(animated: true) {
            self.reject?(CIPErrors.pickerCancelKey, CIPErrors.pickerCancelMsg, nil)
        }
    }
    
    func getTmpDirectory() -> String {
        let TMP_DIRECTORY = "react-native-cropping-image-picker/"
        let tmpFullPath = NSTemporaryDirectory().appending(TMP_DIRECTORY)
        
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: tmpFullPath, isDirectory: &isDir)
        
        if !exists {
            try? FileManager.default.createDirectory(atPath: tmpFullPath, withIntermediateDirectories: true, attributes: nil)
        }
        
        return tmpFullPath
    }
    
    func cleanTmpDirectory() -> Bool {
        let tmpDirectoryPath = getTmpDirectory()
        guard let tmpDirectory = try? FileManager.default.contentsOfDirectory(atPath: tmpDirectoryPath) else { return false }
        
        for file in tmpDirectory {
            let filePath = tmpDirectoryPath.appending(file)
            do {
                try FileManager.default.removeItem(atPath: filePath)
            } catch {
                return false
            }
        }
        
        return true
    }
    
    func cleanSingle(_ path: String, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        do {
            try FileManager.default.removeItem(atPath: path)
            resolver(nil)
        } catch {
            rejecter(CIPErrors.cleanupErrorKey, CIPErrors.cleanupErrorMsg, nil)
        }
    }
    
    func clean(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        if !cleanTmpDirectory() {
            rejecter(CIPErrors.cleanupErrorKey, CIPErrors.cleanupErrorMsg, nil)
        } else {
            resolver(nil)
        }
    }
    
    @available(iOS 14.0, *)
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        //        picker.dismiss(animated: true)
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        let fetchOptions = PHFetchOptions()
        
        if let multiple = self.options["multiple"] as? Bool, multiple {
            var selections = [Any]()
            
            self.showActivityIndicator { (indicatorView, overlayView) in
                let lock = NSLock()
                var processed = 0
                let identifiers = results.compactMap { $0.assetIdentifier }
                fetchOptions.fetchLimit = identifiers.count
                let phAssets = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: fetchOptions)
                
                phAssets.enumerateObjects { (phAsset, _, _) in
                    if phAsset.mediaType == .video {
                        self.getVideoAsset(forAsset: phAsset) { video in
                            DispatchQueue.main.async {
                                lock.lock()
                                if video == nil {
                                    indicatorView.stopAnimating()
                                    overlayView.removeFromSuperview()
                                    picker.dismiss(animated: true) {
                                        self.reject?(CIPErrors.cannotProcessVideoKey, CIPErrors.cannotProcessVideoMsg, nil)
                                    }
                                    return
                                }
                                selections.append(video as Any)
                                processed += 1
                                lock.unlock()
                                
                                if processed == phAssets.count {
                                    indicatorView.stopAnimating()
                                    overlayView.removeFromSuperview()
                                    picker.dismiss(animated: true) {
                                        self.resolve?(selections)
                                    }
                                    return
                                }
                            }
                        }
                    } else {
                        phAsset.requestContentEditingInput(with: nil) { contentEditingInput, info in
                            manager.requestImageData(for: phAsset, options: options) { imageData, dataUTI, orientation, info in
                                guard let sourceURL = contentEditingInput?.fullSizeImageURL, let imageData = imageData else { return }
                                
                                DispatchQueue.main.async {
                                    lock.lock()
                                    
                                    var exif: [String: Any]?
                                    if let includeExif = self.options["includeExif"] as? Bool, includeExif {
                                        if let imageWithData = CIImage(data: imageData) {
                                            exif = imageWithData.properties
                                        }
                                    }
                                    
                                    if let imgT = UIImage(data: imageData) {
                                        let forceJpg = (self.options["forceJpg"] as? Bool) ?? false
                                        let compressQuality = self.options["compressImageQuality"] as? Float
                                        let isLossless = (compressQuality == nil || compressQuality! >= 0.8)
                                        let maxWidth = self.options["compressImageMaxWidth"] as? CGFloat
                                        let useOriginalWidth = (maxWidth == nil || maxWidth! >= imgT.size.width)
                                        let maxHeight = self.options["compressImageMaxHeight"] as? CGFloat
                                        let useOriginalHeight = (maxHeight == nil || maxHeight! >= imgT.size.height)
                                        
                                        let mimeType: String = self.determineMimeType(imageData: imageData)
                                        let isKnownMimeType = !mimeType.isEmpty
                                        
                                        var imageResult = ImageResult()
                                        
                                        if isLossless, useOriginalWidth, useOriginalHeight, isKnownMimeType, !forceJpg {
                                            imageResult.data = imageData
                                            imageResult.width = NSNumber(value: Float(imgT.size.width))
                                            imageResult.height = NSNumber(value: Float(imgT.size.height))
                                            imageResult.mime = mimeType
                                            imageResult.image = imgT
                                        } else {
                                            if let compression = self.compression {
                                                imageResult = compression.compressImage(image: imgT.fixOrientation(), with: self.options)
                                            } else {
                                                // Handle the case where 'self.compression' is nil.
                                                print("Compression instance not available!")
                                            }
                                        }
                                        
                                        var filePath = ""
                                        if let writeTempFile = self.options["writeTempFile"] as? Bool, writeTempFile {
                                            if let imageData = imageResult.data {
                                                filePath = self.persistFile(imageData) ?? ""
                                                if filePath.isEmpty {
                                                    indicatorView.stopAnimating()
                                                    overlayView.removeFromSuperview()
                                                    picker.dismiss(animated: true) {
                                                        self.reject?(CIPErrors.cannotSaveImageKey, CIPErrors.cannotSaveImageMsg, nil)
                                                    }
                                                    return
                                                }
                                            }
                                        }
                                        
                                        let dataSize = imageResult.data?.count ?? 0
                                        let attachmentResponse = self.createAttachmentResponse(filePath: filePath,
                                                                                               exif: exif,
                                                                                               sourceURL: sourceURL.absoluteString,
                                                                                               localIdentifier: phAsset.localIdentifier,
                                                                                               filename: phAsset.value(forKey: "filename") as? String,
                                                                                               width: imageResult.width ?? NSNumber(value: 0),
                                                                                               height: imageResult.height ?? NSNumber(value: 0),
                                                                                               mime: imageResult.mime ?? "",
                                                                                               size: NSNumber(value: dataSize),
                                                                                               duration: nil,
                                                                                               data: (self.options["includeBase64"] as? Bool) ?? false ? imageData.base64EncodedString() : nil,
                                                                                               cropRect: .null,
                                                                                               creationDate: phAsset.creationDate,
                                                                                               modificationDate: phAsset.modificationDate)
                                        
                                        selections.append(attachmentResponse)
                                    }
                                    
                                    processed += 1
                                    lock.unlock()
                                    
                                    if processed == phAssets.count {
                                        indicatorView.stopAnimating()
                                        overlayView.removeFromSuperview()
                                        picker.dismiss(animated: true) {
                                            self.resolve?(selections)
                                        }
                                        return
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            guard let identifier = results.first?.assetIdentifier else { return }
            fetchOptions.fetchLimit = 1
            guard let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: fetchOptions).firstObject else { return }
            self.showActivityIndicator { (indicatorView, overlayView) in
                if phAsset.mediaType == .video {
                    self.getVideoAsset(forAsset: phAsset) { video in
                        DispatchQueue.main.async {
                            indicatorView.stopAnimating()
                            overlayView.removeFromSuperview()
                            picker.dismiss(animated: true) {
                                if let video = video {
                                    self.resolve?(video)
                                } else {
                                    self.reject?(CIPErrors.cannotProcessVideoKey, CIPErrors.cannotProcessVideoMsg, nil)
                                }
                            }
                        }
                    }
                } else {
                    phAsset.requestContentEditingInput(with: nil) { contentEditingInput, info in
                        manager.requestImageData(for: phAsset, options: options) { imageData, dataUTI, orientation, info in
                            guard let sourceURL = contentEditingInput?.fullSizeImageURL, let imageData = imageData else { return }
                            
                            var exif: [String: Any]?
                            if let includeExif = self.options["includeExif"] as? Bool, includeExif {
                                if let imageWithData = CIImage(data: imageData) {
                                    exif = imageWithData.properties
                                }
                            }
                            
                            DispatchQueue.main.async {
                                indicatorView.stopAnimating()
                                overlayView.removeFromSuperview()
                                
                                self.processSingleImagePick(UIImage(data: imageData)!,
                                                            withExif: exif,
                                                            withViewController: picker,
                                                            withSourceURL: sourceURL.absoluteString,
                                                            withLocalIdentifier: phAsset.localIdentifier,
                                                            withFilename: phAsset.value(forKey: "filename") as? String,
                                                            withCreationDate: phAsset.creationDate,
                                                            withModificationDate: phAsset.modificationDate)
                            }
                        }
                    }
                }
            }
            return
        }
    }
    
    @available(iOS 14.0, *)
    func openPicker(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        print("OPEN_PICKER")
        setConfiguration(options: options, resolver: resolver, rejecter: rejecter)
        currentSelectionMode = .picker
        
        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                rejecter(CIPErrors.noLibraryPermissionKey, CIPErrors.noLibraryPermissionMsg, nil)
                return
            }
            
            DispatchQueue.main.async {
                
                var configuration = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
                configuration.selectionLimit = options["multiple"] as? Bool == true ? 0 : 1
                //                configuration.selection = .ordered # iOS 15
                
                if let cropping = options["cropping"] as? Bool, cropping {
                    configuration.filter = PHPickerFilter.images
                    
                } else if let mediaType = options["mediaType"] as? String {
                    switch mediaType {
                    case "photo":
                        configuration.filter = PHPickerFilter.images
                    case "video":
                        configuration.filter = PHPickerFilter.videos
                    default:
                        break
                    }
                }
                
                let imagePickerController = PHPickerViewController(configuration: configuration )
                imagePickerController.delegate = self
                imagePickerController.modalPresentationStyle = .fullScreen

                self.getRootVC().present(imagePickerController, animated: true)
            }
        }
    }
    
    func openCropper(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        setConfiguration(options: options, resolver: resolver, rejecter: rejecter)
        currentSelectionMode = .cropping
        
        if let path = options["path"] as? String,
           let url = URL(string: path),
           let module = RCTImageLoader() {
            module.loadImage(with: URLRequest(url: url)) { (error, image) in
                guard let image = image else {
                    rejecter(CIPErrors.cropperImageNotFoundKey, CIPErrors.cropperImageNotFoundMsg, nil)
                    return
                }
                self.cropImage(image.fixOrientation())
            }
        }
    }
    
    func showActivityIndicator(handler: @escaping (UIActivityIndicatorView, UIView) -> Void) {
        DispatchQueue.main.async {
            guard let mainView = self.getRootVC().view else { return }
            
            // Create overlay
            let loadingView = UIView(frame: UIScreen.main.bounds)
            loadingView.backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.5)
            loadingView.clipsToBounds = true
            
            // Create loading spinner
            let activityView = UIActivityIndicatorView(style: .whiteLarge)
            activityView.frame = CGRect(x: 65, y: 40, width: activityView.bounds.width, height: activityView.bounds.height)
            activityView.center = loadingView.center
            loadingView.addSubview(activityView)
            
            // Create message
            let loadingLabel = UILabel(frame: CGRect(x: 20, y: 115, width: 130, height: 22))
            loadingLabel.backgroundColor = .clear
            loadingLabel.textColor = .white
            loadingLabel.adjustsFontSizeToFitWidth = true
            var loadingLabelLocation = loadingView.center
            loadingLabelLocation.y += activityView.bounds.height
            loadingLabel.center = loadingLabelLocation
            loadingLabel.textAlignment = .center
            loadingLabel.text = self.options["loadingLabelText"] as? String
            loadingLabel.font = UIFont.boldSystemFont(ofSize: 18)
            loadingView.addSubview(loadingLabel)
            
            // Show all
            mainView.addSubview(loadingView)
            activityView.startAnimating()
            
            handler(activityView, loadingView)
        }
    }
    
    func handleVideo(asset: AVAsset, withFileName fileName: String, withLocalIdentifier localIdentifier: String?, completion: @escaping ([String: Any]?) -> Void) {
        guard let sourceURLAsset = asset as? AVURLAsset else { return }
        let sourceURL = sourceURLAsset.url
        
        // Create temp file
        let tmpDirFullPath = getTmpDirectory()
        let filePath = "\(tmpDirFullPath)\(UUID().uuidString).mp4"
        let outputURL = URL(fileURLWithPath: filePath)
        
        compression?.compressVideo(inputURL: sourceURL, outputURL: outputURL, with: options) { exportSession in
            if exportSession.status == .completed {
                let compressedAsset = AVAsset(url: outputURL)
                guard let track = compressedAsset.tracks(withMediaType: .video).first else { return }
                
                var fileSizeValue: NSNumber?
                do {
                    if let fileSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                        fileSizeValue = NSNumber(value: fileSize)
                    }
                } catch {
                    print("Error getting file size: \(error)")
                }
                
                let durationFromUrl = AVURLAsset(url: outputURL)
                let time = durationFromUrl.duration
                let milliseconds = ceil(Double(time.value) / Double(time.timescale)) * 1000
                
                completion(
                    self.createAttachmentResponse(
                        filePath: outputURL.absoluteString,
                        exif: nil,
                        sourceURL: sourceURL.absoluteString,
                        localIdentifier: localIdentifier,
                        filename: fileName,
                        width: NSNumber(value: Float(track.naturalSize.width)),
                        height: NSNumber(value: Float(track.naturalSize.height)),
                        mime: "video/mp4",
                        size: fileSizeValue,
                        duration: NSNumber(value: milliseconds),
                        data: nil,
                        cropRect: .null,
                        creationDate: nil,
                        modificationDate: nil
                    ) as [String : Any]
                )
            } else {
                completion(nil)
            }
        }
    }
    
    func getVideoAsset(forAsset: PHAsset, completion: @escaping ([String: Any?]?) -> Void) {
        let manager = PHImageManager.default()
        let options = PHVideoRequestOptions()
        options.version = .original
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        manager.requestAVAsset(forVideo: forAsset, options: options) { asset, audioMix, info in
            guard let asset = asset else { return }
            self.handleVideo(asset: asset,
                             withFileName: forAsset.value(forKey: "filename") as! String,
                             withLocalIdentifier: forAsset.localIdentifier,
                             completion: completion)
        }
    }
    
    func createAttachmentResponse(
        filePath: String?,
        exif: [String: Any?]?,
        sourceURL: String?,
        localIdentifier: String?,
        filename: String?,
        width: NSNumber,
        height: NSNumber,
        mime: String,
        size: NSNumber?,
        duration: NSNumber?,
        data: String?,
        cropRect: CGRect,
        creationDate: Date?,
        modificationDate: Date?) -> [String: Any?] {
            
            let isRectNull = cropRect == CGRect.null // This checks if the rect is "null"
            
            return [
                "path": filePath ?? NSNull(),
                "sourceURL": sourceURL ?? NSNull(),
                "localIdentifier": localIdentifier ?? NSNull(),
                "filename": filename ?? NSNull(),
                "width": width,
                "height": height,
                "mime": mime,
                "size": size ?? NSNull(),
                "data": data ?? NSNull(),
                "exif": exif ?? NSNull(),
                "cropRect": isRectNull ? NSNull() : cropRect.toDictionary(),
                "creationDate": creationDate != nil ? "\(Int(creationDate!.timeIntervalSince1970))" : NSNull(),
                "modificationDate": modificationDate != nil ? "\(Int(modificationDate!.timeIntervalSince1970))" : NSNull(),
                "duration": duration
            ]
        }
    
    
    func determineMimeType(imageData: Data) -> String {
        var c: UInt8 = 0
        imageData.copyBytes(to: &c, count: 1)
        
        switch c {
        case 0xFF:
            return "image/jpeg"
        case 0x89:
            return "image/png"
        case 0x47:
            return "image/gif"
        case 0x49, 0x4D:
            return "image/tiff"
        case 0x00:
            return "image/heic"
        default:
            return ""
        }
    }
    
    // when user selected single image, with camera or from photo gallery,
    // this method will take care of attaching image metadata, and sending image to cropping controller
    // or to user directly
    func processSingleImagePick(
        _ image: UIImage,
        withExif exif: [String: Any]?,
        withViewController viewController: UIViewController,
        withSourceURL sourceURL: String?,
        withLocalIdentifier localIdentifier: String?,
        withFilename filename: String?,
        withCreationDate creationDate: Date?,
        withModificationDate modificationDate: Date?) {
            print("ARRIVED_start_processSingleImagePick")
            viewController.dismiss(animated: true, completion: waitAnimationEnd {
                self.reject?(CIPErrors.pickerNoDataKey, CIPErrors.pickerNoDataMsg, nil)
            })
            
            
            print("id: \(String(describing: localIdentifier)) filename: \(filename ?? "")")
            
            if let cropping = options["cropping"] as? Bool, cropping {
                croppingFile = [
                    "sourceURL": sourceURL ?? "",
                    "localIdentifier": localIdentifier ?? "",
                    "filename": filename ?? "",
                    "creationDate": creationDate ?? Date(),
                    "modificationDate": modificationDate ?? Date()
                ]
                print("CroppingFile \(String(describing: croppingFile))")
                cropImage(image.fixOrientation())
            } else {
                guard
                    let imageResult = compression?.compressImage(image: image.fixOrientation(), with: options),
                    let imageData = imageResult.data,
                    let filePath = persistFile(imageData) else {
                    viewController.dismiss(animated: true, completion: waitAnimationEnd {
                        self.reject?(CIPErrors.cannotSaveImageKey, CIPErrors.cannotSaveImageMsg, nil)
                    })
                    return
                }
                
                viewController.dismiss(animated: true, completion: waitAnimationEnd {
                    self.resolve?(self.createAttachmentResponse(filePath: filePath,
                                                                exif: exif,
                                                                sourceURL: sourceURL,
                                                                localIdentifier: localIdentifier,
                                                                filename: filename,
                                                                width: imageResult.width ?? NSNumber(value: 0),
                                                                height: imageResult.height ?? NSNumber(value: 0),
                                                                mime: imageResult.mime ?? "",
                                                                size: NSNumber(value: imageData.count),
                                                                duration: nil,
                                                                data: (self.options["includeBase64"] as? Bool == true) ? imageData.base64EncodedString() : nil,
                                                                cropRect: CGRect.null,
                                                                creationDate: creationDate,
                                                                modificationDate: modificationDate))
                })
            }
        }
    
    func dismissCropper(_ controller: UIViewController, selectionDone: Bool, completion: (() -> Void)? = nil) {
        switch currentSelectionMode {
        case .cropping:
            controller.dismiss(animated: true, completion: completion)
        case .picker:
            if selectionDone {
                controller.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: completion)
            } else {
                controller.presentingViewController?.dismiss(animated: true, completion: completion)
            }
        case .camera:
            controller.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: completion)
        }
    }
    
    func imageCropViewController(_ controller: UIViewController, didCropImage croppedImage: UIImage, usingCropRect cropRect: CGRect) {
        guard
            let desiredWidth = options["width"] as? Int,
            let desiredHeight = options["height"] as? Int,
            let resizedImage = croppedImage.resizedImageToFitInSize(boundingSize: CGSize(width: desiredWidth, height: desiredHeight), scaleIfSmaller: true),
            let imageResult = compression?.compressImage(image: resizedImage, with: options),
            let imageData = imageResult.data,
            let filePath = persistFile(imageData) else {
            dismissCropper(controller, selectionDone: true, completion: waitAnimationEnd {
                self.reject?(CIPErrors.cannotSaveImageKey, CIPErrors.cannotSaveImageMsg, nil)
            })
            return
        }
        
        
        var exif: [String: Any]?
        if options["includeExif"] as? Bool == true {
            exif = CIImage(data: imageData)?.properties
        }
        
        dismissCropper(controller, selectionDone: true, completion: waitAnimationEnd {
            self.resolve?(self.createAttachmentResponse(filePath: filePath,
                                                        exif: exif,
                                                        sourceURL: self.croppingFile?["sourceURL"] as? String ?? "",
                                                        localIdentifier: self.croppingFile?["localIdentifier"] as? String ?? "",
                                                        filename: self.croppingFile?["filename"] as? String,
                                                        width: imageResult.width ?? NSNumber(value: 0),
                                                        height: imageResult.height ?? NSNumber(value: 0),
                                                        mime: imageResult.mime ?? "",
                                                        size: NSNumber(value: imageData.count),
                                                        duration: nil,
                                                        data: (self.options["includeBase64"] as? Bool == true) ? imageData.base64EncodedString() : nil,
                                                        cropRect: cropRect,
                                                        creationDate: self.croppingFile?["creationDate"] as? Date,
                                                        modificationDate: self.croppingFile?["modificationDate"] as? Date))
        })
    }
    
    // at the moment it is not possible to upload image by reading PHAsset
    // we are saving image and saving it to the tmp location where we are allowed to access image later
    func persistFile(_ data: Data) -> String? {
        let tmpDirFullPath = getTmpDirectory()
        let fileName = "\(UUID().uuidString).jpg"
        let filePath = tmpDirFullPath.appending("/").appending(fileName)
        
        do {
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            return filePath
        } catch {
            return nil
        }
    }
    
    
    func cropImage(_ image: UIImage) {
        DispatchQueue.main.async {
            let cropVC: CropViewController
            if self.options["cropperCircleOverlay"] as? Bool == true {
                cropVC = CropViewController(croppingStyle: .circular, image: image)
            } else {
                cropVC = CropViewController(image: image)
                let widthRatio = self.options["width"] as? CGFloat ?? 0
                let heightRatio = self.options["height"] as? CGFloat ?? 0
                if widthRatio > 0 && heightRatio > 0 {
                    let aspectRatio = CGSize(width: widthRatio, height: heightRatio)
                    cropVC.customAspectRatio = aspectRatio
                }
                cropVC.aspectRatioLockEnabled = !(self.options["freeStyleCropEnabled"] as? Bool ?? false)
                cropVC.resetAspectRatioEnabled = !cropVC.aspectRatioLockEnabled
            }
            
            cropVC.title = self.options["cropperToolbarTitle"] as? String
            cropVC.delegate = self
            
            if let rawDoneButtonColor = self.options["cropperChooseColor"] as? String {
                cropVC.doneButtonColor = UIColor.from(hexString: rawDoneButtonColor)
            }
            if let rawCancelButtonColor = self.options["cropperCancelColor"] as? String {
                cropVC.cancelButtonColor = UIColor.from(hexString: rawCancelButtonColor)
            }
            
            cropVC.doneButtonTitle = self.options["cropperChooseText"] as? String
            cropVC.cancelButtonTitle = self.options["cropperCancelText"] as? String
            cropVC.rotateButtonsHidden = self.options["cropperRotateButtonsHidden"] as? Bool ?? false
            
            cropVC.modalPresentationStyle = .fullScreen
            if #available(iOS 15.0, *) {
                cropVC.modalTransitionStyle = .coverVertical
            }
            
            self.getRootVC().present(cropVC, animated: false, completion: nil)
        }
    }
    
    // Delegate methods for TOCropViewController
    func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
        imageCropViewController(cropViewController, didCropImage: image, usingCropRect: cropRect)
    }
    
    func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
        dismissCropper(cropViewController, selectionDone: false) {
            if self.currentSelectionMode == .cropping {
                self.reject?(CIPErrors.pickerCancelKey, CIPErrors.pickerCancelMsg, nil)
            }
        }
    }
}

