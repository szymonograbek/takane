/// The library and account as core's profile and library hold them.
struct CoreLibraryService: LibraryService {
    let runtime: CoreRuntime

    func continueWatching() -> AsyncStream<[ContinueWatchingItem]> {
        runtime.observe(.continueWatchingPreview, as: ContinueWatchingState.self) { state in
            state.items.compactMap { item in
                MediaID(item.id).map { media in
                    ContinueWatchingItem(
                        media: media,
                        name: item.name,
                        offset: .milliseconds(item.state.timeOffset),
                        duration: .milliseconds(item.state.duration)
                    )
                }
            }
        }
    }

    func account() -> AsyncStream<Account> {
        runtime.observe(.ctx, as: CtxState.self) { ctx in
            ctx.profile.auth.map { .signedIn(email: $0.user.email) } ?? .anonymous
        }
    }
}
