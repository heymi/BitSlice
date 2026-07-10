import AVKit
import SwiftUI

// MARK: - Video Player Representable (used by ContentView)

struct VideoPlayerViewRepresentable: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let v = AVPlayerView(); v.player = player; v.controlsStyle = .none; v.showsFullScreenToggleButton = false; return v
    }
    func updateNSView(_ v: AVPlayerView, context: Context) { v.player = player }
}
