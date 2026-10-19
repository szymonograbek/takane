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
        // At large text sizes the title stacks above the list, which then gets the full width.
        let columns = textLayout == .large
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.sectionSpacing))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 60))
        columns {
            VStack(alignment: .leading, spacing: 12) {
                Text(request.title).font(.title2).bold().lineLimit(2)
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
                if sections.firstCandidate == nil {
                    if state.isLookingUp(request.video) {
                        CancellableProgress("Asking your add-ons…")
                    } else {
                        ContentUnavailableView {
                            Label("No Playable Streams", systemImage: "play.slash")
                        } description: {
                            Text("Your add-ons have nothing Takane can play for this. Torrent streams need a debrid add-on.")
                        } actions: {
                            // Also gives the screen something to focus, so Menu goes back from it.
                            Button("Try Again") { app.streams.send(.lookUp(request.video)) }
                        }
                    }
                } else {
                    StreamList(
                        sections: sections, title: request.playerTitle,
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
        .onAppear { app.streams.send(.lookUp(request.video)) }
        .onChange(of: isPlayingRequest) { _, playing in
            if playing { dismiss() }
        }
    }
}

extension StreamsScreen {
    /// A stream for this video got past opening.
    private var isPlayingRequest: Bool {
        app.player.state.session.map { $0.candidate.item == request.video && $0.phase != .opening } ?? false
    }
}

private struct StreamList: View {
    @Environment(AppContext.self) private var app
    let sections: [StreamSection]
    let title: String
    let resumeFrom: Duration
    /// Streams often arrive after the screen opens; focus then moves to the first one.
    @FocusState private var focused: StreamCandidate.ID?

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
                            .focused($focused, equals: candidate.id)
                            .accessibilityIdentifier("streams.row")
                        }
                    }
                } header: {
                    Text(section.addonName).padding(.bottom, Metrics.headerSpacing)
                }
            }
        }
        .accessibilityIdentifier("streams.list")
        .onChange(of: sections.firstCandidate, initial: true) { _, first in
            if focused == nil { focused = first }
        }
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
            Text(candidate.name ?? "Stream").font(.callout).bold().lineLimit(2)
            if let detail = candidate.description ?? candidate.filename {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension StreamsRequest {
    /// "Twin Peaks · S1 E3", or the movie's name.
    var playerTitle: String {
        video.playerTitle(title)
    }
}

extension StreamsFeature.State {
    /// Sources still answering, and sources with at least one stream this app can play, holding only
    /// those streams, in add-on order. Sources that failed or have nothing playable are left out.
    func sections(for item: PlayableID) -> [StreamSection] {
        guard case .lookingUp(item, let results?) = self else { return [] }
        return results.sources.compactMap { source in
            switch source.candidates {
            case .loading:
                return StreamSection(addon: source.addon, addonName: source.addonName, streams: .loading)
            case .loaded(let candidates):
                let playable = candidates.filter { $0.source != nil }
                return playable.isEmpty ? nil : StreamSection(addon: source.addon, addonName: source.addonName, streams: .loaded(playable))
            case .failed:
                return nil
            }
        }
    }

    func isLookingUp(_ item: PlayableID) -> Bool {
        guard case .lookingUp(item, _) = self else { return true }
        return isLookingUp
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
