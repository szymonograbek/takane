import SwiftUI

/// The content tabs, as in Apple's player: their names sit among the transport bar's buttons and
/// the open tab shows below the bar. Selecting a name opens its tab and moves focus to what plays
/// now in it; with a tab open, focusing another name switches to it.
struct PlayerTabs: View {
    let session: PlayerFeature.Session
    /// Nil while only the names show.
    let open: PlayerFeature.Tab?
    var focus: FocusState<PlayerFocus?>.Binding
    let openTab: (PlayerFeature.Tab) -> Void
    let playEpisode: (Video) -> Void
    let playChapter: (Chapter) -> Void

    /// The names, for the transport bar's row of buttons.
    var names: some View {
        HStack(spacing: 20) {
            ForEach(session.tabs, id: \.self) { tab in
                Button {
                    openTab(tab)
                    focus.wrappedValue = session.playingFocus(in: tab)
                } label: {
                    Text(tab.title).fontWeight(tab == open ? .bold : .regular)
                }
                .focused(focus, equals: .tab(tab))
                .accessibilityIdentifier("player.tab.\(tab.name)")
                .accessibilityAddTraits(tab == open ? .isSelected : [])
            }
        }
    }

    var body: some View {
        switch open {
        case .info:
            PlayingInfo(session: session)
                .padding(.horizontal, Metrics.screenPadding)
        case .episodes:
            ScrollViewReader { shelf in
                episodes.onAppear { scrollToPlaying(session.candidate.item, in: shelf) }
            }
            // A sideways scroll view would otherwise take all the height, pushing the transport bar up.
            .fixedSize(horizontal: false, vertical: true)
        case .chapters:
            ScrollViewReader { shelf in
                chapters.onAppear { scrollToPlaying(session.currentChapter?.id, in: shelf) }
            }
            .fixedSize(horizontal: false, vertical: true)
        case nil:
            EmptyView()
        }
    }

    private var episodes: some View {
        let playing = session.candidate.item
        let season = session.playingVideo?.season
        return Shelf(title: season.map { $0 == 0 ? "Specials" : "Season \($0)" }) {
            ForEach(session.seasonEpisodes) { video in
                EpisodeCard(video: video, fallbackArtwork: session.meta?.backdrop, isPlaying: video.playable == playing) { still in
                    Button { playEpisode(video) } label: { still }
                        .cardButtonStyle()
                        .focused(focus, equals: .episode(video.playable))
                        .accessibilityIdentifier("player.episode.\(video.playable.rawValue)")
                }
                // The row is as tall as the cards it measured first, which can be shorter than this one.
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var chapters: some View {
        let current = session.currentChapter
        return Shelf {
            ForEach(session.chapters) { chapter in
                ChapterCard(chapter: chapter, isPlaying: chapter == current, focus: focus) { playChapter(chapter) }
            }
        }
    }

    /// Starts the shelf at the card of what plays now, where focus lands on entering the tab.
    private func scrollToPlaying(_ id: (some Hashable)?, in shelf: ScrollViewProxy) {
        guard let id else { return }
        // Once the lazy row has laid out its cards.
        Task { shelf.scrollTo(id, anchor: .leading) }
    }
}

/// The Info tab: the title, the episode, its description and the stream playing.
private struct PlayingInfo: View {
    let session: PlayerFeature.Session

    var body: some View {
        let video = session.playingVideo
        VStack(alignment: .leading, spacing: 10) {
            Text(session.meta?.name.rawValue ?? session.title.rawValue).font(.title3).bold()
            if case .episode(_, let season, let episode) = session.candidate.item {
                let name = video?.name.rawValue ?? ""
                Text("Season \(season), Episode \(episode)" + (name.isEmpty ? "" : " · \(name)"))
                    .font(.callout).foregroundStyle(Palette.secondary)
            }
            if let description = video?.overview ?? session.meta?.description {
                Text(description.rawValue)
                    .font(.callout).lineLimit(3)
                    .frame(maxWidth: Metrics.readingWidth, alignment: .leading)
            }
            if let stream = session.candidate.name {
                Label(stream.rawValue.split(whereSeparator: \.isNewline).joined(separator: " · "), systemImage: "play.rectangle")
                    .font(.caption).foregroundStyle(Palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("player.info")
    }
}

/// A chapter's start time and title.
private struct ChapterCard: View {
    let chapter: Chapter
    let isPlaying: Bool
    var focus: FocusState<PlayerFocus?>.Binding
    let select: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.captionSpacing) {
            Button(action: select) {
                Palette.surface
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .overlay {
                        Text(chapter.start.clock).font(.title2).monospacedDigit().foregroundStyle(Palette.text)
                    }
                    .clipShape(.rect(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .cardButtonStyle()
            .focused(focus, equals: .chapter(chapter.id))
            .accessibilityLabel("\(chapter.title.rawValue), \(chapter.start.clock)")
            .accessibilityIdentifier("player.chapter.\(chapter.id.number)")
            HStack(spacing: 8) {
                if isPlaying {
                    Image(systemName: "play.fill").foregroundStyle(Palette.red).accessibilityLabel("Playing")
                }
                Text(chapter.title.rawValue).bold().labelLineLimit()
            }
            .font(.caption)
        }
        .lockupFrame(.wide)
    }
}

extension PlayerFeature.Session {
    /// The episode or chapter playing, where focus goes on entering a tab.
    func playingFocus(in tab: PlayerFeature.Tab) -> PlayerFocus {
        switch tab {
        case .info: .tab(.info)
        case .episodes: .episode(candidate.item)
        case .chapters: currentChapter.map { .chapter($0.id) } ?? .tab(.chapters)
        }
    }
}

extension PlayerFeature.Tab {
    var title: String {
        switch self {
        case .info: "Info"
        case .episodes: "Episodes"
        case .chapters: "Chapters"
        }
    }

    /// How accessibility identifiers name it.
    fileprivate var name: String {
        switch self {
        case .info: "info"
        case .episodes: "episodes"
        case .chapters: "chapters"
        }
    }
}
