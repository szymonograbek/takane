import SwiftUI

/// Takane's colors. Burgundy is the brand; focus and text stay light, as tvOS draws them. Colors
/// that carry text or set a surface apart from the canvas get stronger under Increase Contrast.
enum Palette {
    /// Screen backgrounds.
    static let canvas = Color(red: 0.043, green: 0.024, blue: 0.024)
    /// Rows, menus and cards resting on the canvas.
    static let surface = Color(
        Color(red: 0.165, green: 0.024, blue: 0.024),
        increasedContrast: Color(red: 0.271, green: 0.047, blue: 0.047)
    )
    /// The brand: the logo and the wash behind full-screen moments.
    static let burgundy = Color(red: 0.361, green: 0.039, blue: 0.071)
    /// Tint for controls and progress.
    static let red = Color(red: 0.702, green: 0.090, blue: 0.102)
    static let text = Color(cream, increasedContrast: .white)
    /// Metadata and labels: the text color, dimmed.
    static let secondary = Color(cream.opacity(0.6), increasedContrast: .white.opacity(0.85))

    private static let cream = Color(red: 0.937, green: 0.910, blue: 0.871)

    /// Burgundy fading into the canvas from the top, behind sign-in and empty screens.
    static let wash = RadialGradient(
        colors: [burgundy, surface, canvas], center: .top, startRadius: 0, endRadius: 1_400
    )
    /// A dusk sky behind the subtitle preview, pale on the left and dark on the right, so one line
    /// of text crosses both.
    static let previewScene = LinearGradient(
        colors: [
            Color(red: 0.98, green: 0.90, blue: 0.76), Color(red: 0.89, green: 0.58, blue: 0.44),
            Color(red: 0.42, green: 0.20, blue: 0.30), Color(red: 0.06, green: 0.05, blue: 0.10),
        ],
        startPoint: .leading, endPoint: .trailing
    )
}

private extension Color {
    /// `regular`, or `increased` while the viewer has Increase Contrast on.
    init(_ regular: Color, increasedContrast increased: Color) {
        #if os(tvOS)
        let regular = UIColor(regular), increased = UIColor(increased)
        self.init(uiColor: UIColor { traits in
            traits.accessibilityContrast == .high ? increased : regular
        })
        #else
        let regular = NSColor(regular), increased = NSColor(increased)
        self.init(nsColor: NSColor(name: nil) { appearance in
            let highContrast: [NSAppearance.Name] = [.accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]
            guard let match = appearance.bestMatch(from: [.aqua, .darkAqua] + highContrast) else { return regular }
            return highContrast.contains(match) ? increased : regular
        })
        #endif
    }
}

