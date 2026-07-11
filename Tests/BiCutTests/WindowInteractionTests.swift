import AppKit
import Testing
@testable import BiCut

@Suite("Window interaction")
struct WindowInteractionTests {
    @Test @MainActor func interactiveContentDoesNotDragTheWindow() {
        let window = NSWindow()

        configureWindowDragging(window)

        #expect(window.isMovableByWindowBackground == false)
    }
}
