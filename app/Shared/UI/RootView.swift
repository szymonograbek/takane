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

/// Where a tab's navigation stack can go.
enum Route: Hashable {
    case details(MetaPreview)
    case streams(StreamsRequest)
    case genre(GenreFilter)
}

/// What the streams screen looks up, and how it labels and resumes it.
struct StreamsRequest: Hashable {
    let video: PlayableID
    let title: String
    let backdrop: URL?
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            Tab("Home", systemImage: "house") {
                NavigationStack {
                    HomeScreen().withRoutes()
                }
            }
            Tab(role: .search) {
                NavigationStack {
                    SearchScreen().withRoutes()
                }
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
        }
        #if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
        #endif
    }
}

extension View {
    /// The screens a title can lead to, for any tab's stack.
    func withRoutes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case .details(let preview): DetailsScreen(preview: preview)
            case .streams(let request): StreamsScreen(request: request)
            case .genre(let filter): GenreScreen(filter: filter)
            }
        }
    }
}
