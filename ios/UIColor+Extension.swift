//
//  UIColor+Extension.swift
//  react-native-cropping-image-picker
//
//  Created by Hilokal on 2023/10/19.
//

import Foundation

extension UIColor {
    static func fromHex(hexString: String) -> UIColor {
        var rgbValue: UInt64 = 0
        let scanner = Scanner(string: hexString)
        scanner.currentIndex = scanner.string.index(scanner.currentIndex, offsetBy: 1)  // bypass '#' character
        scanner.scanHexInt64(&rgbValue)
        return UIColor(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0xFF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
