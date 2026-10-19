import Foundation
import Testing

struct LibraryFeatureTests {
    private let all = LibraryFeature.defaultFilter
    private let series = LibraryFilter(type: .series, sort: .name)

    private func contents(_ filter: LibraryFilter, _ titles: [MetaPreview], canLoadMore: Bool = false) -> LibraryContents {
        LibraryContents(filter: filter, types: [.movie, .series], titles: titles, canLoadMore: canLoadMore)
    }

    @Test func choosingAFilterLoadsItAndDropsContentsForAnotherOne() {
        let show = Fixture.preview("tt0944947", type: .series)
        var state = LibraryFeature.State.loading(all)
        #expect(LibraryFeature.reduce(&state, .select(all)).isEmpty)
        #expect(LibraryFeature.reduce(&state, .select(series)) == [.observe(series)])
        #expect(state == .loading(series))

        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt0111161")])))
        #expect(state == .loading(series))
        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(series, [show])))
        #expect(state == .loaded(contents(series, [show])))
    }

    @Test func moreLoadsOnlyWhileTheLibraryHasMore() {
        var state = LibraryFeature.State.loading(all)
        #expect(LibraryFeature.reduce(&state, .loadMore).isEmpty)
        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt1")], canLoadMore: true)))
        #expect(LibraryFeature.reduce(&state, .loadMore) == [.loadMore])
        _ = LibraryFeature.reduce(&state, .contentsChanged(contents(all, [Fixture.preview("tt1")], canLoadMore: false)))
        #expect(LibraryFeature.reduce(&state, .loadMore).isEmpty)
    }

    @Test func removingTakesOutAListedTitle() {
        let movie = Fixture.preview("tt0111161")
        var state = LibraryFeature.State.loaded(contents(all, [movie]))
        #expect(LibraryFeature.reduce(&state, .remove(movie.media)) == [.remove(movie)])
        #expect(LibraryFeature.reduce(&state, .remove(MediaID("tt9999999").require())).isEmpty)
        #expect(state == .loaded(contents(all, [movie])))
    }
}

struct CalendarFeatureTests {
    private let episode = UpcomingEpisode(
        show: Fixture.preview("tt0944947", type: .series), video: Fixture.episode, name: "Winter Is Coming", released: .distantFuture
    )

    @Test func appearingReloadsAndKeepsTheEpisodesShownUntilTheAnswer() {
        var state = CalendarFeature.State.loading
        #expect(CalendarFeature.reduce(&state, .appeared) == [.load])
        _ = CalendarFeature.reduce(&state, .episodesChanged(.loaded([episode])))
        #expect(state == .loaded([episode]))

        #expect(CalendarFeature.reduce(&state, .appeared) == [.load])
        _ = CalendarFeature.reduce(&state, .episodesChanged(.loading))
        #expect(state == .loaded([episode]))
        _ = CalendarFeature.reduce(&state, .episodesChanged(.failed(.addonFailed(reason: "offline"))))
        #expect(state == .loaded([episode]))
        _ = CalendarFeature.reduce(&state, .episodesChanged(.loaded([])))
        #expect(state == .loaded([]))
    }

    @Test func aFailedFirstLoadShowsTheErrorAndRetries() {
        var state = CalendarFeature.State.loading
        _ = CalendarFeature.reduce(&state, .episodesChanged(.failed(.addonFailed(reason: "offline"))))
        #expect(state == .failed(.addonFailed(reason: "offline")))
        #expect(CalendarFeature.reduce(&state, .retry) == [.load])
        #expect(state == .loading)
        #expect(CalendarFeature.reduce(&state, .retry).isEmpty)
    }
}

struct ReleaseScheduleTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: "America/New_York").require()
        return calendar
    }()

    /// Monday, 19 October 2026, 15:00 in New York.
    private var today: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15)).require()
    }

    private func episode(_ number: Int, inDays days: Int, hour: Int = 21) -> UpcomingEpisode {
        let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: today)).require()
        return UpcomingEpisode(
            show: Fixture.preview("tt0944947", type: .series),
            video: PlayableID("tt0944947:1:\(number)").require(),
            name: "Episode \(number)",
            released: calendar.date(bySettingHour: hour, minute: 30, second: 0, of: day).require()
        )
    }

    @Test func daysAreLabeledByHowFarOffTheyAre() {
        let offsets = [0, 1, 2, 13, 14, 59, 60, 92]
        let episodes = offsets.enumerated().map { episode($0.offset + 1, inDays: $0.element) }

        let days = ReleaseSchedule.days(episodes, today: today, calendar: calendar)

        #expect(days.map(\.label) == [
            "Today", "Tomorrow", "In 2 days (Wednesday)", "In 13 days (Sunday)", "In 2 weeks (Monday)",
            "In 8 weeks (Thursday)", "In 2 months (Friday, December 18)", "In 3 months (Tuesday, January 19)",
        ])
    }

    @Test func episodesGroupByLocalDayFromTodayOn() {
        let lateTonight = episode(2, inDays: 0, hour: 23)
        let earlierToday = episode(1, inDays: 0, hour: 9)
        let tomorrow = episode(3, inDays: 1)

        let days = ReleaseSchedule.days([episode(9, inDays: -1), earlierToday, lateTonight, tomorrow], today: today, calendar: calendar)

        #expect(days.map(\.episodes) == [[earlierToday, lateTonight], [tomorrow]])
        #expect(days.first?.day == calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
    }
}
