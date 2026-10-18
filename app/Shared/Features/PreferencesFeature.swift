/// The playback preferences Settings edits.
enum PreferencesFeature: Feature {
    struct Dependencies: Sendable {
        let preferences: any PreferencesService
    }

    struct State: Equatable, Sendable {
        /// Nil until the provider reports them.
        var playback: PlaybackPreferences?
        var failure: PreferencesError?
    }

    enum Event: Sendable {
        case playbackChanged(PlaybackPreferences)
        case setLanguage(TrackKind, Language?)
        case updateFailed(PreferencesError)
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observePlayback
        case update(PlaybackPreferences)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .playbackChanged(let preferences):
            state.playback = preferences
            state.failure = nil
            return []
        case .setLanguage(let kind, let language):
            guard var preferences = state.playback else { return [] }
            switch kind {
            case .audio: preferences.languages.audio = language
            case .subtitle: preferences.languages.subtitles = language
            }
            guard preferences != state.playback else { return [] }
            return [.update(preferences)]
        case .updateFailed(let error):
            state.failure = error
            return []
        }
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observePlayback:
            for await preferences in dependencies.preferences.playback() {
                send(.playbackChanged(preferences))
            }
        case .update(let preferences):
            do {
                try dependencies.preferences.update(preferences)
            } catch {
                send(.updateFailed(error))
            }
        }
    }
}
