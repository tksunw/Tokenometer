import SwiftUI
import TokenometerCore

@main
struct TokenometerApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
                .onAppear { model.requestRefresh(logChanged: false) }
        } label: {
            MenuBarLabel(snapshot: model.snapshot, style: model.settings.menuBarStyle, focus: model.menuBarFocus)
                .task { model.start(windowSources: [ClaudeUsageFile(), AntigravityLocalClient()]) }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: model.settings, model: model)
        }
    }
}
