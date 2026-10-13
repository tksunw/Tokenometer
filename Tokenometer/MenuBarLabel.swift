import AppKit
import SwiftUI
import TokenometerCore
import TokenometerUI

/// The menu bar item: a provider's logo with its session and weekly bar, drawn into a colored NSImage (see MenuBarImage).
struct MenuBarLabel: View {
    let snapshot: Snapshot?
    let focus: ProviderSnapshot?
    let showsWeekly: Bool
    let palette: StatusPalette

    var body: some View {
        if let providers = snapshot?.providers, !providers.isEmpty {
            Image(nsImage: MenuBarImage.render(providers, focus: focus, showsWeekly: showsWeekly, palette: palette))
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}
