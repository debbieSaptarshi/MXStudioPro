import SwiftUI

/// Typography tokens from Figma (Helvetica Neue / Bebas Neue).
public enum MXFont {
    public static func header3() -> Font {
        .system(size: 16, weight: .medium)
    }

    public static func body2() -> Font {
        .system(size: 14, weight: .regular)
    }

    public static func body3() -> Font {
        .system(size: 12, weight: .regular)
    }

    public static func bigButton() -> Font {
        .system(size: 16, weight: .medium)
    }

    public static func mediumButton() -> Font {
        .system(size: 14, weight: .medium)
    }

    public static func smallButton() -> Font {
        .system(size: 12, weight: .medium)
    }

    public static func displayTitle() -> Font {
        .system(size: 28, weight: .bold, design: .default)
    }

    public static func sectionTitle() -> Font {
        .system(size: 16, weight: .medium, design: .default)
            .width(.condensed)
    }

    public static func nowPlayingSource() -> Font {
        .system(size: 16, weight: .regular, design: .default)
            .width(.condensed)
    }

    public static func trackTitle() -> Font {
        .system(size: 20, weight: .bold)
    }

    public static func caption() -> Font {
        .system(size: 10, weight: .regular)
    }

    /// Bebas-style condensed readout used on Studio details strip.
    public static func studioReadout() -> Font {
        .system(size: 16, weight: .regular, design: .default).width(.condensed)
    }

    public static func studioTrackName() -> Font {
        .system(size: 12, weight: .regular, design: .default).width(.condensed)
    }
}
