import AppKit
import SwiftUI

/// Right-click menu on the menu bar item. MenuBarExtra offers no secondary-click hook, so a local
/// event monitor catches right-clicks on the status bar window and pops an NSMenu there; left-click
/// still opens the usage popover.
@MainActor
final class StatusItemMenu: NSObject {
    private let model: AppModel
    private var monitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown]) { [weak self] event in
            guard let self, let window = event.window, window.className.contains("NSStatusBarWindow") else { return event }
            self.show(in: window)
            return nil
        }
    }

    private func show(in window: NSWindow) {
        let menu = NSMenu()
        menu.addItem(item("About Tokenometer", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(item("Check for Updates…", #selector(checkForUpdates)))
        menu.addItem(item("Settings…", #selector(settings)))
        menu.addItem(.separator())
        menu.addItem(item("Quit Tokenometer", #selector(quit)))
        guard let view = window.contentView else { return }
        // Popped inside the status bar window the menu would inherit its dark, wallpaper-driven look;
        // the app's appearance matches the system menus. Anchor at the bottom edge so it drops below.
        menu.appearance = NSApplication.shared.effectiveAppearance
        let button = view.subviews.first { $0 is NSStatusBarButton } ?? view
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY - 5), in: button)
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func about() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "Usage limits for Claude, Codex, Gemini, and Antigravity, read from the logs they already write.\nMIT licensed. Nothing leaves your Mac except the usage checks.",
                                         attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)]),
        ])
    }

    @objc private func checkForUpdates() {
        model.updater.checkForUpdates()
    }

    @objc private func settings() {
        model.openSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
