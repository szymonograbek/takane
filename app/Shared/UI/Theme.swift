import SwiftUI

/// Takane's colors. Burgundy is the brand; focus and text stay light, as tvOS draws them.
enum Palette {
    /// Screen backgrounds.
    static let canvas = Color(red: 0.043, green: 0.024, blue: 0.024)
    /// Rows, menus and cards resting on the canvas.
    static let surface = Color(red: 0.165, green: 0.024, blue: 0.024)
    /// The brand: the logo and the wash behind full-screen moments.
    static let burgundy = Color(red: 0.361, green: 0.039, blue: 0.071)
    /// Tint for controls and progress.
    static let red = Color(red: 0.702, green: 0.090, blue: 0.102)
    static let text = Color(red: 0.937, green: 0.910, blue: 0.871)
    /// Metadata and labels: the text color, dimmed.
    static let secondary = text.opacity(0.6)
    /// Subtitle text, pure white for contrast on any picture, over a dark translucent backing.
    static let subtitle = Color.white
    static let subtitleBacking = Color.black.opacity(0.6)

    /// Burgundy fading into the canvas from the top, behind sign-in and empty screens.
    static let wash = RadialGradient(
        colors: [burgundy, surface, canvas], center: .top, startRadius: 0, endRadius: 1_400
    )
}

/// Sizes that differ between the 10-foot tvOS screen and a macOS window.
enum Metrics {
    #if os(tvOS)
    static let posterWidth: CGFloat = 200
    static let wideCardWidth: CGFloat = 420
    static let shelfSpacing: CGFloat = 40
    static let sectionSpacing: CGFloat = 50
    static let screenPadding: CGFloat = 80
    static let heroHeight: CGFloat = 640
    static let cornerRadius: CGFloat = 12
    /// Room under a card for the lift it gets under focus.
    static let captionSpacing: CGFloat = 26
    /// The logo or symbol beside a settings list.
    static let emblemSize: CGFloat = 420
    /// Space between a section's title and its rows.
    static let headerSpacing: CGFloat = 20
    /// How far a focused list row grows past its resting bounds on each side.
    static let rowLift: CGFloat = 24
    /// The player's list of tracks or speeds.
    static let playerPanelWidth: CGFloat = 720
    static let playerPanelMaxHeight: CGFloat = 560
    static let playerPanelPadding: CGFloat = 30
    static let welcomeLogoSize: CGFloat = 300
    static let progressHeight: CGFloat = 5
    /// The player's progress bar while it has focus.
    static let focusedProgressHeight: CGFloat = 14
    static let subtitleStyle = Font.TextStyle.title2
    /// Space between the subtitles and the bottom of the picture.
    static let subtitleInset: CGFloat = 60
    /// Horizontal room inside the subtitle backing; a third of it above and below.
    static let subtitlePadding: CGFloat = 18
    #else
    static let posterWidth: CGFloat = 140
    static let wideCardWidth: CGFloat = 280
    static let shelfSpacing: CGFloat = 16
    static let sectionSpacing: CGFloat = 28
    static let screenPadding: CGFloat = 32
    static let heroHeight: CGFloat = 420
    static let cornerRadius: CGFloat = 10
    static let captionSpacing: CGFloat = 8
    static let emblemSize: CGFloat = 180
    static let headerSpacing: CGFloat = 8
    static let rowLift: CGFloat = 0
    static let playerPanelWidth: CGFloat = 320
    static let playerPanelMaxHeight: CGFloat = 360
    static let playerPanelPadding: CGFloat = 12
    static let welcomeLogoSize: CGFloat = 160
    static let progressHeight: CGFloat = 5
    static let focusedProgressHeight: CGFloat = 9
    static let subtitleStyle = Font.TextStyle.largeTitle
    static let subtitleInset: CGFloat = 28
    static let subtitlePadding: CGFloat = 10
    #endif
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
