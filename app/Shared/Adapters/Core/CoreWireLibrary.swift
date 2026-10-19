import Foundation

// Decodable views of core's library models: continue watching, the library and the calendar.

// MARK: - continue_watching_preview

struct ContinueWatchingState: Decodable, Sendable {
    /// A library item, flattened, with the number of new episodes core found for it.
    struct Item: Decodable, Sendable {
        let library: LibraryItem
        let notifications: Int

        init(from decoder: any Decoder) throws {
            library = try LibraryItem(from: decoder)
            notifications = try decoder.container(keyedBy: CodingKeys.self).decode(Int.self, forKey: .notifications)
        }

        private enum CodingKeys: String, CodingKey { case notifications }
    }

    let items: [Item]
}

// MARK: - library

struct LibraryItem: Decodable, Sendable {
    struct State: Decodable, Sendable {
        /// Milliseconds.
        let timeOffset: UInt64
        /// Milliseconds.
        let duration: UInt64
        /// The video watched last, such as `tt0944947:1:2`.
        let videoId: String?
        /// Counts each watch of a movie, or of any episode of a series; zero once marked unwatched.
        let timesWatched: UInt32

        private enum CodingKeys: String, CodingKey {
            case timeOffset, duration, timesWatched
            case videoId = "video_id"
        }
    }

    let id: String
    let name: String
    let type: String
    /// Decoded as text so one malformed URL drops the image instead of the item.
    let poster: String?
    let posterShape: String
    let removed: Bool
    /// Core keeps titles the user watched without adding them as removed temporary items.
    let temp: Bool
    let state: State

    /// The user added it and has not removed it.
    var isInLibrary: Bool { !removed && !temp }

    private enum CodingKeys: String, CodingKey {
        case id = "_id"
        case name, type, poster, posterShape, removed, temp, state
    }
}

/// core's `LibraryWithFilters`, which (unlike most core types) serializes `selectable` in snake_case.
struct LibraryState: Decodable, Sendable {
    struct Selected: Decodable, Sendable {
        let request: LibraryRequest
    }

    struct Selectable: Decodable, Sendable {
        struct TypeChoice: Decodable, Sendable {
            /// Nil for every type.
            let type: String?
        }

        /// The library's types, every type first.
        let types: [TypeChoice]
        /// Present while `LoadNextPage` would add titles.
        let nextPage: JSONValue?

        private enum CodingKeys: String, CodingKey {
            case types
            case nextPage = "next_page"
        }
    }

    /// Nil until the model is loaded.
    let selected: Selected?
    let selectable: Selectable
    /// Every page loaded so far.
    let catalog: [LibraryItem]
}

// MARK: - calendar

/// core's `Calendar` as the bridge cuts it: each show with the videos released from the day before
/// the state was read.
struct CalendarState: Decodable, Sendable {
    struct Month: Decodable, Sendable {
        let month: Int
        let year: Int
    }

    struct Show: Decodable, Sendable {
        let id: String
        let type: String
        let name: String
        let poster: String?
        let posterShape: String
        let background: String?
        let logo: String?
        let videos: [MetaDetailsState.Video]
    }

    /// Nil while unloaded.
    let selected: Month?
    /// One entry per add-on catalog asked for the library's shows.
    let metaItems: [ResourceLoadable<[Show]>]
}
