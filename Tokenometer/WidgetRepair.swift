import Foundation

/// Makes the widgets pick up a new version of the app.
///
/// When the app bundle is replaced (a Sparkle update, a drag from the disk image), chronod, the
/// widget service, sees for a moment an extension with no app around it and drops it ("LS doesn't
/// have a containing bundle, removing existing version as a safeguard"). The widget then stays on
/// the old drawing, or goes blank when it is removed and added again.
///
/// Worse, chronod asks the extension for its list of widgets the moment LaunchServices registers
/// the new bundle, and the extension process it keeps alive from the old version is what answers,
/// so a widget added in the new version is missing from the list, and chronod caches that list
/// under the new build number and never asks again (1.2.0 on a Mac that had 1.1.9: "query
/// returned 1 widget descriptors"). Re-registering alone does not help; chronod folds an
/// unregister and register with the same build number into one update and keeps the cache.
///
/// What clears both: unregister the extension, restart chronod so it forgets it, kill the old
/// extension process, register the extension again so chronod sees a new one and asks it afresh.
/// The app does that once, the first time a new build launches. Every app's widgets redraw for a
/// second or two when that happens.
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
            run("/usr/bin/pluginkit", ["-r", appex.path])
            run("/usr/bin/killall", ["chronod"])
            // chronod takes a moment to come back and read the registry without the extension.
            try? await Task.sleep(for: .seconds(4))
            run("/usr/bin/killall", ["TokenometerWidget"])
            run("/usr/bin/pluginkit", ["-a", appex.path])
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
