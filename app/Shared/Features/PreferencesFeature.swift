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
        case setAudioLanguage(Language?)
        case setSubtitleLanguages(SubtitleLanguages)
        case setSubtitleStyle(SubtitleStyle)
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
        case .setAudioLanguage(let language):
            return change(state) { $0.languages.audio = language }
        case .setSubtitleLanguages(let languages):
            return change(state) { $0.languages.subtitles = languages }
        case .setSubtitleStyle(let style):
            return change(state) { $0.subtitleStyle = style }
        case .updateFailed(let error):
            state.failure = error
            return []
        }
    }

    /// Saves the edited preferences, unless they are not loaded yet or the edit changes nothing.
    private static func change(_ state: State, _ edit: (inout PlaybackPreferences) -> Void) -> [Effect] {
        guard var preferences = state.playback else { return [] }
        edit(&preferences)
        return preferences == state.playback ? [] : [.update(preferences)]
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
