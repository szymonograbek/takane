import SwiftUI
import UIKit

/// Hosts the playback engine's Metal layer in SwiftUI and keeps its drawable sized to the view.
struct VideoSurfaceView: UIViewRepresentable {
    let layer: CAMetalLayer

    func makeUIView(context: Context) -> LayerHostView {
        LayerHostView(metalLayer: layer)
    }

    func updateUIView(_ view: LayerHostView, context: Context) {}

    final class LayerHostView: UIView {
        private let metalLayer: CAMetalLayer

        init(metalLayer: CAMetalLayer) {
            self.metalLayer = metalLayer
            super.init(frame: .zero)
            backgroundColor = .black
            layer.addSublayer(metalLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layoutSubviews() {
            super.layoutSubviews()
            let scale = window?.screen.nativeScale ?? traitCollection.displayScale
            metalLayer.frame = bounds
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
    }
}
