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

    @Test func headingMarkerOnExistingLineFormatsWithoutTextEdit() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 6), googleStartIndex: 1, googleEndIndex: 7, tabID: nil)]

        let shortcut = mapper.shortcut(from: "Title\n", to: "# Title\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "")
        #expect(shortcut?.formattingRequests == [.heading(level: 1, tabID: nil, startIndex: 1, endIndex: 6)])
    }

    @Test func bareBulletMarkerFormatsEmptyParagraph() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "-\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "")
        #expect(shortcut?.formattingRequests == [.bulletList(tabID: nil, startIndex: 1, endIndex: 2)])
    }

    @Test func bareNumberedMarkerFormatsEmptyParagraph() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]

        let shortcut = mapper.shortcut(from: "\n", to: "1.\n", segments: segments)

        #expect(shortcut?.edit.replacementText == "")
        #expect(shortcut?.formattingRequests == [.numberedList(tabID: nil, startIndex: 1, endIndex: 2)])
    }

    @Test func multiLinePasteRemovesAllMarkersAndCreatesSeparateFormattingRequests() throws {
        let mapper = GoogleDocsFormattingShortcutMapper()
        let segments = [GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 1), googleStartIndex: 1, googleEndIndex: 2, tabID: nil)]
        let pasted = """
        # Heading one

        ## Heading two

        - Bullet item

        1. Number item

        [ ] Checkbox item

        [Reference](https://example.com)

        """

        let shortcut = mapper.shortcut(from: "\n", to: pasted, segments: segments)

        #expect(shortcut?.normalizedText.contains("#") == false)
        #expect(shortcut?.normalizedText.contains("[Reference](https://example.com)") == false)
        #expect(shortcut?.normalizedText.contains("Heading one") == true)
        #expect(shortcut?.normalizedText.contains("Reference") == true)
        #expect(shortcut?.formattingRequests.count == 6)
        #expect(shortcut?.localFormattingRequests.count == 6)
    }
}
