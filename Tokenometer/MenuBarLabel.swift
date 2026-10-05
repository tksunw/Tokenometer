import AppKit
import SwiftUI
import TokenometerCore
import TokenometerUI

/// The menu bar item: a gauge or bars, drawn into a colored NSImage (see MenuBarImage).
struct MenuBarLabel: View {
    let snapshot: Snapshot?
    let style: MenuBarStyle
    let focus: ProviderSnapshot?

    var body: some View {
        if let providers = snapshot?.providers, !providers.isEmpty {
            Image(nsImage: MenuBarImage.render(providers, style: style, focus: focus))
        } else {
            Image(systemName: "gauge.with.dots.needle.33percent")
        }
    }
}
