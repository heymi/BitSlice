import AppKit
import SwiftUI

// MARK: - Manual app entry

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let model = AppViewModel()
// Apply saved theme after NSApplication exists (never before).
AppViewModel.applySystemAppearance(model.appSettings.appearance)

let menuCoordinator = ApplicationMenuCoordinator(model: model)
menuCoordinator.install(on: app)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
    styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
    backing: .buffered,
    defer: false
)
window.title = "BiCut"
window.titleVisibility = .hidden
window.titlebarAppearsTransparent = true
configureWindowDragging(window)
window.backgroundColor = NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.071, green: 0.071, blue: 0.078, alpha: 1)
        : NSColor(red: 0.93, green: 0.93, blue: 0.945, alpha: 1)
}
window.minSize = NSSize(width: 1100, height: 720)
window.contentView = NSHostingView(rootView: ContentView(model: model))
window.center()
window.setFrameAutosaveName("BiCutMainWindow")
window.makeKeyAndOrderFront(nil)
app.activate()

let windowDelegate = WindowDelegate(model: model)
window.delegate = windowDelegate

if CommandLine.arguments.count > 1 {
    let previewURL = URL(fileURLWithPath: CommandLine.arguments[1])
    Task { @MainActor in await model.loadVideo(from: previewURL) }
}

app.run()
