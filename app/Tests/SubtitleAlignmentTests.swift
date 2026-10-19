import Testing

struct SubtitleAlignmentTests {
    @Test func numpadRowsRunBottomToTopAndColumnsLeftToRight() {
        let alignments = (1...9).map { SubtitleAlignment(numpad: $0) }
        let expected: [SubtitleAlignment?] = [
            SubtitleAlignment(horizontal: .leading, vertical: .bottom),
            SubtitleAlignment(horizontal: .center, vertical: .bottom),
            SubtitleAlignment(horizontal: .trailing, vertical: .bottom),
            SubtitleAlignment(horizontal: .leading, vertical: .middle),
            SubtitleAlignment(horizontal: .center, vertical: .middle),
            SubtitleAlignment(horizontal: .trailing, vertical: .middle),
            SubtitleAlignment(horizontal: .leading, vertical: .top),
            SubtitleAlignment(horizontal: .center, vertical: .top),
            SubtitleAlignment(horizontal: .trailing, vertical: .top),
        ]
        #expect(alignments == expected)
    }

    @Test(arguments: [0, 10, -1])
    func rejectsKeysOffTheNumpad(_ key: Int) {
        #expect(SubtitleAlignment(numpad: key) == nil)
    }
}
