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
    // Secondary text. Reads as the same family but clears AA on glass, where sage
    // measured 2.14:1 and slate 2.98:1.
    static let muted = Color(hex: 0x1E2A22).opacity(0.62)

    static let attack: [Color] = [leaf, sage]
    static let defense: [Color] = [sage, slate]
    static let stamina: [Color] = [mint, leaf]
    static let speed: [Color] = [leaf, mint]
    static let focus: [Color] = [slate, sage]
    static let recovery: [Color] = [mint, sage]
}

enum TypeScale {
    // Anchored to text styles, not point sizes, so every label grows with Dynamic Type.
    // The paired size is what each one measures at the default setting.
    static let display = Font.system(.largeTitle, design: .rounded).weight(.bold)      // 34
    static let title = Font.system(.title, design: .rounded).weight(.bold)             // 28
    static let heading = Font.system(.headline, design: .rounded)                      // 17
    static let body = Font.system(.callout)                                            // 16
    static let label = Font.system(.footnote, design: .rounded).weight(.semibold)      // 13
    static let number = Font.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit()
    static let bigNumber = Font.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit()
    static let caption = Font.system(.caption).weight(.medium)                         // 12
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
