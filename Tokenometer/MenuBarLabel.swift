import AppKit
import SwiftUI
import TokenometerCore
import TokenometerUI

/// The menu bar item: a gauge, bars, or a logo with a session and weekly bar, drawn into a colored NSImage (see MenuBarImage).
struct MenuBarLabel: View {
    let snapshot: Snapshot?
    let style: MenuBarStyle
    let focus: ProviderSnapshot?
    let showsWeekly: Bool
    let palette: StatusPalette

    var body: some View {
        if let providers = snapshot?.providers, !providers.isEmpty {
            Image(nsImage: MenuBarImage.render(providers, style: style, focus: focus, showsWeekly: showsWeekly, palette: palette))
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}
