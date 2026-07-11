import AppKit

@MainActor
func configureWindowDragging(_ window: NSWindow) {
    window.isMovableByWindowBackground = false
}
