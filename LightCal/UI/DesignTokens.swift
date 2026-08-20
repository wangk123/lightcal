import SwiftUI

/// 设计令牌：全局唯一颜色/尺寸来源（spec 7.6）
enum DesignTokens {
    static let primary = Color(hex: 0x0891B2)
    static let accent = Color(hex: 0x059669)
    static let background = Color(hex: 0xECFEFF)
    static let destructive = Color(hex: 0xDC2626)
    static let aiAmber = Color(hex: 0xD97706)
    static let targetLine = Color(hex: 0x64748B)
    static let minTouchSize: CGFloat = 44
    static let touchGap: CGFloat = 8
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}
