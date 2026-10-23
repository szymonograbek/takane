import Testing

struct SourceBrowserFeatureTests {
    private let source = SourceID("ab23cd45").require()
    private var root: SourceBrowserFeature.Folder { .init(source: source, id: nil) }
    private var shows: SourceBrowserFeature.Folder { .init(source: source, id: SourceFolderID("shows")) }
    private let showsEntry = SourceEntry.folder(SourceFolderID("shows"), name: Redacted("Shows"))

    @Test func listsTheFolderItWasOpenedOn() {
        var state = SourceBrowserFeature.State.loading(root)

        #expect(SourceBrowserFeature.reduce(&state, .listed(root, .success([showsEntry]))).isEmpty)

        #expect(state == .loaded(root, [showsEntry]))
    }

    @Test func dropsAnAnswerForAnotherFolder() {
        var state = SourceBrowserFeature.State.loading(root)

        #expect(SourceBrowserFeature.reduce(&state, .listed(shows, .success([]))).isEmpty)

        #expect(state == .loading(root))
    }

    @Test func aFailureCanBeRetried() {
        var state = SourceBrowserFeature.State.loading(shows)

        _ = SourceBrowserFeature.reduce(&state, .listed(shows, .failure(.unreachable)))
        #expect(state == .failed(shows, .unreachable))
        #expect(SourceBrowserFeature.reduce(&state, .retry) == [.list(shows)])
        #expect(state == .loading(shows))
        #expect(SourceBrowserFeature.reduce(&state, .retry).isEmpty)
        _ = SourceBrowserFeature.reduce(&state, .listed(shows, .success([showsEntry])))
        #expect(state == .loaded(shows, [showsEntry]))
    }

    @Test func onlyAnEmptyFolderIsListedAgain() {
        var state = SourceBrowserFeature.State.loaded(root, [showsEntry])
        #expect(SourceBrowserFeature.reduce(&state, .retry).isEmpty)
        #expect(SourceBrowserFeature.reduce(&state, .listed(root, .success([]))).isEmpty)
        #expect(state == .loaded(root, [showsEntry]))

        state = .loaded(root, [])
        #expect(SourceBrowserFeature.reduce(&state, .retry) == [.list(root)])
        #expect(state == .loading(root))
    }
}
