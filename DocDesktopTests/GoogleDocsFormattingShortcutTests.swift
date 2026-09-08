import Foundation
import Testing
@testable import DocDesktop

struct GoogleDocsFormattingShortcutTests {
    @Test func headingOneShortcutRemovesMarkerAndFormatsRange() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "# Title\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "Title")
        #expect(shortcut?.formattingRequests == [.heading(level: 1, tabID: nil, startIndex: 1, endIndex: 6)])
    }

    @Test func headingTwoShortcutDoesNotBecomeHeadingOne() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "## Title\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "Title")
        #expect(shortcut?.formattingRequests == [.heading(level: 2, tabID: nil, startIndex: 1, endIndex: 6)])
    }

    @Test func bulletShortcutRemovesMarkerAndCreatesBullets() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "- Item\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "Item")
        #expect(shortcut?.formattingRequests == [.bulletList(tabID: nil, startIndex: 1, endIndex: 5)])
    }

    @Test func numberedShortcutRemovesMarkerAndCreatesNumberedList() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "1. Item\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "Item")
        #expect(shortcut?.formattingRequests == [.numberedList(tabID: nil, startIndex: 1, endIndex: 5)])
    }

    @Test func checkboxShortcutRemovesMarkerAndCreatesCheckboxList() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "[ ] Item\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "Item")
        #expect(shortcut?.formattingRequests == [.checkboxList(tabID: nil, startIndex: 1, endIndex: 5)])
    }

    @Test func linkShortcutReplacesMarkdownWithLabelAndAppliesLink() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]
        let url = URL(string: "https://example.com")!

        let shortcut = mapper.shortcut(from: "\n", to: "[Site](https://example.com)\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "Site")
        #expect(shortcut?.formattingRequests == [.link(url: url, tabID: nil, startIndex: 1, endIndex: 5)])
    }
}
