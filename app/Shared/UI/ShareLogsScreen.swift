import SwiftUI

/// This device's logs from a chosen time range, offered to a phone or computer on the same network
/// as an address and its QR code. Sharing stops when the screen goes.
struct ShareLogsScreen: View {
    @Environment(AppContext.self) private var app
    @State private var store: FeatureStore<LogSharingFeature>?

    var body: some View {
        ZStack {
            Palette.canvas.ignoresSafeArea()
            if let store {
                ShareLogsContent(store: store)
            }
        }
        .screenTitle("Share Logs")
        .onAppear {
            let store = store ?? FeatureStore(.idle, dependencies: LogSharingFeature.Dependencies(sharing: app.services.logSharing))
            self.store = store
            store.send(.appeared)
        }
        .onDisappear { store?.send(.disappeared) }
    }
}

private struct ShareLogsContent: View {
    let store: FeatureStore<LogSharingFeature>
    @State private var choosingWindow = false

    var body: some View {
        let window = store.state.window ?? .default
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            ScreenTitle("Share Logs")
            // In every state, so the screen always has something to focus.
            ChoiceMenu(
                title: "Time Range", label: window.name, systemImage: "clock",
                choices: LogWindow.allCases.map { (name: $0.name, value: $0) },
                selection: window, isPresented: $choosingWindow
            ) { store.send(.select($0)) }
            .accessibilityIdentifier("shareLogs.window")
            // Spans the width, so moving up from the key's button lands here, not on the tab bar.
            .frame(maxWidth: .infinity, alignment: .leading)
            #if os(tvOS)
            .focusSection()
            #endif
            Group {
                switch store.state {
                case .idle, .starting:
                    ProgressView()
                case .sharing(let link, _):
                    SharedLink(link: link)
                case .failed(_, let error):
                    ContentUnavailableView {
                        Label("Logs Not Shared", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error.message)
                    } actions: {
                        Button("Try Again") { store.send(.retry) }
                            .accessibilityIdentifier("shareLogs.retry")
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Keeps focus in the open time ranges.
            .disabled(choosingWindow)
        }
        .padding(.horizontal, Metrics.screenPadding)
        .choiceMenus()
        // Without it the screen's identifier would replace its controls' own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shareLogs.screen")
    }
}

/// The address beside its QR code, with what to do with it. At large text sizes the address goes below the code.
private struct SharedLink: View {
    @Environment(\.textLayout) private var textLayout
    let link: LogLink

    var body: some View {
        let address = link.url.rawValue.absoluteString
        let layout = switch textLayout {
        case .regular: AnyLayout(HStackLayout(spacing: Metrics.screenPadding))
        case .large: AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.sectionSpacing))
        }
        layout {
            QRCode(text: address)
                .frame(width: Metrics.qrCodeSize, height: Metrics.qrCodeSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                Text("Scan the code, or open this address on a phone or computer on the same network:")
                    .foregroundStyle(Palette.secondary)
                Text(address)
                    .font(.largeTitle.monospaced().weight(.semibold))
                    // One line reads as one address to type.
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .accessibilityIdentifier("shareLogs.url")
                Text("Sharing stops when you leave this screen.")
                    .font(.callout)
                    .foregroundStyle(Palette.secondary)
                if let key = Log.key {
                    LogKeyNote(key: key)
                }
            }
            .frame(maxWidth: Metrics.readingWidth, alignment: .leading)
        }
        // Spans the width below the time range, so moving down from it reaches the key's button.
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

/// The key that reveals what release logs hide, for the user to hand over if the developer asks. It
/// stays hidden until asked for, so a photo of the screen does not give it away, and hides again when
/// the screen goes. Debug builds hide nothing, so they have none.
private struct LogKeyNote: View {
    let key: LogKey
    @State private var isShown = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
            Text("Log Key").font(.headline)
            // Hidden, it draws placeholder characters, so neither the screen nor accessibility holds the key.
            Text(isShown ? key.text : "XXXX-XXXX-XXXX")
                .font(.largeTitle.monospaced().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .redacted(reason: isShown ? [] : .placeholder)
                .accessibilityIdentifier("shareLogs.key")
            Button(isShown ? "Hide Log Key" : "Show Log Key", systemImage: isShown ? "eye.slash" : "eye") {
                isShown.toggle()
            }
            .accessibilityIdentifier("shareLogs.showKey")
            Text("Lets the developer read the details the log hides, only if they ask for it. Never post it in an issue.")
                .font(.callout)
                .foregroundStyle(Palette.secondary)
        }
        .padding(.top, Metrics.headerSpacing)
        .onDisappear { isShown = false }
    }
}