/// Sizes that differ between the 10-foot tvOS screen and a macOS window.
enum Metrics {
    #if os(tvOS)
    /// A wide card outside a shelf, such as Up Next in the player.
    static let wideCardWidth: CGFloat = 420
    static let shelfSpacing: CGFloat = 40
    static let sectionSpacing: CGFloat = 50
    static let screenPadding: CGFloat = 80
    static let heroHeight: CGFloat = 640
    /// The widest a block of text runs before lines get too long to follow.
    static let readingWidth: CGFloat = 1200
    static let cornerRadius: CGFloat = 12
    /// Room under a card for the lift it gets under focus.
    static let captionSpacing: CGFloat = 26
    /// The logo or symbol beside a settings list.
    static let emblemSize: CGFloat = 420
    /// Space between a section's title and its rows.
    static let headerSpacing: CGFloat = 20
    /// How far a focused list row grows past its resting bounds on each side.
    static let rowLift: CGFloat = 24
    /// Room between a settings row's text and the sides of its focus platter, so the text clears
    /// the platter's rounded ends.
    static let rowPadding: CGFloat = 40
    /// Room above and below a row's text inside its focus platter.
    static let rowVerticalPadding: CGFloat = 18
    /// The player's list of tracks or speeds.
    static let playerPanelWidth: CGFloat = 720
    static let playerPanelMaxHeight: CGFloat = 560
    static let playerPanelPadding: CGFloat = 30
    /// The choices a `ChoiceMenu` opens.
    static let choiceMenuWidth: CGFloat = 560
    static let welcomeLogoSize: CGFloat = 300
    /// A QR code a phone scans from across the room.
    static let qrCodeSize: CGFloat = 440
    static let progressHeight: CGFloat = 5
    /// The player's progress bar while it has focus.
    static let focusedProgressHeight: CGFloat = 14
    /// The color dot beside a subtitle color choice.
    static let swatchSize: CGFloat = 36
    /// How strongly an unwatched episode's still blurs while spoilers are hidden.
    static let spoilerBlurRadius: CGFloat = 24
    #else
    static let wideCardWidth: CGFloat = 280
    static let shelfSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let screenPadding: CGFloat = 32
    static let heroHeight: CGFloat = 420
    static let readingWidth: CGFloat = 640
    static let cornerRadius: CGFloat = 10
    static let captionSpacing: CGFloat = 8
    static let emblemSize: CGFloat = 180
    static let headerSpacing: CGFloat = 8
    static let rowLift: CGFloat = 0
    static let rowPadding: CGFloat = 10
    static let rowVerticalPadding: CGFloat = 4
    static let playerPanelWidth: CGFloat = 320
    static let playerPanelMaxHeight: CGFloat = 360
    static let playerPanelPadding: CGFloat = 12
    static let choiceMenuWidth: CGFloat = 260
    static let welcomeLogoSize: CGFloat = 160
    static let qrCodeSize: CGFloat = 220
    static let progressHeight: CGFloat = 5
    static let focusedProgressHeight: CGFloat = 9
    static let swatchSize: CGFloat = 14
    static let spoilerBlurRadius: CGFloat = 16
    #endif

    /// The title column beside the stream list.
    static let streamsInfoWidth: CGFloat = 520

    // Subtitles scale with the picture rather than the screen, so the preview in Settings is the
    // player's overlay in miniature.
    /// Text size at 100 %, as a fraction of the picture's height.
    static let subtitleTextHeight: CGFloat = 0.053
    /// Horizontal room inside the subtitle backing, as a fraction of the text size; a third of it
    /// above and below.
    static let subtitlePadding: CGFloat = 0.32
    /// Outline thickness, as a fraction of the text size.
    static let subtitleOutline: CGFloat = 0.06
}

/// How the text size shapes layouts. At accessibility sizes (Large Text on tvOS, the largest
/// Dynamic Type sizes on macOS) screens trade density for room: shelves hold fewer lockups, labels
/// wrap and side-by-side columns stack.
enum TextLayout {
    case regular
    case large
}

extension EnvironmentValues {
    var textLayout: TextLayout {
        dynamicTypeSize.isAccessibilitySize ? .large : .regular
    }
}

extension View {
    /// One line for a label at regular text sizes, so rows stay even; as many as it needs at large ones.
    func labelLineLimit() -> some View {
        modifier(LabelLineLimit())
    }
}

private struct LabelLineLimit: ViewModifier {
    @Environment(\.textLayout) private var textLayout

    func body(content: Content) -> some View {
        switch textLayout {
        case .regular: content.lineLimit(1)
        case .large: content.lineLimit(nil)
        }
    }
}

/// The kinds of lockup a shelf holds. Each is as wide as a column of Apple's tvOS grid, so a
/// shelf's first and last lockups line up with the screen's margins.
enum Lockup {
    /// Posters: 260 pt on the TV, 410 pt at large text sizes.
    case poster
    /// 16:9 artwork: 410 pt on the TV, 560 pt at large text sizes.
    case wide

    func columns(_ textLayout: TextLayout) -> Int {
        switch (self, textLayout) {
        case (.poster, .regular): 6
        case (.poster, .large): 4
        case (.wide, .regular): 4
        case (.wide, .large): 3
        }
    }
}

/// Takane's logo, a mountain with a play button, `size` points wide. Generated with
/// `scripts/make-icons.swift` from `assets/logo.png`, with the app icons.
struct AppLogo: View {
    var size: CGFloat = 120

    var body: some View {
        Image("Logo")
            .resizable()
            .scaledToFit()
            .frame(width: size)
            .accessibilityLabel("Takane")
    }
}
