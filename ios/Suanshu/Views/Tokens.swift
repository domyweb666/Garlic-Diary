import SwiftUI
import UIKit

extension UIColor {
    static func hex(_ v: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                green: CGFloat((v >> 8) & 0xFF) / 255,
                blue: CGFloat(v & 0xFF) / 255,
                alpha: alpha)
    }
}

extension Color {
    /// 淺色、深色各給一個
    static func dual(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(uiColor: UIColor { tc in tc.userInterfaceStyle == .dark ? dark : light })
    }

    static func hex(_ v: UInt32) -> Color {
        Color(uiColor: .hex(v))
    }
}

/// 設計代號。對應網頁版的 CSS 變數：介面色全部走系統色，只有蒜頭本身有自己的顏色。
enum T {
    static let bg = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let fg = Color.primary
    static let fg2 = Color.secondary
    static let fg3 = Color(uiColor: .tertiaryLabel)
    static let sep = Color(uiColor: .separator)
    static let fill = Color(uiColor: .tertiarySystemFill)
    static let fill2 = Color(uiColor: .systemFill)
    static let accent = Color(uiColor: .systemPurple)
    static let onAccent = Color.white
    static let danger = Color(uiColor: .systemRed)
    static let leaf = Color(uiColor: .systemGreen)

    static let segGood = Color.dual(.hex(0xB566DC), .hex(0xB05BE0))
    static let segMid = Color.dual(.hex(0xE2CDEE), .hex(0x6B4A80))
    static let segBad = Color.dual(.hex(0xBDB8B4), .hex(0x5A5652))
    static let segEmpty = Color.dual(.hex(0xF7F2F9), .hex(0x2B2530))
    static let skin = Color.dual(.hex(0xEDE3D6), .hex(0x5B5048))
    static let edge = Color.dual(.hex(0x8E7A99), .hex(0xA794B3))
    static let root = Color.dual(.hex(0xB8A58F), .hex(0x8D7A66))
    static let seed = Color.dual(.hex(0xFFF8EA), .hex(0xF5E6CF))

    static func rate(_ r: Rate?) -> Color {
        guard let r else { return segEmpty }
        switch r {
        case .good: return segGood
        case .mid: return segMid
        case .bad: return segBad
        }
    }

    /// 三個選項按鈕的漸層
    static func choiceGradient(_ r: Rate) -> LinearGradient {
        let colors: [Color]
        switch r {
        case .good: colors = [.hex(0xC77FE6), .hex(0xAF52DE)]
        case .mid: colors = [.hex(0xD3B3E6), .hex(0xB58BCD)]
        case .bad: colors = [.hex(0xA9A6A1), .hex(0x8C8984)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static let cardRadius: CGFloat = 26
}
