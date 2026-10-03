import SwiftUI
import TokenometerCore
import TokenometerUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    let model: AppModel

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { model.updater.automaticallyChecks },
                    set: { model.updater.automaticallyChecks = $0 }))
                Picker("Menu bar", selection: $settings.menuBarStyle) {
                    Text("Gauge").tag(MenuBarStyle.gauge)
                    Text("Bars").tag(MenuBarStyle.bars)
                    Text("Horizontal bar").tag(MenuBarStyle.horizontal)
                }
                if settings.menuBarStyle == .horizontal {
                    Picker("Show", selection: $settings.menuBarProvider) {
                        Text("Cycle every 10 seconds").tag(MenuBarProviderChoice.cycle)
                        ForEach(Provider.allCases) { provider in
                            Text(provider.displayName).tag(MenuBarProviderChoice(rawValue: provider.rawValue) ?? .cycle)
                        }
                    }
                }
                Toggle("Notify when a window passes 90%", isOn: $settings.notifyAtCritical)
            }
            ForEach(Provider.allCases) { provider in
                Section(provider.displayName) {
                    Toggle("Enabled", isOn: Binding(
                        get: { settings.visibility[provider] != .hide },
                        set: { settings.visibility[provider] = $0 ? nil : .hide }))
                    Toggle("Show even when no logs are found", isOn: Binding(
                        get: { settings.visibility[provider] == .show },
                        set: { settings.visibility[provider] = $0 ? .show : nil }))
                        .disabled(settings.visibility[provider] == .hide)
                    Picker("Account", selection: Binding(
                        get: { settings.accountOverrides[provider].map { $0 == .plan ? "plan" : "metered" } ?? "auto" },
                        set: { value in
                            switch value {
                            case "plan": settings.accountOverrides[provider] = .plan
                            case "metered": settings.accountOverrides[provider] = .metered
                            default: settings.accountOverrides[provider] = nil
                            }
                        })) {
                        Text("Detect").tag("auto")
                        Text("Plan (subscription)").tag("plan")
                        Text("Metered (API key)").tag("metered")
                    }
                    BudgetField(label: "Session budget (USD)", value: Binding(
                        get: { settings.budgets[provider]?.sessionUSD },
                        set: { settings.budgets[provider, default: Budget()].sessionUSD = $0 }))
                    BudgetField(label: "Weekly budget (USD)", value: Binding(
                        get: { settings.budgets[provider]?.weeklyUSD },
                        set: { settings.budgets[provider, default: Budget()].weeklyUSD = $0 }))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 560)
        .onChange(of: settings.visibility) { model.requestRefresh(logChanged: false) }
        .onChange(of: settings.accountOverrides) { model.requestRefresh(logChanged: false) }
        .onChange(of: settings.budgets) { model.requestRefresh(logChanged: false) }
    }
}

struct BudgetField: View {
    let label: String
    @Binding var value: Double?

    var body: some View {
        TextField(label, value: $value, format: .number.precision(.fractionLength(0...2)), prompt: Text("none"))
    }
}
