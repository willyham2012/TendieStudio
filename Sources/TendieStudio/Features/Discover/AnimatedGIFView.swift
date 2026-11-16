import SwiftUI
import UIKit
import ImageIO

/// Plays a GIF by streaming frames with ImageIO (CGAnimateImageDataWithBlock),
/// so only one decoded frame is in memory at a time. Stops when removed.
struct AnimatedGIFView: UIViewRepresentable {
    let data: Data
    func makeUIView(context: Context) -> GIFHostView { GIFHostView() }
    func updateUIView(_ v: GIFHostView, context: Context) { v.play(data) }
    static func dismantleUIView(_ v: GIFHostView, coordinator: ()) { v.stop() }
}

final class GIFHostView: UIView {
    private var playing: Data?
    override init(frame: CGRect) { super.init(frame: frame); layer.contentsGravity = .resizeAspect; layer.masksToBounds = true }
    required init?(coder: NSCoder) { fatalError() }

    func play(_ data: Data) {
        guard playing != data else { return }
        playing = data
        _ = CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, image, stop in
            guard let self, self.playing == data else { stop.pointee = true; return }
            self.layer.contents = image
        }
    }
    func stop() { playing = nil; layer.contents = nil }
}
