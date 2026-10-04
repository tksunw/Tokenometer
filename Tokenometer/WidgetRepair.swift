import Foundation

/// Makes the widget pick up a new version of the app.
///
/// When the app bundle is replaced (a Sparkle update, a drag from the disk image), chronod, the
/// widget service, sees for a moment an extension with no app around it and drops it ("LS doesn't
/// have a containing bundle, removing existing version as a safeguard"). The widget then stays on
/// the old drawing, or goes blank when it is removed and added again. Re-registering the extension
/// and restarting chronod is what clears it, so the app does both once, the first time a new build
/// launches. Every app's widgets redraw for a second or two when that happens.
enum WidgetRepair {
    private static let key = "lastLaunchedBuild"

    static func runIfBuildChanged(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        guard let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
              defaults.string(forKey: key) != build
        else { return }
        defaults.set(build, forKey: key)
        guard let appex = bundle.builtInPlugInsURL?.appendingPathComponent("TokenometerWidget.appex"),
              FileManager.default.fileExists(atPath: appex.path)
        else { return }
        Task.detached(priority: .utility) {
            run("/usr/bin/pluginkit", ["-a", appex.path])
            run("/usr/bin/killall", ["chronod"])
        }
    }

    private static func run(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
    }
}
