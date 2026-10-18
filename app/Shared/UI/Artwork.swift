import SwiftUI

/// An add-on image, filling its frame, with a quiet placeholder while it loads or when it fails.
struct Artwork: View {
    let url: URL?
    /// Shown on the placeholder when there is no image.
    var title: String?

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    Palette.surface
                    if let title, url == nil || phase.isSettled {
                        Text(title)
                            .font(.caption).bold()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Palette.secondary)
                            .padding(8)
                    }
                }
            }
        }
    }
}

private extension AsyncImagePhase {
    var isSettled: Bool {
        if case .empty = self { false } else { true }
    }
}

/// How far into a title the viewer is.
struct ProgressLine: View {
    let fraction: Double
    var height = Metrics.progressHeight

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(.white.opacity(0.3))
                .overlay(alignment: .leading) {
                    Capsule().fill(Palette.text).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
        }
        .frame(height: height)
    }
}
