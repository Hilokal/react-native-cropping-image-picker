//
//  CIPError.swift
//  react-native-cropping-image-picker
//
//  Created by Hilokal on 2023/10/19.
//

import Foundation

struct CIPError {
    static let cannotRunCameraOnSimulatorKey = "E_PICKER_CANNOT_RUN_CAMERA_ON_SIMULATOR"
    static let cannotRunCameraOnSimulatorMsg = "Cannot run camera on simulator"

    static let noCameraPermissionKey = "E_NO_CAMERA_PERMISSION"
    static let noCameraPermissionMsg = "User did not grant camera permission."

    static let noLibraryPermissionKey = "E_NO_LIBRARY_PERMISSION"
    static let noLibraryPermissionMsg = "User did not grant library permission."
    
    static let notGrantedAccessToAssetsKey = "E_NOT_GRANTED_ACCESS"
    static let notGrantedAccessToAssetsMsg = "User has selected assets that have not been granted access."

    static let pickerCancelKey = "E_PICKER_CANCELLED"
    static let pickerCancelMsg = "User cancelled image selection"

    static let pickerNoDataKey = "E_NO_IMAGE_DATA_FOUND"
    static let pickerNoDataMsg = "Cannot find image data"

    static let cropperImageNotFoundKey = "E_CROPPER_IMAGE_NOT_FOUND"
    static let cropperImageNotFoundMsg = "Can't find the image at the specified path"

    static let cleanupErrorKey = "E_ERROR_WHILE_CLEANING_FILES"
    static let cleanupErrorMsg = "Error while cleaning up tmp files"

    static let cannotSaveImageKey = "E_CANNOT_SAVE_IMAGE"
    static let cannotSaveImageMsg = "Cannot save image. Unable to write to tmp location."

    static let cannotProcessVideoKey = "E_CANNOT_PROCESS_VIDEO"
    static let cannotProcessVideoMsg = "Cannot process video data"
    
    static let cannotOpenSettingsKey = "E_CANNOT_OPEN_SETTINGS"
    static let cannotOpenSettingsMsg = "Unable to open app settings"
    static let cannotOpenSettingsWrongUrlMsg = "Cannot handle URL for app settings"
}
