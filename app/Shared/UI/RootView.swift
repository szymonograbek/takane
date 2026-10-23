import SwiftUI

/// Welcome on first launch, then the tabs. Playback covers everything while a stream is open.
struct RootView: View {
    @Environment(AppContext.self) private var app
    /// Set once the user signs in or chooses to continue without an account.
    @AppStorage("onboardingFinished") private var onboardingFinished = false

    var body: some View {
        Group {
            if onboardingFinished {
                MainTabs()
            } else {
                WelcomeScreen { onboardingFinished = true }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: app.account.state.account, initial: true) { _, account in
            if case .signedIn = account { onboardingFinished = true }
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: isPlaying) { PlayerScreen() }
        #else
        .overlay { if isPlaying.wrappedValue { PlayerScreen() } }
        #endif
    }

    private var isPlaying: Binding<Bool> {
        Binding(
            get: { app.player.state.candidate != nil },
            set: { presented in
                if !presented { app.player.send(.stop) }
            }
        )
    }
}

private enum MainTab: String {
    case home = "Home", library = "Library", calendar = "Calendar", search = "Search", settings = "Settings"
}

private struct MainTabs: View {
    @State private var tab = MainTab.home

    var body: some View {
        TabView(selection: $tab) {
            Tab("Home", systemImage: "house", value: .home) {
                RouteStack { HomeScreen() }
            }
            Tab("Library", systemImage: "books.vertical", value: .library) {
                RouteStack { LibraryScreen() }
            }
            Tab("Calendar", systemImage: "calendar", value: .calendar) {
                RouteStack { CalendarScreen() }
            }
            Tab(value: .search, role: .search) {
                RouteStack { SearchScreen() }
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                RouteStack { SettingsScreen() }
            }
        }
        .onChange(of: tab) { _, tab in Log.ui.info("tab → \(tab.rawValue)") }
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
}

/// A tab's navigation stack: the screens a title can lead to, each push and pop logged.
private struct RouteStack<Root: View>: View {
    @ViewBuilder let root: () -> Root
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            root().navigationDestination(for: Route.self) { route in
                switch route {
                case .details(let preview): DetailsScreen(preview: preview)
                case .streams(let request): StreamsScreen(request: request)
                case .genre(let filter): GenreScreen(filter: filter)
                case .sourceSettings: SourceSettings()
                case .source(let id): SourceScreen(id: id)
                case .sourceFolder(let folder, let name): SourceBrowserScreen(folder: folder, name: name)
                }
            }
        }
        .onChange(of: path) { old, new in
            if new.count > old.count, let pushed = new.last {
                Log.ui.info("push \(pushed)")
            } else {
                Log.ui.info("pop to \(new.last.map(String.init(describing:)) ?? "root")")
            }
        }
    }
}
