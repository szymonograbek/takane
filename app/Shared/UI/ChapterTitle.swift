import SwiftUI

/// The chapter at the playhead, named above it on the progress bar and kept within the bar's ends.
struct ChapterTitle: View {
    let title: String
    /// Where the playhead is, as a share of the bar's length.
    let at: Double
    @State private var size = CGSize.zero

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Text(title)
                .font(.caption).bold()
                .foregroundStyle(Palette.text)
                .lineLimit(1)
                .fixedSize()
                .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
                .offset(
                    x: min(max(width * at - size.width / 2, 0), max(width - size.width, 0)),
                    y: -size.height - Metrics.chapterTitleSpacing
                )
        }
    }
}
