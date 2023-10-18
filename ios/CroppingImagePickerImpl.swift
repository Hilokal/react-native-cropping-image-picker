import UIKit
import AVFoundation
import MobileCoreServices
import Photos

class CroppingImagePickerImpl: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
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
        rejecter(ERROR_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR_KEY, ERROR_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR_MSG, nil)
        return
        #else
        checkCameraPermissions { granted in
            if !granted {
                rejecter(ERROR_NO_CAMERA_PERMISSION_KEY, ERROR_NO_CAMERA_PERMISSION_MSG, nil)
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
                
                self.getRootVC()?.present(picker, animated: true, completion: nil)
            }
        }
        #endif
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    func imagePickerController(_ picker: UIImagePickerController, 
                            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let mediaType = info[.mediaType] as? String, 
        mediaType == kUTTypeMovie as String {
            if let url = info[.mediaURL] as? URL, 
            let asset = AVURLAsset(url: url) as? AVURLAsset {
                let fileName = asset.url.lastPathComponent
                handleVideo(asset, 
                            fileName: fileName, 
                            localIdentifier: nil) { video in
                    DispatchQueue.main.async {
                        if let video = video {
                            picker.dismiss(animated: true) {
                                self.resolve(video)
                            }
                        } else {
                            picker.dismiss(animated: true) {
                                self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil)
                            }
                        }
                    }
                }
            }
        } else if let chosenImage = info[.originalImage] as? UIImage {
            let exif = (options["includeExif"] as? Bool == true) ? info[.mediaMetadata] : nil
            processSingleImagePick(chosenImage, 
                                exif: exif, 
                                viewController: picker, 
                                sourceURL: croppingFile["sourceURL"], 
                                localIdentifier: croppingFile["localIdentifier"], 
                                filename: croppingFile["filename"], 
                                creationDate: croppingFile["creationDate"], 
                                modificationDate: croppingFile["modificationDate"])
        }
    }


    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) {
            self.reject(ERROR_PICKER_CANCEL_KEY, ERROR_PICKER_CANCEL_MSG, nil)
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
            rejecter(ERROR_CLEANUP_ERROR_KEY, ERROR_CLEANUP_ERROR_MSG, nil)
        }
    }

    func clean(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        if !cleanTmpDirectory() {
            rejecter(ERROR_CLEANUP_ERROR_KEY, ERROR_CLEANUP_ERROR_MSG, nil)
        } else {
            resolver(nil)
        }
    }

    func openPicker(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        setConfiguration(options: options, resolver: resolver, rejecter: rejecter)
        currentSelectionMode = .picker

        PHPhotoLibrary.requestAuthorization { status in
            guard status == .authorized else {
                rejecter(ERROR_NO_LIBRARY_PERMISSION_KEY, ERROR_NO_LIBRARY_PERMISSION_MSG, nil)
                return
            }

            DispatchQueue.main.async {
                let imagePickerController = QBImagePickerController()
                imagePickerController.delegate = self
                imagePickerController.allowsMultipleSelection = options["multiple"] as? Bool ?? false
                imagePickerController.minimumNumberOfSelection = abs(options["minFiles"] as? Int ?? 0)
                imagePickerController.maximumNumberOfSelection = abs(options["maxFiles"] as? Int ?? 0)
                imagePickerController.showsNumberOfSelectedAssets = options["showsSelectedCount"] as? Bool ?? false
                imagePickerController.sortOrder = options["sortOrder"] as? String
                
                if let smartAlbums = options["smartAlbums"] as? [String], !smartAlbums.isEmpty {
                    let albums: [String: PHAssetCollectionSubtype] = [
                        "Regular": .albumRegular,
                        "SyncedEvent": .albumSyncedEvent,
                        "SyncedFaces": .albumSyncedFaces,
                        "SyncedAlbum": .albumSyncedAlbum,
                        "Imported": .albumImported,
                        "PhotoStream": .albumMyPhotoStream,
                        "CloudShared": .albumCloudShared,
                        "Generic": .smartAlbumGeneric,
                        "Panoramas": .smartAlbumPanoramas,
                        "Videos": .smartAlbumVideos,
                        "Favorites": .smartAlbumFavorites,
                        "Timelapses": .smartAlbumTimelapses,
                        "AllHidden": .smartAlbumAllHidden,
                        "RecentlyAdded": .smartAlbumRecentlyAdded,
                        "Bursts": .smartAlbumBursts,
                        "SlomoVideos": .smartAlbumSlomoVideos,
                        "UserLibrary": .smartAlbumUserLibrary,
                        "SelfPortraits": .smartAlbumSelfPortraits,
                        "Screenshots": .smartAlbumScreenshots,
                        "DepthEffect": .smartAlbumDepthEffect,
                        "LivePhotos": .smartAlbumLivePhotos,
                        "Animated": .smartAlbumAnimated,
                        "LongExposure": .smartAlbumLongExposures
                    ]
                    
                    var albumsToShow: [PHAssetCollectionSubtype] = []
                    for smartAlbum in smartAlbums {
                        if let albumSubtype = albums[smartAlbum] {
                            albumsToShow.append(albumSubtype)
                        }
                    }
                    imagePickerController.assetCollectionSubtypes = albumsToShow
                }

                
                if let cropping = options["cropping"] as? Bool, cropping {
                    imagePickerController.mediaType = .image
                } else if let mediaType = options["mediaType"] as? String {
                    switch mediaType {
                    case "photo":
                        imagePickerController.mediaType = .image
                    case "video":
                        imagePickerController.mediaType = .video
                    default:
                        imagePickerController.mediaType = .any
                    }
                }
                
                imagePickerController.modalPresentationStyle = .fullScreen
                self.getRootVC()?.present(imagePickerController, animated: true, completion: nil)
            }
        }
    }

    func openCropper(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        setConfiguration(options: options, resolver: resolver, rejecter: rejecter)
        currentSelectionMode = .cropping

        if let path = options["path"] as? String,
        let module = bridge.module(forName: "ImageLoader", lazilyLoadIfNecessary: true) as? RCTImageLoader {
            module.loadImage(with: RCTConvert.nsURLRequest(path)) { (error, image) in
                guard let image = image else {
                    rejecter(ERROR_CROPPER_IMAGE_NOT_FOUND_KEY, ERROR_CROPPER_IMAGE_NOT_FOUND_MSG, nil)
                    return
                }
                self.cropImage(image.fixOrientation())
            }
        }
    }

    func showActivityIndicator(handler: @escaping (UIActivityIndicatorView, UIView) -> Void) {
        DispatchQueue.main.async {
            guard let mainView = self.getRootVC()?.view else { return }
            
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
            loadingLabel.text = self.options?["loadingLabelText"] as? String
            loadingLabel.font = UIFont.boldSystemFont(ofSize: 18)
            loadingView.addSubview(loadingLabel)
            
            // Show all
            mainView.addSubview(loadingView)
            activityView.startAnimating()
            
            handler(activityView, loadingView)
        }
    }

    func handleVideo(asset: AVAsset, withFileName fileName: String, withLocalIdentifier localIdentifier: String, completion: @escaping ([String: Any?]?) -> Void) {
        guard let sourceURL = asset as? AVURLAsset else { return }
        
        // Create temp file
        let tmpDirFullPath = getTmpDirectory()
        let filePath = "\(tmpDirFullPath)\(UUID().uuidString).mp4"
        let outputURL = URL(fileURLWithPath: filePath)
        
        self.compression.compressVideo(sourceURL: sourceURL, outputURL: outputURL, withOptions: options) { exportSession in
            if exportSession.status == .completed {
                let compressedAsset = AVAsset(url: outputURL)
                guard let track = compressedAsset.tracks(withMediaType: .video).first else { return }
                
                var fileSizeValue: NSNumber?
                do {
                    try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
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
                        width: track.naturalSize.width,
                        height: track.naturalSize.height,
                        mime: "video/mp4",
                        size: fileSizeValue,
                        duration: milliseconds,
                        data: nil,
                        cropRect: .null,
                        creationDate: nil,
                        modificationDate: nil
                    )
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
        options.networkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        
        manager.requestAVAsset(forVideo: forAsset, options: options) { asset, audioMix, info in
            guard let asset = asset else { return }
            self.handleVideo(asset: asset,
                            withFileName: forAsset.value(forKey: "filename") as! String,
                            withLocalIdentifier: forAsset.localIdentifier,
                            completion: completion)
        }
    }

    func createAttachmentResponse(filePath: String?, exif: [String: Any?]?, sourceURL: String?, localIdentifier: String?, filename: String?, width: CGFloat, height: CGFloat, mime: String, size: NSNumber?, duration: CGFloat, data: String?, cropRect: CGRect, creationDate: Date?, modificationDate: Date?) -> [String: Any?] {
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
            "cropRect": cropRect.isNull ? NSNull() : ImageCropPicker.cgRectToDictionary(cropRect),
            "creationDate": creationDate != nil ? "\(Int(creationDate!.timeIntervalSince1970))" : NSNull(),
            "modificationDate": modificationDate != nil ? "\(Int(modificationDate!.timeIntervalSince1970))" : NSNull(),
            "duration": duration
        ]
    }

    func determineMimeTypeFromImageData(data: Data) -> String {
        var c: UInt8 = 0
        data.copyBytes(to: &c, count: 1)
        
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

    func imagePickerController(_ imagePickerController: QBImagePickerController, didFinishPickingAssets assets: [PHAsset]) {
        
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.isSynchronous = false
        options.isNetworkAccessAllowed = true
        
        if let multiple = self.options["multiple"] as? Bool, multiple {
            var selections = [Any]()
            
            showActivityIndicator { (indicatorView, overlayView) in
                let lock = NSLock()
                var processed = 0
                
                for phAsset in assets {
                    if phAsset.mediaType == .video {
                        self.getVideoAsset(forAsset: phAsset) { video in
                            DispatchQueue.main.async {
                                lock.lock()
                                if video == nil {
                                    indicatorView.stopAnimating()
                                    overlayView.removeFromSuperview()
                                    imagePickerController.dismiss(animated: true) {
                                        self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil)
                                    }
                                    return
                                }
                                selections.append(video)
                                processed += 1
                                lock.unlock()
                                
                                if processed == assets.count {
                                    indicatorView.stopAnimating()
                                    overlayView.removeFromSuperview()
                                    imagePickerController.dismiss(animated: true) {
                                        self.resolve(selections)
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
                                        
                                        var mimeType: String = self.determineMimeType(from: imageData)
                                        let isKnownMimeType = !mimeType.isEmpty
                                        
                                        var imageResult = ImageResult() // Assuming ImageResult struct is available
                                        
                                        if isLossless, useOriginalWidth, useOriginalHeight, isKnownMimeType, !forceJpg {
                                            imageResult.data = imageData
                                            imageResult.width = imgT.size.width
                                            imageResult.height = imgT.size.height
                                            imageResult.mime = mimeType
                                            imageResult.image = imgT
                                        } else {
                                            imageResult = self.compression.compressImage(imgT.fixOrientation(), with: self.options)
                                        }
                                        
                                        var filePath = ""
                                        if let writeTempFile = self.options["writeTempFile"] as? Bool, writeTempFile {
                                            filePath = self.persistFile(data: imageResult.data)
                                            if filePath.isEmpty {
                                                indicatorView.stopAnimating()
                                                overlayView.removeFromSuperview()
                                                imagePickerController.dismiss(animated: true) {
                                                    self.reject(ERROR_CANNOT_SAVE_IMAGE_KEY, ERROR_CANNOT_SAVE_IMAGE_MSG, nil)
                                                }
                                                return
                                            }
                                        }
                                        
                                        let attachmentResponse = self.createAttachmentResponse(filePath: filePath,
                                                                                            exif: exif,
                                                                                            sourceURL: sourceURL.absoluteString,
                                                                                            localIdentifier: phAsset.localIdentifier,
                                                                                            filename: phAsset.value(forKey: "filename") as? String,
                                                                                            width: imageResult.width,
                                                                                            height: imageResult.height,
                                                                                            mime: imageResult.mime,
                                                                                            size: imageResult.data.count,
                                                                                            duration: nil,
                                                                                            data: (self.options["includeBase64"] as? Bool) ?? false ? imageData.base64EncodedString() : nil,
                                                                                            rect: .null,
                                                                                            creationDate: phAsset.creationDate,
                                                                                            modificationDate: phAsset.modificationDate)
                                        
                                        selections.append(attachmentResponse)
                                    }
                                    
                                    processed += 1
                                    lock.unlock()
                                    
                                    if processed == assets.count {
                                        indicatorView.stopAnimating()
                                        overlayView.removeFromSuperview()
                                        imagePickerController.dismiss(animated: true) {
                                            self.resolve(selections)
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
        guard let phAsset = assets.first else { return }

        self.showActivityIndicator { (indicatorView, overlayView) in
            if phAsset.mediaType == .video {
                self.getVideoAsset(phAsset) { video in
                    DispatchQueue.main.async {
                        indicatorView.stopAnimating()
                        overlayView.removeFromSuperview()
                        imagePickerController.dismiss(animated: true) {
                            if let video = video {
                                self.resolve(video)
                            } else {
                                self.reject(ERROR_CANNOT_PROCESS_VIDEO_KEY, ERROR_CANNOT_PROCESS_VIDEO_MSG, nil)
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
                                                        exif: exif,
                                                        viewController: imagePickerController,
                                                        sourceURL: sourceURL.absoluteString,
                                                        localIdentifier: phAsset.localIdentifier,
                                                        filename: phAsset.value(forKey: "filename") as? String,
                                                        creationDate: phAsset.creationDate,
                                                        modificationDate: phAsset.modificationDate)
                        }
                    }
                }
            }
        }
    }

    func imagePickerControllerDidCancel(_ imagePickerController: QBImagePickerController) {
        imagePickerController.dismiss(animated: true) {
            self.reject(ERROR_PICKER_CANCEL_KEY, ERROR_PICKER_CANCEL_MSG, nil)
        }
    }

    // when user selected single image, with camera or from photo gallery,
    // this method will take care of attaching image metadata, and sending image to cropping controller
    // or to user directly
    func processSingleImagePick(_ image: UIImage?, withExif exif: [String: Any]?, withViewController viewController: UIViewController, withSourceURL sourceURL: String, withLocalIdentifier localIdentifier: String, withFilename filename: String?, withCreationDate creationDate: Date?, withModificationDate modificationDate: Date?) {
        guard let image = image else {
            viewController.dismiss(animated: true, completion: waitAnimationEnd {
                self.reject(ERROR_PICKER_NO_DATA_KEY, ERROR_PICKER_NO_DATA_MSG, nil)
            })
            return
        }

        print("id: \(localIdentifier) filename: \(filename ?? "")")

        if let cropping = options["cropping"] as? Bool, cropping {
            croppingFile = [
                "sourceURL": sourceURL,
                "localIdentifier": localIdentifier,
                "filename": filename ?? "",
                "creationDate": creationDate ?? Date(),
                "modificationDate": modificationDate ?? Date()
            ]
            print("CroppingFile \(croppingFile)")
            cropImage(image.fixOrientation())
        } else {
            guard let imageResult = compression.compressImage(image.fixOrientation(), withOptions: options),
                let filePath = persistFile(imageResult.data) else {
                viewController.dismiss(animated: true, completion: waitAnimationEnd {
                    self.reject(ERROR_CANNOT_SAVE_IMAGE_KEY, ERROR_CANNOT_SAVE_IMAGE_MSG, nil)
                })
                return
            }

            viewController.dismiss(animated: true, completion: waitAnimationEnd {
                self.resolve(self.createAttachmentResponse(filePath,
                                                        withExif: exif,
                                                        withSourceURL: sourceURL,
                                                        withLocalIdentifier: localIdentifier,
                                                        withFilename: filename,
                                                        withWidth: imageResult.width,
                                                        withHeight: imageResult.height,
                                                        withMime: imageResult.mime,
                                                        withSize: imageResult.data.count,
                                                        withDuration: nil,
                                                        withData: (options["includeBase64"] as? Bool == true) ? imageResult.data.base64EncodedString() : nil,
                                                        withRect: CGRect.null,
                                                        withCreationDate: creationDate,
                                                        withModificationDate: modificationDate))
            })
        }
    }

    func dismissCropper(_ controller: UIViewController, selectionDone: Bool, completion: @escaping () -> Void) {
        switch currentSelectionMode {
        case .CROPPING:
            controller.dismiss(animated: true, completion: completion)
        case .PICKER:
            if selectionDone {
                controller.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: completion)
            } else {
                controller.presentingViewController?.dismiss(animated: true, completion: completion)
            }
        case .CAMERA:
            controller.presentingViewController?.presentingViewController?.dismiss(animated: true, completion: completion)
        }
    }

    func imageCropViewController(_ controller: UIViewController, didCropImage croppedImage: UIImage, usingCropRect cropRect: CGRect) {
        guard let desiredWidth = options["width"] as? Int, let desiredHeight = options["height"] as? Int else { return }

        let desiredImageSize = CGSize(width: desiredWidth, height: desiredHeight)
        let resizedImage = croppedImage.resizedImageToFit(in: desiredImageSize, scaleIfSmaller: true)

        guard let imageResult = compression.compressImage(resizedImage, withOptions: options),
            let filePath = persistFile(imageResult.data) else {
            dismissCropper(controller, selectionDone: true, completion: waitAnimationEnd {
                self.reject(ERROR_CANNOT_SAVE_IMAGE_KEY, ERROR_CANNOT_SAVE_IMAGE_MSG, nil)
            })
            return
        }

        var exif: [String: Any]?
        if options["includeExif"] as? Bool == true {
            exif = CIImage(data: imageResult.data)?.properties
        }

        dismissCropper(controller, selectionDone: true, completion: waitAnimationEnd {
            self.resolve(self.createAttachmentResponse(filePath,
                                                    withExif: exif,
                                                    withSourceURL: self.croppingFile["sourceURL"] as? String ?? "",
                                                    withLocalIdentifier: self.croppingFile["localIdentifier"] as? String ?? "",
                                                    withFilename: self.croppingFile["filename"] as? String,
                                                    withWidth: imageResult.width,
                                                    withHeight: imageResult.height,
                                                    withMime: imageResult.mime,
                                                    withSize: imageResult.data.count,
                                                    withDuration: nil,
                                                    withData: (self.options["includeBase64"] as? Bool == true) ? imageResult.data.base64EncodedString() : nil,
                                                    withRect: cropRect,
                                                    withCreationDate: self.croppingFile["creationDate"] as? Date,
                                                    withModificationDate: self.croppingFile["modificationDate"] as? Date))
        })
    }

    // at the moment it is not possible to upload image by reading PHAsset
    // we are saving image and saving it to the tmp location where we are allowed to access image later
    func persistFile(_ data: Data) -> String? {
        let tmpDirFullPath = getTmpDirectory()
        let filePath = tmpDirFullPath.appendingPathComponent(UUID().uuidString).appending(".jpg")

        do {
            try data.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            return filePath
        } catch {
            return nil
        }
    }

    extension CGRect {
        func toDictionary() -> [String: CGFloat] {
            return [
                "x": self.origin.x,
                "y": self.origin.y,
                "width": self.width,
                "height": self.height
            ]
        }
    }

    extension UIColor {
        static func from(hexString: String) -> UIColor {
            var rgbValue: UInt64 = 0
            let scanner = Scanner(string: hexString)
            scanner.scanLocation = 1  // bypass '#' character
            scanner.scanHexInt64(&rgbValue)
            return UIColor(
                red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
                green: CGFloat((rgbValue & 0xFF00) >> 8) / 255.0,
                blue: CGFloat(rgbValue & 0xFF) / 255.0,
                alpha: 1.0
            )
        }
    }

    func cropImage(_ image: UIImage) {
        DispatchQueue.main.async {
            let cropVC: TOCropViewController
            if options["cropperCircleOverlay"] as? Bool == true {
                cropVC = TOCropViewController(croppingStyle: .circular, image: image)
            } else {
                cropVC = TOCropViewController(image: image)
                let widthRatio = options["width"] as? CGFloat ?? 0
                let heightRatio = options["height"] as? CGFloat ?? 0
                if widthRatio > 0 && heightRatio > 0 {
                    let aspectRatio = CGSize(width: widthRatio, height: heightRatio)
                    cropVC.customAspectRatio = aspectRatio
                }
                cropVC.aspectRatioLockEnabled = !(options["freeStyleCropEnabled"] as? Bool ?? false)
                cropVC.resetAspectRatioEnabled = !cropVC.aspectRatioLockEnabled
            }

            cropVC.title = options["cropperToolbarTitle"] as? String
            cropVC.delegate = self
            
            if let rawDoneButtonColor = options["cropperChooseColor"] as? String {
                cropVC.doneButtonColor = UIColor.from(hexString: rawDoneButtonColor)
            }
            if let rawCancelButtonColor = options["cropperCancelColor"] as? String {
                cropVC.cancelButtonColor = UIColor.from(hexString: rawCancelButtonColor)
            }
            
            cropVC.doneButtonTitle = options["cropperChooseText"] as? String
            cropVC.cancelButtonTitle = options["cropperCancelText"] as? String
            cropVC.rotateButtonsHidden = options["cropperRotateButtonsHidden"] as? Bool ?? false

            cropVC.modalPresentationStyle = .fullScreen
            if #available(iOS 15.0, *) {
                cropVC.modalTransitionStyle = .coverVertical
            }
            
            getRootVC().present(cropVC, animated: false, completion: nil)
        }
    }

    // Delegate methods for TOCropViewController
    func cropViewController(_ cropViewController: TOCropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
        imageCropViewController(cropViewController, didCropImage: image, usingCropRect: cropRect)
    }

    func cropViewController(_ cropViewController: TOCropViewController, didFinishCancelled cancelled: Bool) {
        dismissCropper(cropViewController, selectionDone: false) {
            if self.currentSelectionMode == .CROPPING {
                self.reject(ERROR_PICKER_CANCEL_KEY, ERROR_PICKER_CANCEL_MSG, nil)
            }
        }
    }
}
}
