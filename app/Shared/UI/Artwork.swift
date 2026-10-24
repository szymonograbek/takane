import SwiftUI

/// An add-on image, filling its frame, with a quiet placeholder while it loads or when it fails.
struct Artwork: View {
    let url: URL?
    /// Shown on the placeholder when there is no image.
    var title: String?

    var body: some View {
        // Takes the size it is offered rather than the image's, so `aspectRatio` can shape it.
        Color.clear
            .overlay { image }
            .clipped()
    }

    private var image: some View {
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
    /// Where the line breaks, such as where chapters begin, as shares of its length.
    var breaks: [Double] = []
    /// Stretches tinted `Palette.skippable` over the progress, as shares of its length.
    var highlights: [Range<Double>] = []

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule().fill(.white.opacity(0.3))
                .overlay(alignment: .leading) {
                    Capsule().fill(Palette.text).frame(width: width * min(max(fraction, 0), 1))
                }
                .overlay(alignment: .leading) {
                    ForEach(highlights, id: \.lowerBound) { highlight in
                        Rectangle().fill(Palette.skippable)
                            .frame(width: width * (highlight.upperBound - highlight.lowerBound))
                            .offset(x: width * highlight.lowerBound)
                    }
                }
                .clipShape(.capsule)
                .mask(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle()
                        ForEach(breaks, id: \.self) { share in
                            Rectangle()
                                .frame(width: Metrics.progressBreak)
                                .offset(x: width * share - Metrics.progressBreak / 2)
                                .blendMode(.destinationOut)
                        }
                    }
                    .compositingGroup()
                }
        }
        .frame(height: height)
    }
}
