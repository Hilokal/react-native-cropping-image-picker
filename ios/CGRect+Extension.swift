//
//  CGRect+Extension.swift
//  react-native-cropping-image-picker
//
//  Created by Hilokal on 2023/10/19.
//

import Foundation

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
