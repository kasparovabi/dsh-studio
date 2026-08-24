import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private func appearanceColor(light: NSColor, dark: NSColor) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
    })
}

private func nsColor(hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func themed(light: UInt32, dark: UInt32) -> Color {
    appearanceColor(light: nsColor(hex: light), dark: nsColor(hex: dark))
}

private func themedAlpha(light: UInt32, lightAlpha: CGFloat, dark: UInt32, darkAlpha: CGFloat) -> Color {
    appearanceColor(light: nsColor(hex: light, alpha: lightAlpha), dark: nsColor(hex: dark, alpha: darkAlpha))
}
#endif

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    #if os(macOS)
    static let inkPrimary = themed(light: 0x1A1D21, dark: 0xF1F3F6)
    static let inkSecondary = themed(light: 0x8A8F98, dark: 0x9198A3)
    static let accentOrange = themed(light: 0xF59527, dark: 0xF9A94A)
    static let accentPurple = themed(light: 0x8B5CF6, dark: 0xA78BFA)
    static let accentTeal = themed(light: 0x38BDF8, dark: 0x56CCF8)
    static let accentGreen = themed(light: 0x34C759, dark: 0x4ADE80)
    static let hairline = themedAlpha(light: 0x000000, lightAlpha: 0.06, dark: 0xFFFFFF, darkAlpha: 0.09)
    static let chipFill = themedAlpha(light: 0x000000, lightAlpha: 0.04, dark: 0xFFFFFF, darkAlpha: 0.07)
    static let chipFillStrong = themedAlpha(light: 0x000000, lightAlpha: 0.05, dark: 0xFFFFFF, darkAlpha: 0.12)
    static let onInk = themed(light: 0xFFFFFF, dark: 0x0E1013)
    static let cardFill = themedAlpha(light: 0xFFFFFF, lightAlpha: 0.64, dark: 0x14161A, darkAlpha: 0.40)
    static let cardShadow = themedAlpha(light: 0x000000, lightAlpha: 0.05, dark: 0x000000, darkAlpha: 0.35)
    // Code stays light-on-dark in both themes, so it needs a surface of its own
    // rather than inkPrimary, which inverts and would put white text on white.
    static let codeSurface = themed(light: 0x1A1D21, dark: 0x0B0D10)
    static let codeText = Color(hex: 0xE8EAED)
    static let codeLabel = Color.white.opacity(0.55)
    static let codeAction = Color.white.opacity(0.70)
    static let codeHeaderFill = Color.white.opacity(0.06)
    #else
    static let inkPrimary = Color(hex: 0x1A1D21)
    static let inkSecondary = Color(hex: 0x8A8F98)
    static let accentOrange = Color(hex: 0xF59527)
    static let accentPurple = Color(hex: 0x8B5CF6)
    static let accentTeal = Color(hex: 0x38BDF8)
    static let accentGreen = Color(hex: 0x34C759)
    static let hairline = Color.black.opacity(0.06)
    static let chipFill = Color.black.opacity(0.04)
    static let chipFillStrong = Color.black.opacity(0.05)
    static let onInk = Color.white
    static let cardFill = Color.white.opacity(0.64)
    static let cardShadow = Color.black.opacity(0.05)
    #endif
}

struct CardBackground: ViewModifier {
    var radius: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(Color.cardFill)
                    .shadow(color: Color.cardShadow, radius: 14, y: 5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.hairline, lineWidth: 1)
            )
    }
}

extension View {
    func card(radius: CGFloat = 18) -> some View {
        modifier(CardBackground(radius: radius))
    }
}
