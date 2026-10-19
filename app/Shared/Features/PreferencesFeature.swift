/// The preferences Settings edits.
enum PreferencesFeature: Feature {
    struct Dependencies: Sendable {
        let preferences: any PreferencesService
    }

    struct State: Equatable, Sendable {
        /// Nil until the provider reports them.
        var preferences: Preferences?
        var failure: PreferencesError?
    }

    enum Event: Sendable {
        case changed(Preferences)
        case setAudioLanguages(PreferredLanguages?)
        case setSubtitleLanguages(PreferredLanguages?)
        case setSubtitleStyle(SubtitleStyle)
        case setSeekStep(SeekStep)
        case updateFailed(PreferencesError)
    }

    enum Effect: Equatable, Sendable {
        /// Start it once, when the store is created.
        case observe
        case update(Preferences)
    }

    static func reduce(_ state: inout State, _ event: Event) -> [Effect] {
        switch event {
        case .changed(let preferences):
            state.preferences = preferences
            state.failure = nil
            return []
        case .setAudioLanguages(let languages):
            return change(state) { $0.languages.audio = languages }
        case .setSubtitleLanguages(let languages):
            return change(state) { $0.languages.subtitles = languages }
        case .setSubtitleStyle(let style):
            return change(state) { $0.subtitleStyle = style }
        case .setSeekStep(let step):
            return change(state) { $0.seekStep = step }
        case .updateFailed(let error):
            state.failure = error
            return []
        }
    }

    /// Saves the edited preferences, unless they are not loaded yet or the edit changes nothing.
    private static func change(_ state: State, _ edit: (inout Preferences) -> Void) -> [Effect] {
        guard var preferences = state.preferences else { return [] }
        edit(&preferences)
        return preferences == state.preferences ? [] : [.update(preferences)]
    }

    @MainActor
    static func run(_ effect: Effect, _ dependencies: Dependencies, _ send: @escaping @MainActor (Event) -> Void) async {
        switch effect {
        case .observe:
            for await preferences in dependencies.preferences.preferences() {
                send(.changed(preferences))
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
