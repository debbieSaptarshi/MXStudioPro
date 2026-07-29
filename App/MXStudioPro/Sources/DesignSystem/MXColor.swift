import SwiftUI

/// Color tokens from MXStudio Pro Figma Component Box.
public enum MXColor {
    // Neutrals
    public static let white = Color(hex: 0xF8F8F8)
    public static let lightGrey = Color(hex: 0xC8C8C8)
    public static let grey = Color(hex: 0x808690)
    public static let layer2 = Color(hex: 0x2F3238)
    public static let black = Color(hex: 0x17191A)
    public static let surface = Color(hex: 0x1A1C1E)
    public static let surfaceRaised = Color(hex: 0x23262A)
    public static let dark = Color(hex: 0x1A1C1E)

    // Accents / palette (Colors strip in Component Box)
    public static let accent = Color(hex: 0x7ED965)          // Green
    public static let primeInset = Color(hex: 0x5BB542)      // Prime button dark inset
    public static let teal = Color(hex: 0x65D9D5)
    public static let blue = Color(hex: 0x65D9D5)
    public static let purple = Color(hex: 0x6765D9)
    public static let lightPurple = Color(hex: 0xAD65D9)
    public static let pink = Color(hex: 0xD965B8)
    public static let red = Color(hex: 0xE85A5C)
    public static let orange = Color(hex: 0xFD6D35)

    public static let steelTop = Color(hex: 0x35383B)
    public static let steelBottom = Color(hex: 0x212326)

    public static let cinematicSteel = LinearGradient(
        colors: [steelTop, steelBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

public extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
