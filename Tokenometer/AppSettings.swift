import Foundation
import Observation
import ServiceManagement
import TokenometerCore
import TokenometerUI

/// User settings, persisted in UserDefaults. Read by the engine as `EngineSettings`.
@MainActor
@Observable
final class AppSettings {
    private let defaults = UserDefaults.standard

    var visibility: [Provider: ProviderVisibility] { didSet { save(visibility, key: "visibility") } }
    var accountOverrides: [Provider: AccountKind] { didSet { save(accountOverrides, key: "accountOverrides") } }
    var budgets: [Provider: Budget] { didSet { save(budgets, key: "budgets") } }
    var menuBarStyle: MenuBarStyle { didSet { defaults.set(menuBarStyle.rawValue, forKey: "menuBarStyle") } }
    var menuBarProvider: MenuBarProviderChoice { didSet { defaults.set(menuBarProvider.rawValue, forKey: "menuBarProvider") } }
    var notifyAtCritical: Bool {
        didSet {
            defaults.set(notifyAtCritical, forKey: "notifyAtCritical")
            if notifyAtCritical { Notifier.requestPermission() }
        }
    }
    var launchAtLogin: Bool {
        didSet {
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init() {
        visibility = Self.load(key: "visibility") ?? [:]
        accountOverrides = Self.load(key: "accountOverrides") ?? [:]
        budgets = Self.load(key: "budgets") ?? [:]
        menuBarStyle = MenuBarStyle(rawValue: UserDefaults.standard.string(forKey: "menuBarStyle") ?? "") ?? .gauge
        menuBarProvider = MenuBarProviderChoice(rawValue: UserDefaults.standard.string(forKey: "menuBarProvider") ?? "") ?? .cycle
        notifyAtCritical = UserDefaults.standard.bool(forKey: "notifyAtCritical")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var engineSettings: EngineSettings {
        EngineSettings(visibility: visibility, accountOverrides: accountOverrides, budgets: budgets)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
