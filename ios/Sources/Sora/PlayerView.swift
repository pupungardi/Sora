import AVFoundation
import SwiftUI

/// Thin AVPlayer host used while Sora only plays direct URLs / HLS.
///
/// TODO(cursor): swap this for MPVKit once the engine path is proven.
/// MPVKit is already declared as an SPM dependency in `project.yml`, so the
/// work is: replace `PlayerView` with an `MPVKit`-backed UIView that loads the
/// same loopback URL, and delete the AVPlayer code here. Keep the `PlayerModel`
/// surface (`load(url:)`, `pause()`, `teardown()`) unchanged so the UI and the
/// engine wiring do not need to move.
struct PlayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerUIView {
        let view = PlayerUIView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerUIView, context: Context) {
        uiView.playerLayer.player = player
    }
}

/// `AVPlayerLayer` needs its owning view to keep the layer class in sync with
/// layout, otherwise the video stays at its first size after rotation.
final class PlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // Safe by construction: `layerClass` above.
        layer as! AVPlayerLayer
    }
}
