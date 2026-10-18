#if os(macOS)
import AppKit
import SwiftUI

/// Hosts mpv's Metal layer in SwiftUI and keeps its drawable sized to the view.
struct MPVVideoView: NSViewRepresentable {
    let layer: MPVMetalLayer

    func makeNSView(context: Context) -> LayerHostView {
        LayerHostView(metalLayer: layer)
    }

    func updateNSView(_ view: LayerHostView, context: Context) {}

    final class LayerHostView: NSView {
        private let metalLayer: MPVMetalLayer

        init(metalLayer: MPVMetalLayer) {
            self.metalLayer = metalLayer
            super.init(frame: .zero)
            // Assigning the layer before `wantsLayer` makes this a layer-hosting view.
            layer = metalLayer
            wantsLayer = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            resizeDrawable()
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            resizeDrawable()
        }

        private func resizeDrawable() {
            let scale = window?.backingScaleFactor ?? 2
            metalLayer.frame = bounds
            metalLayer.contentsScale = scale
            metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        }
    }
}
#endif
