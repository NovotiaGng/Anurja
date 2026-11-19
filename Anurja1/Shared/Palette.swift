import SwiftUI

extension Color {
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }

    static let cream = Color(hex: 0xFAF3EB)
    static let terracotta = Color(hex: 0xAA5A43)
    static let maroon = Color(hex: 0x7A1F2B)
    static let forest = Color(hex: 0x3B5B4B)
    static let sage = Color(hex: 0x5E7466)
    static let sand = Color(hex: 0xEEE2D6)
    static let blush = Color(hex: 0xE0BBA8)
    static let ink = Color(hex: 0x2E241F)
    static let muted = Color(hex: 0x8A7B70)
    static let pillGreen = Color(hex: 0x24382E)
    static let warmMid = Color(hex: 0xD9A68F)
    static let heroStart = Color(hex: 0xF7EBC8)
    static let heroEnd = Color(hex: 0xE8D4A8)
    static let paleDisc = Color(hex: 0xF5EDE2)
}
