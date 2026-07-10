import AppKit
import SwiftUI

// MARK: - Manual app entry

let model = AppViewModel()

let app = NSApplication.shared
app.setActivationPolicy(.regular)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
    styleMask: [.titled, .closable, .miniaturizable, .resizable],
    backing: .buffered,
    defer: false
)
window.title = "BiCut"
window.contentView = NSHostingView(rootView: ContentView(model: model))
window.center()
window.setFrameAutosaveName("BiCutMainWindow")
window.makeKeyAndOrderFront(nil)

let windowDelegate = WindowDelegate(model: model)
window.delegate = windowDelegate

app.run()
