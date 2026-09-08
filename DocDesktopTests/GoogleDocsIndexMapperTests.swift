import Foundation
import Testing
@testable import DocDesktop

struct GoogleDocsIndexMapperTests {
    @Test func insertAtEndUsesIndexBeforeSegmentEndWithoutDeleteRange() throws {
        let mapper = GoogleDocsIndexMapper()
        let segments = [
            GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 6), googleStartIndex: 1, googleEndIndex: 7, tabID: nil)
        ]

        let edit = try mapper.edit(from: "hello\n", to: "hello\ndf", segments: segments)

        #expect(edit.googleStartIndex == 6)
        #expect(edit.googleEndIndex == 6)
        #expect(edit.replacementText == "df")
    }

    @Test func insertAfterEmojiUsesUTF16Index() throws {
        let mapper = GoogleDocsIndexMapper()
        let original = "hi 😄\n"
        let segments = [
            GoogleDocsTextSegment(localRange: NSRange(location: 0, length: (original as NSString).length), googleStartIndex: 1, googleEndIndex: 7, tabID: nil)
        ]

        let edit = try mapper.edit(from: original, to: "hi 😄!\n", segments: segments)

        #expect(edit.googleStartIndex == 6)
        #expect(edit.googleEndIndex == 6)
        #expect(edit.replacementText == "!")
    }

    @Test func replaceTextKeepsGoogleRange() throws {
        let mapper = GoogleDocsIndexMapper()
        let segments = [
            GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 6), googleStartIndex: 1, googleEndIndex: 7, tabID: nil)
        ]

        let edit = try mapper.edit(from: "hello\n", to: "help\n", segments: segments)

        #expect(edit.googleStartIndex == 4)
        #expect(edit.googleEndIndex == 6)
        #expect(edit.replacementText == "p")
    }

    @Test func deleteAtSegmentEndClampsBeforeProtectedNewline() throws {
        let mapper = GoogleDocsIndexMapper()
        let segments = [
            GoogleDocsTextSegment(localRange: NSRange(location: 0, length: 6), googleStartIndex: 1, googleEndIndex: 7, tabID: nil)
        ]

        let edit = try mapper.edit(from: "hello\n", to: "", segments: segments)

        #expect(edit.googleStartIndex == 1)
        #expect(edit.googleEndIndex == 6)
        #expect(edit.replacementText == "")
    }
}
