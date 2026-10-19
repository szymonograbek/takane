import Foundation

/// The episodes that come out on one day.
struct ReleaseDay: Identifiable, Hashable, Sendable {
    /// The start of the day.
    let day: Date
    /// How far off the day is: "Today", "Tomorrow", "In 3 days (Friday)".
    let label: String
    /// In the order they were given.
    let episodes: [UpcomingEpisode]

    var id: Date { day }
}

enum ReleaseSchedule {
    /// `episodes` grouped by the day of `calendar` they come out on, from the day of `today` on,
    /// earliest first, each day's in the order given. Each day is labeled by its distance from today:
    /// in days up to 13, in weeks up to 59 days, then in months. From 2 days on the label names the
    /// weekday, and in months the date too, since a month holds each weekday more than once.
    static func days(_ episodes: [UpcomingEpisode], today: Date, calendar: Calendar) -> [ReleaseDay] {
        let start = calendar.startOfDay(for: today)
        let byDay = Dictionary(grouping: episodes) { calendar.startOfDay(for: $0.released) }
        return byDay.keys.filter { $0 >= start }.sorted().map { day in
            ReleaseDay(
                day: day,
                label: label(day, from: start, calendar: calendar),
                episodes: byDay[day, default: []]
            )
        }
    }

    private static func label(_ day: Date, from today: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        let weekday = calendar.standaloneWeekdaySymbols[calendar.component(.weekday, from: day) - 1]
        switch days {
        case ...0: return "Today"
        case 1: return "Tomorrow"
        case 2...13: return "In \(days) days (\(weekday))"
        case 14...59: return "In \(days / 7) weeks (\(weekday))"
        default:
            // 60 days or more read as two months, even when a calendar month is still short of it.
            let months = max(2, calendar.dateComponents([.month], from: today, to: day).month ?? 0)
            let date = "\(calendar.monthSymbols[calendar.component(.month, from: day) - 1]) \(calendar.component(.day, from: day))"
            return "In \(months) months (\(weekday), \(date))"
        }
    }
}
