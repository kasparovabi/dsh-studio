import SwiftUI

// The reference builds its hierarchy out of tone rather than shadow, so the
// palette carries the whole design. Every surface here is a step on one
// neutral ramp, with a single deep green for identity and a single blue for
// the one control that is switched on.
enum Phone {
    static let radiusCard: CGFloat = 24
    static let radiusBubble: CGFloat = 20
    static let radiusComposer: CGFloat = 28
    static let control: CGFloat = 40
    static let margin: CGFloat = 16
}

extension Color {
    static let phoneGround = Color(light: 0xF2F2F4, dark: 0x0B0B0C)
    static let phoneCard = Color(light: 0xFFFFFF, dark: 0x161618)
    static let phoneWash = Color(light: 0xE9E9EB, dark: 0x202023)
    static let phoneControl = Color(light: 0xEFEFF1, dark: 0x1D1D20)
    static let phoneInk = Color(light: 0x111113, dark: 0xF5F5F7)
    static let phoneInkSoft = Color(light: 0x8A8A8E, dark: 0x8A8A8E)
    static let phoneStamp = Color(light: 0x9A96AE, dark: 0x76748A)
    static let phoneSlate = Color(light: 0x111113, dark: 0x000000)
    static let phoneGreen = Color(red: 0.07, green: 0.23, blue: 0.18)
    static let phoneRed = Color(red: 0.78, green: 0.16, blue: 0.16)
    static let phoneBlue = Color(red: 0.18, green: 0.42, blue: 1.0)

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

struct CircleControl: View {
    let system: String
    var body: some View {
        Image(systemName: system)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Color.phoneInk)
            .frame(width: Phone.control, height: Phone.control)
            .background(Circle().fill(Color.phoneControl))
    }
}
