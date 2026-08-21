import SwiftUI

struct PhoneMeter: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        if let pressure = app.contextPressure {
            HStack(spacing: 8) {
                Capsule()
                    .fill(Color.phoneStamp.opacity(0.25))
                    .frame(width: 58, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint(pressure.fraction))
                            .frame(width: 58 * pressure.fraction, height: 4)
                    }
                Text("\(Int(pressure.fraction * 100))% context")
                Text("·")
                Text(short(app.stats.totalTokens) + " tokens")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.phoneInkSoft)
            .monospacedDigit()
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.phoneControl))
            .padding(.top, 8)
        }
    }

    private func tint(_ fraction: Double) -> Color {
        if fraction > 0.9 { return .phoneRed }
        if fraction > 0.75 { return .phoneAmber }
        return .phoneGreen
    }

    private func short(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return "\(value / 1_000)k"
        }
        return "\(value)"
    }
}
