import AppKit
import Foundation
import Testing
@testable import DocDesktop

struct MarkdownStylerTests {
    @Test func keepsMarkdownSourceWhileStylingHeadings() throws {
        let markdown = "## Some header\n"
        let styled = MarkdownStyler().attributedString(for: markdown)

        #expect(styled.string == markdown)
        let markerColor = try #require(styled.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
        let contentFont = try #require(styled.attribute(.font, at: 3, effectiveRange: nil) as? NSFont)

        #expect(markerColor.alphaComponent < 0.6)
        #expect(contentFont.pointSize >= 24)
        #expect(contentFont.fontDescriptor.symbolicTraits.contains(.bold))
    }

    @Test func keepsMarkdownSourceWhileStylingInlineEmphasis() throws {
        let markdown = "This is **bold**, *italic*, and ~~gone~~.\n"
        let styled = MarkdownStyler().attributedString(for: markdown)

        #expect(styled.string == markdown)

        let boldIndex = (markdown as NSString).range(of: "bold").location
        let italicIndex = (markdown as NSString).range(of: "italic").location
        let strikeIndex = (markdown as NSString).range(of: "gone").location
        let boldFont = try #require(styled.attribute(.font, at: boldIndex, effectiveRange: nil) as? NSFont)
        let italicFont = try #require(styled.attribute(.font, at: italicIndex, effectiveRange: nil) as? NSFont)
        let strike = styled.attribute(.strikethroughStyle, at: strikeIndex, effectiveRange: nil) as? Int

        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))
        #expect(strike == NSUnderlineStyle.single.rawValue)
    }

    @Test func keepsMarkdownSourceWhileStylingLinksAndLists() throws {
        let markdown = "- Item\n1. Number\n[Open](https://example.com)\n"
        let styled = MarkdownStyler().attributedString(for: markdown)

        #expect(styled.string == markdown)
        let bulletStyle = try #require(styled.attribute(.paragraphStyle, at: 2, effectiveRange: nil) as? NSParagraphStyle)
        let linkIndex = (markdown as NSString).range(of: "Open").location
        let link = styled.attribute(.link, at: linkIndex, effectiveRange: nil) as? URL

        #expect(bulletStyle.headIndent > 0)
        #expect(link == URL(string: "https://example.com"))
    }

    @Test func returnContinuesBulletList() throws {
        let engine = MarkdownEditingEngine()
        let text = "- First"
        let replacement = try #require(engine.replacementForReturn(in: text, selectedRange: NSRange(location: 7, length: 0)))

        #expect(replacement.range == NSRange(location: 7, length: 0))
        #expect(replacement.text == "\n- ")
    }

    @Test func returnContinuesNestedBulletList() throws {
        let engine = MarkdownEditingEngine()
        let text = "  - Nested"
        let replacement = try #require(engine.replacementForReturn(in: text, selectedRange: NSRange(location: 10, length: 0)))

        #expect(replacement.text == "\n  - ")
    }

    @Test func returnContinuesNumberedListWithNextNumber() throws {
        let engine = MarkdownEditingEngine()
        let text = "9. Item"
        let replacement = try #require(engine.replacementForReturn(in: text, selectedRange: NSRange(location: 7, length: 0)))

        #expect(replacement.text == "\n10. ")
    }

    @Test func returnContinuesCheckboxListUnchecked() throws {
        let engine = MarkdownEditingEngine()
        let text = "[ ] Task"
        let replacement = try #require(engine.replacementForReturn(in: text, selectedRange: NSRange(location: 8, length: 0)))

        #expect(replacement.text == "\n[ ] ")
    }

    @Test func returnContinuesCheckboxListCheckedAsNewUncheckedItem() throws {
        let engine = MarkdownEditingEngine()
        let text = "[x] Done"
        let replacement = try #require(engine.replacementForReturn(in: text, selectedRange: NSRange(location: 8, length: 0)))

        #expect(replacement.text == "\n[ ] ")
    }

    @Test func returnOnEmptyListItemRemovesMarker() throws {
        let engine = MarkdownEditingEngine()
        let text = "- "
        let replacement = try #require(engine.replacementForReturn(in: text, selectedRange: NSRange(location: 2, length: 0)))

        #expect(replacement.range == NSRange(location: 0, length: 2))
        #expect(replacement.text == "")
        #expect(replacement.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test func tabIndentsListItem() throws {
        let engine = MarkdownEditingEngine()
        let text = "- Item"
        let replacement = try #require(engine.replacementForTab(in: text, selectedRange: NSRange(location: 2, length: 0), outdent: false))

        #expect(replacement.range == NSRange(location: 0, length: 0))
        #expect(replacement.text == "  ")
    }

    @Test func shiftTabOutdentsListItem() throws {
        let engine = MarkdownEditingEngine()
        let text = "  - Item"
        let replacement = try #require(engine.replacementForTab(in: text, selectedRange: NSRange(location: 4, length: 0), outdent: true))

        #expect(replacement.range == NSRange(location: 0, length: 2))
        #expect(replacement.text == "")
    }

    @Test func checkboxToggleChangesMarkerOnly() throws {
        let engine = MarkdownEditingEngine()
        let text = "[ ] Task"
        let replacement = try #require(engine.replacementForCheckboxToggle(in: text, location: 1))

        #expect(replacement.range == NSRange(location: 0, length: 3))
        #expect(replacement.text == "[x]")
        #expect(replacement.selectedRange == NSRange(location: 1, length: 0))
    }
}
