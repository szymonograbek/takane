import Foundation

/// A title's name and year as a folder or file names it, without the tags around them:
/// `Sintel (2010) [imdbid-tt1727587]`, `Sintel.2010.1080p.WEB-DL.x264` and `Sintel 2010` are all
/// Sintel from 2010.
struct ReleaseName: Equatable, Sendable {
    /// Empty when the name is nothing but tags.
    let title: String
    let year: Int?

    init(_ name: String) {
        var text = name.replacing(/\[[^\]]*\]|\{[^}]*\}/, with: " ").replacing("_", with: " ")
        // A name with spaces keeps its dots, as in `Mr. Robot`; one without uses them as spaces.
        if !text.contains(" ") { text = text.replacing(".", with: " ") }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        let named = Array(words.prefix { !Self.isTag($0) })
        let latest = Calendar(identifier: .gregorian).component(.year, from: .now) + 1
        // The year is the last one in parentheses, else the last bare one, never the first word,
        // so `2001 A Space Odyssey (1968)` and `1917.2019.1080p` keep their titles.
        let years = named.indices.dropFirst().compactMap { index in
            Self.year(in: named[index], before: latest).map { (index: index, year: $0.year, isEnclosed: $0.isEnclosed) }
        }
        let found = years.last(where: \.isEnclosed) ?? years.last
        title = named[..<(found?.index ?? named.count)].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -._:,"))
        year = found?.year
    }

    private static func year(in word: String, before latest: Int) -> (year: Int, isEnclosed: Bool)? {
        guard let match = word.wholeMatch(of: /(\()?((?:19|20)\d{2})(\))?/), let year = Int(match.2), year <= latest else { return nil }
        return (year, match.1 != nil && match.3 != nil)
    }

    /// What release names add after the title: resolution, source, codecs, audio, edition. Words
    /// that are also common in titles, such as `Web` or `Dual`, are left out.
    private static func isTag(_ word: String) -> Bool {
        let tag = #/
            (?i)
            (?: \d{3,4}[pi] | [48]k | uhd | hdr(?:10)?\+? | sdr | dovi
              | [xh]\.?26[45] | hevc | avc | av1 | xvid | divx
              | web-?dl | web-?rip | blu-?ray | bdrip | brrip | bdremux | remux | dvdrip | dvdscr | hdtv | hdrip
              | proper | repack | extended | unrated | remastered | imax | 10bit | 8bit
              | aac[\d.]* | e?ac3 | dts(?:-?hd)? | truehd | ddp?[\d.]+ | atmos )
            (?:-\w+)?
            /#
        return word.wholeMatch(of: tag) != nil
    }
}
