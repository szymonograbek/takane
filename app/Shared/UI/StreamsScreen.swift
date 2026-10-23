import SwiftUI

/// The streams the add-ons offer for one movie or episode. Choosing one starts playback, from the
/// saved position when continue watching has one. Once it plays, this screen closes under the player,
/// so leaving the player lands on the title's details; a stream that fails returns here.
struct StreamsScreen: View {
    @Environment(AppContext.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.textLayout) private var textLayout
    let request: StreamsRequest

    var body: some View {
        let state = app.streams.state
        let sections = state.sections(for: request.video)
        let offers = state.offers(for: request.video)
        // At large text sizes the title stacks above the list, which then gets the full width.
        let columns = textLayout == .large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.sectionSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 60))
        columns {
            VStack(alignment: .leading, spacing: 12) {
                Text(request.title.rawValue).font(.title2).bold().lineLimit(2)
                if case .episode(_, let season, let episode) = request.video {
                    Text("Season \(season), Episode \(episode)").foregroundStyle(Palette.secondary)
                }
                if let resume = app.home.state.resumePosition(for: request.video) {
                    Label("Resumes at \(resume.clock)", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(Palette.secondary)
                }
            }
            .frame(width: textLayout == .large ? nil : Metrics.streamsInfoWidth, alignment: .leading)
            Group {
                if sections.firstCandidate == nil && offers.isEmpty {
                    if state.isLookingUp(request.video) {
                        CancellableProgress("Asking your add-ons…")
                    } else {
                        ContentUnavailableView {
                            Label("No Playable Streams", systemImage: "play.slash")
                        } description: {
                            Text("Your add-ons have nothing Takane can play for this.")
                        } actions: {
                            // Also gives the screen something to focus, so Menu goes back from it.
                            Button("Try Again") { lookUp() }
                        }
                    }
                } else {
                    StreamList(
                        sections: sections, offers: offers, title: request.playerTitle,
                        resumeFrom: app.home.state.resumePosition(for: request.video) ?? .zero
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(Metrics.screenPadding)
        .background {
            Artwork(url: request.backdrop, title: nil)
                .overlay(Palette.canvas.opacity(0.88))
                .ignoresSafeArea()
        }
        .onAppear { lookUp() }
        .onChange(of: isPlayingRequest) { _, playing in
            if playing { dismiss() }
        }
    }
}

extension StreamsScreen {
    private func lookUp() {
        app.streams.send(.lookUp(request.video, account: app.account.state.account))
    }

    /// A stream for this video got past opening.
    private var isPlayingRequest: Bool {
        app.player.state.session.map { $0.candidate.item == request.video && $0.phase != .opening } ?? false
    }
}

private struct StreamList: View {
    private enum Row: Hashable {
        case stream(StreamCandidate.ID)
        case offer(service: String)
    }

    @Environment(AppContext.self) private var app
    @Environment(\.openURL) private var openURL
    let sections: [StreamSection]
    let offers: [WatchOffer]
    let title: Redacted<String>
    let resumeFrom: Duration
    /// Streams often arrive after the screen opens; focus then moves to the first one.
    @FocusState private var focused: Row?
    /// An offer whose link nothing on this device opens, such as a service whose app is not installed.
    @State private var unopened: WatchOffer?

    var body: some View {
        List {
            ForEach(sections) { section in
                Section {
                    switch section.streams {
                    case .loading:
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .loaded(let candidates):
                        ForEach(candidates) { candidate in
                            Button {
                                app.player.send(.open(candidate, from: resumeFrom, title: title))
                            } label: {
                                StreamRow(candidate: candidate)
                            }
                            .focused($focused, equals: .stream(candidate.id))
                            .accessibilityIdentifier("streams.row")
                        }
                    }
                } header: {
                    Text(section.addonName).padding(.bottom, Metrics.headerSpacing)
                }
            }
            if !offers.isEmpty {
                Section {
                    ForEach(offers, id: \.service) { offer in
                        Button {
                            openURL(offer.link) { opened in
                                if !opened { unopened = offer }
                            }
                        } label: {
                            OfferRow(offer: offer)
                        }
                        .focused($focused, equals: .offer(service: offer.service))
                        .accessibilityIdentifier("streams.offer")
                    }
                } header: {
                    Text("Other Services").padding(.bottom, Metrics.headerSpacing)
                }
            }
        }
        .accessibilityIdentifier("streams.list")
        .alert(
            "Open \(unopened?.service ?? "the service") Yourself", isPresented: Binding { unopened != nil } set: { if !$0 { unopened = nil } },
            presenting: unopened
        ) { _ in
            Button("OK") {}
        } message: { offer in
            Text("Nothing on this device opens \(offer.service) links. Find the title in the \(offer.service) app.")
        }
        .onChange(of: firstRow, initial: true) { _, first in
            if focused == nil { focused = first }
        }
    }

    private var firstRow: Row? {
        sections.firstCandidate.map(Row.stream) ?? offers.first.map { .offer(service: $0.service) }
    }
}

/// One add-on in the stream list: still answering, or the streams Takane can play from it.
struct StreamSection: Identifiable {
    enum Streams {
        case loading
        /// Never empty.
        case loaded([StreamCandidate])
    }

    let addon: ManifestURL
    let addonName: String
    let streams: Streams

    var id: ManifestURL { addon }
}

extension [StreamSection] {
    /// The first stream listed, if any add-on has answered with one.
    var firstCandidate: StreamCandidate.ID? {
        lazy.compactMap { section in
            if case .loaded(let candidates) = section.streams { candidates.first?.id } else { nil }
        }.first
    }
}

private struct StreamRow: View {
    let candidate: StreamCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(candidate.name?.rawValue ?? "Stream").font(.callout).bold().lineLimit(2)
            if let detail = candidate.description?.rawValue ?? candidate.filename?.rawValue {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A service outside this app that has the title, and how it offers it.
private struct OfferRow: View {
    let offer: WatchOffer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(offer.service).font(.callout).bold().lineLimit(1)
            Text(offer.access.map(\.label).joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension WatchOffer.Access {
    fileprivate var label: String {
        switch self {
        case .subscription: "Subscription"
        case .free: "Free"
        case .addon(let name): name.map { "With \($0)" } ?? "Add-on"
        case .rent(let price): price.map { "Rent \($0)" } ?? "Rent"
        case .buy(let price): price.map { "Buy \($0)" } ?? "Buy"
        }
    }
}

extension StreamsRequest {
    /// "Twin Peaks · S1 E3", or the movie's name.
    var playerTitle: Redacted<String> {
        video.playerTitle(title)
    }
}

extension StreamsFeature.State {
    /// Sources still answering, and sources with at least one stream this app can play, holding only
    /// those streams, in add-on order. Sources that failed or have nothing playable are left out.
    func sections(for item: PlayableID) -> [StreamSection] {
        guard case .lookingUp(item, let results?, _) = self else { return [] }
        return results.sources.compactMap { source in
            switch source.candidates {
            case .loading:
                return StreamSection(addon: source.addon, addonName: source.addonName.rawValue, streams: .loading)
            case .loaded(let candidates):
                let playable = candidates.filter { $0.source != nil }
                return playable.isEmpty ? nil : StreamSection(addon: source.addon, addonName: source.addonName.rawValue, streams: .loaded(playable))
            case .failed:
                return nil
            }
        }
    }

    /// Offers found for the item. None while they load, or when they failed or were not looked up.
    func offers(for item: PlayableID) -> [WatchOffer] {
        guard case .lookingUp(item, _, .loaded(let offers)?) = self else { return [] }
        return offers
    }

    /// Streams or offers for the item are still on their way.
    func isLookingUp(_ item: PlayableID) -> Bool {
        guard case .lookingUp(item, _, let offers) = self else { return true }
        return isLookingUp || offers == .loading
    }
}

/// A pushed screen waiting on its content. Cancel goes back, and gives the screen something to
/// focus so Menu can go back too.
struct CancellableProgress: View {
    @Environment(\.dismiss) private var dismiss
    let label: LocalizedStringKey

    init(_ label: LocalizedStringKey) {
        self.label = label
    }

    var body: some View {
        VStack(spacing: Metrics.sectionSpacing) {
            ProgressView(label)
            Button("Cancel") { dismiss() }
                .accessibilityIdentifier("loading.cancel")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
