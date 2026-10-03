import SwiftUI
import TokenometerCore
import TokenometerUI

struct MenuView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Color.clear.frame(height: 0).onAppear { model.openSettingsAction = { openSettings() } }
            if let snapshot = model.snapshot, !snapshot.providers.isEmpty {
                ForEach(snapshot.providers) { provider in
                    ProviderSectionView(snapshot: provider)
                    if provider.id != snapshot.providers.last?.id { Divider() }
                }
            } else {
                Text("No agent logs found yet").foregroundStyle(.secondary)
            }
            Divider()
            if let pending = model.updater.pendingVersion {
                Button("Tokenometer \(pending) is available. Update…") { model.updater.checkForUpdates() }
                    .buttonStyle(.link).font(.caption)
            }
            HStack {
                if let generated = model.snapshot?.generatedAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text("Updated \(Format.age(generated, now: context.date))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    model.requestRefresh(logChanged: false, force: true)
                } label: {
                    Image(systemName: model.isRefreshing ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath")
                }
                .buttonStyle(.borderless)
                .help("Refresh now")
                Button {
                    model.updater.checkForUpdates()
                } label: {
                    Image(systemName: model.updater.pendingVersion == nil ? "arrow.down.circle" : "arrow.down.circle.fill")
                        .foregroundStyle(model.updater.pendingVersion == nil ? .secondary : .primary)
                }
                .buttonStyle(.borderless)
                .disabled(!model.updater.canCheck)
                .help(model.updater.pendingVersion.map { "Update to \($0) available" } ?? "Check for Updates…")
                Button {
                    model.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                Button { NSApplication.shared.terminate(nil) } label: { Image(systemName: "power") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("q")
                    .help("Quit Tokenometer")
            }
        }
        .padding(12)
        .frame(width: 320)
    }
}
