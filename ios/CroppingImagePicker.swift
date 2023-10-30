@available(iOS 14.0, *)
@objc(CroppingImagePicker)
class CroppingImagePicker: NSObject, RCTBridgeModule {
    static func moduleName() -> String! {
        return "CroppingImagePicker"
    }
    
    var bridge: RCTBridge!
        
    @objc(openCamera:withResolver:withRejecter:)
    func openCamera(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        CroppingImagePickerImpl.shared.openCamera(options, resolver: resolver, rejecter: rejecter)
    }
    
    @objc(cleanSingle:withResolver:withRejecter:)
    func cleanSingle(_ path: String, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        CroppingImagePickerImpl.shared.cleanSingle(path, resolver: resolver, rejecter: rejecter)
    }
    
    @objc(clean:withRejecter:)
    func clean(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        CroppingImagePickerImpl.shared.clean(resolver: resolver, rejecter: rejecter)
    }
    
    @objc(openPicker:withResolver:withRejecter:)
    func openPicker(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        CroppingImagePickerImpl.shared.openPicker(options, resolver: resolver, rejecter: rejecter)
    }
    
    @objc(openCropper:withResolver:withRejecter:)
    func openCropper(_ options: [String: Any], resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        CroppingImagePickerImpl.shared.openCropper(options, bridge: bridge, resolver: resolver, rejecter: rejecter)
    }
}
