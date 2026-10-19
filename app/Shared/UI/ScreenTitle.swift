import SwiftUI

/// A screen's title, drawn in its content and marked as a header. On tvOS the navigation bar keeps
/// its title pinned over content that scrolls under it, so screens hide the bar (`screenTitle(_:)`)
/// and draw this instead: above a list, or at the top of a grid so it scrolls away with it. On macOS
/// the window's toolbar shows the title, so this draws nothing.
struct ScreenTitle: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        #if os(tvOS)
        Text(title)
            .font(.title2).bold()
            .accessibilityAddTraits(.isHeader)
        #endif
    }
}

extension View {
    /// Names the screen for navigation and, on tvOS, hides the navigation bar. A pushed screen
    /// then shows its name with `ScreenTitle`; a tab's root screen is named by its tab.
    func screenTitle(_ title: String) -> some View {
        navigationTitle(title)
        #if os(tvOS)
            .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}
