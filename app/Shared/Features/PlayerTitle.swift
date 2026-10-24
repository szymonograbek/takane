/// The title playing, from its metadata, and the tabs below the transport bar that show it.
extension PlayerFeature {
    /// A tab of content below the transport bar, in the order they show.
    enum Tab: Hashable, Sendable {
        /// The title, the episode and the stream.
        case info
        /// The playing episode's season.
        case episodes
        /// The file's chapters.
        case chapters
    }
}

extension PlayerFeature.Session {
    /// Keeps what the tracker found about the title and offers its next episode.
    mutating func receive(_ title: PlayingTitle?) {
        meta = title
        offer(title?.next)
    }

    /// The video playing, among the title's, once its metadata loaded.
    var playingVideo: Video? {
        meta?.videos.first { $0.playable == candidate.item }
    }

    /// The playing episode's season in order. Empty for a movie and until the metadata loads.
    var seasonEpisodes: [Video] {
        guard let meta, let season = playingVideo?.season else { return [] }
        return meta.videos.episodes(in: season)
    }

    /// Info always, then the tabs that have something to show: Episodes for a series, Chapters when
    /// the file has them.
    var tabs: [PlayerFeature.Tab] {
        [.info] + (seasonEpisodes.isEmpty ? [] : [.episodes]) + (chapters.isEmpty ? [] : [.chapters])
    }
}
