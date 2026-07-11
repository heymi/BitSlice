import AppKit
import SwiftUI

// MARK: - Manual app entry

let model = AppViewModel()

let app = NSApplication.shared
app.setActivationPolicy(.regular)

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
window.backgroundColor = NSColor(red: 0.055, green: 0.057, blue: 0.071, alpha: 1)
window.minSize = NSSize(width: 1040, height: 700)
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
