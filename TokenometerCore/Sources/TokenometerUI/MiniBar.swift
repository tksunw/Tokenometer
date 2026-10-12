import SwiftUI
import TokenometerCore

/// The menu bar's tiny vertical bar: one per provider, session window percent.
public struct MiniBar: View {
    let percent: Double
    let base: Color

    public init(percent: Double, base: Color) {
        self.percent = percent
        self.base = base
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 1).fill(base.opacity(0.25))
                RoundedRectangle(cornerRadius: 1).fill(UsageLevel.tint(for: percent, base: base))
                    .frame(height: max(1, geo.size.height * min(max(percent, 0), 100) / 100))
            }
        }
        .frame(width: 5)
    }
}
