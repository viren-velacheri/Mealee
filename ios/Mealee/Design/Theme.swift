import SwiftUI

// Palette: https://coolors.co/f7fff6-bcebcb-87d68d-93b48b-8491a3
enum Palette {
    static let mist = Color(hex: 0xF7FFF6)
    static let mint = Color(hex: 0xBCEBCB)
    static let leaf = Color(hex: 0x87D68D)
    static let sage = Color(hex: 0x93B48B)
    static let slate = Color(hex: 0x8491A3)
    // The five swatches are all light. Text needs one deep tone; this is sage taken
    // down to 15% lightness so it still reads as part of the same family.
    static let ink = Color(hex: 0x1E2A22)

    static let attack: [Color] = [leaf, sage]
    static let defense: [Color] = [sage, slate]
    static let stamina: [Color] = [mint, leaf]
    static let speed: [Color] = [leaf, mint]
    static let focus: [Color] = [slate, sage]
    static let recovery: [Color] = [mint, sage]
}

enum TypeScale {
    static let display = Font.system(size: 40, weight: .bold, design: .rounded)
    static let title = Font.system(size: 26, weight: .bold, design: .rounded)
    static let heading = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let body = Font.system(size: 16, weight: .regular)
    static let label = Font.system(size: 13, weight: .semibold, design: .rounded)
    static let number = Font.system(size: 15, weight: .bold, design: .rounded).monospacedDigit()
    static let bigNumber = Font.system(size: 34, weight: .bold, design: .rounded).monospacedDigit()
    static let caption = Font.system(size: 12, weight: .medium)
}

enum Layout {
    static let corner: CGFloat = 28
    static let innerCorner: CGFloat = 18
    static let gutter: CGFloat = 20
    static let cardPadding: CGFloat = 18
}

enum Motion {
    static let bounce = Animation.spring(response: 0.45, dampingFraction: 0.62)
    static let settle = Animation.spring(response: 0.7, dampingFraction: 0.78)
    static let snappy = Animation.spring(response: 0.28, dampingFraction: 0.7)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}
