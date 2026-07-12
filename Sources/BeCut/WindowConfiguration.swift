import AppKit
import SwiftUI

@MainActor
func configureWindowDragging(_ window: NSWindow) {
    window.isMovableByWindowBackground = false
}

@MainActor
final class SettingsWindowCoordinator {
    static let shared = SettingsWindowCoordinator()

    private var windowController: NSWindowController?

    func show(model: AppViewModel) {
        let settingsView = AppSettingsView(model: model)

        if let window = windowController?.window {
            window.contentView = NSHostingView(rootView: settingsView)
            window.title = title(for: model.appSettings.language)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = title(for: model.appSettings.language)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1)
                : NSColor(red: 0.93, green: 0.93, blue: 0.945, alpha: 1)
        }
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.setFrameAutosaveName("BeCutSettingsWindow")
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 480)

        let controller = NSWindowController(window: window)
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshTitle(language: AppLanguage) {
        windowController?.window?.title = title(for: language)
    }

    private func title(for language: AppLanguage) -> String {
        language.t("Settings", "设置")
    }
}

@MainActor
final class ApplicationMenuCoordinator: NSObject {
    private let model: AppViewModel
    private static weak var shared: ApplicationMenuCoordinator?

    init(model: AppViewModel) {
        self.model = model
        super.init()
        Self.shared = self
    }

    func install(on application: NSApplication) {
        rebuildMenu(on: application, language: model.appSettings.language)
    }

    static func refreshMenuTitles(language: AppLanguage) {
        guard let shared, let application = NSApp else { return }
        shared.rebuildMenu(on: application, language: language)
    }

    private func rebuildMenu(on application: NSApplication, language: AppLanguage) {
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "BeCut")

        let settingsItem = NSMenuItem(
            title: language.t("Settings…", "设置…"),
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        settingsItem.isEnabled = true
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())
        applicationMenu.addItem(
            withTitle: language.t("Quit BeCut", "退出 BeCut"),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ).target = application

        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        application.mainMenu = mainMenu
    }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowCoordinator.shared.show(model: model)
    }
}
