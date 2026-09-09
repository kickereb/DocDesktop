import AppKit
import Foundation
import Testing
@testable import DocDesktop

struct GoogleDocsRenderingTests {
    @Test func parserPreservesRichTextStylesFromGoogleDocs() throws {
        let document = try decodeDocument(richDocumentJSON)
        let parsed = GoogleDocsParser().parse(document)
        let text = parsed.attributedText
        let fullText = text.string

        #expect(fullText.contains("Project Plan"))
        #expect(fullText.contains("Requirements"))
        #expect(fullText.contains("This is important and urgent 😄."))
        #expect(fullText.contains("First item"))
        #expect(fullText.contains("Nested item"))
        #expect(fullText.contains("Number item"))

        let titleFont = try font(in: text, matching: "Project Plan")
        #expect(titleFont.pointSize >= 30)
        #expect(titleFont.fontDescriptor.symbolicTraits.contains(.bold))

        let headingFont = try font(in: text, matching: "Requirements")
        #expect(headingFont.pointSize >= 24)
        #expect(headingFont.fontDescriptor.symbolicTraits.contains(.bold))

        let boldFont = try font(in: text, matching: "important")
        #expect(boldFont.fontDescriptor.symbolicTraits.contains(.bold))

        let italicFont = try font(in: text, matching: "urgent")
        #expect(italicFont.fontDescriptor.symbolicTraits.contains(.italic))

        let bothFont = try font(in: text, matching: "both")
        #expect(bothFont.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(bothFont.fontDescriptor.symbolicTraits.contains(.italic))

        let underline = text.attribute(.underlineStyle, at: range(of: "underlined", in: fullText).location, effectiveRange: nil) as? Int
        #expect(underline == NSUnderlineStyle.single.rawValue)

        let strike = text.attribute(.strikethroughStyle, at: range(of: "removed", in: fullText).location, effectiveRange: nil) as? Int
        #expect(strike == NSUnderlineStyle.single.rawValue)

        let link = text.attribute(.link, at: range(of: "Reference", in: fullText).location, effectiveRange: nil) as? URL
        #expect(link == URL(string: "https://example.com"))

        let color = text.attribute(.foregroundColor, at: range(of: "blue", in: fullText).location, effectiveRange: nil) as? NSColor
        #expect(color?.blueComponent ?? 0 > 0.8)

        let centerStyle = try paragraphStyle(in: text, matching: "Centered line")
        #expect(centerStyle.alignment == .center)
        #expect(centerStyle.paragraphSpacing >= 8)

        let firstListStyle = try paragraphStyle(in: text, matching: "First item")
        #expect(firstListStyle.textLists.count == 1)
        #expect(firstListStyle.headIndent > 0)

        let nestedListStyle = try paragraphStyle(in: text, matching: "Nested item")
        #expect(nestedListStyle.textLists.count == 1)
        #expect(nestedListStyle.headIndent > firstListStyle.headIndent)

        let numberedStyle = try paragraphStyle(in: text, matching: "Number item")
        #expect(numberedStyle.textLists.count == 1)
        #expect(numberedStyle.textLists[0].markerFormat == .decimal)

        let emojiRange = range(of: "😄", in: fullText)
        #expect(emojiRange.length == 2)
        #expect(parsed.textSegments.contains { NSIntersectionRange($0.localRange, emojiRange).length > 0 })
    }

    @Test func parserStoresStyleMetadataBesideMappedGoogleRanges() throws {
        let document = try decodeDocument(richDocumentJSON)
        let parsed = GoogleDocsParser().parse(document)
        let fullText = parsed.plainText

        let importantRange = range(of: "important", in: fullText)
        let importantSegment = try #require(parsed.textSegments.first { NSIntersectionRange($0.localRange, importantRange).length > 0 })
        #expect(importantSegment.textStyle?.bold == true)
        #expect(importantSegment.paragraphStyle?.namedStyleType == "NORMAL_TEXT")

        let nestedRange = range(of: "Nested item", in: fullText)
        let nestedSegment = try #require(parsed.textSegments.first { NSIntersectionRange($0.localRange, nestedRange).length > 0 })
        #expect(nestedSegment.listMetadata?.listID == "bullet-list")
        #expect(nestedSegment.listMetadata?.nestingLevel == 1)
    }
}

private func decodeDocument(_ json: String) throws -> GoogleDocsAPIDocument {
    try JSONDecoder().decode(GoogleDocsAPIDocument.self, from: Data(json.utf8))
}

private func range(of needle: String, in haystack: String) -> NSRange {
    (haystack as NSString).range(of: needle)
}

private func font(in text: NSAttributedString, matching string: String) throws -> NSFont {
    let match = range(of: string, in: text.string)
    return try #require(text.attribute(.font, at: match.location, effectiveRange: nil) as? NSFont)
}

private func paragraphStyle(in text: NSAttributedString, matching string: String) throws -> NSParagraphStyle {
    let match = range(of: string, in: text.string)
    return try #require(text.attribute(.paragraphStyle, at: match.location, effectiveRange: nil) as? NSParagraphStyle)
}

private let richDocumentJSON = """
{
  "documentId": "doc-1",
  "title": "Rich Test",
  "revisionId": "rev-1",
  "lists": {
    "bullet-list": {
      "listProperties": {
        "nestingLevels": [
          { "glyphType": "BULLET" },
          { "glyphType": "CIRCLE" }
        ]
      }
    },
    "number-list": {
      "listProperties": {
        "nestingLevels": [
          { "glyphType": "DECIMAL", "startNumber": 1 }
        ]
      }
    }
  },
  "body": {
    "content": [
      {
        "paragraph": {
          "paragraphStyle": { "namedStyleType": "TITLE", "spaceBelow": { "magnitude": 12, "unit": "PT" } },
          "elements": [
            { "startIndex": 1, "endIndex": 14, "textRun": { "content": "Project Plan\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "paragraphStyle": { "namedStyleType": "HEADING_2", "spaceBelow": { "magnitude": 10, "unit": "PT" } },
          "elements": [
            { "startIndex": 14, "endIndex": 27, "textRun": { "content": "Requirements\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "paragraphStyle": { "namedStyleType": "NORMAL_TEXT" },
          "elements": [
            { "startIndex": 27, "endIndex": 35, "textRun": { "content": "This is " } },
            { "startIndex": 35, "endIndex": 44, "textRun": { "content": "important", "textStyle": { "bold": true } } },
            { "startIndex": 44, "endIndex": 49, "textRun": { "content": " and " } },
            { "startIndex": 49, "endIndex": 55, "textRun": { "content": "urgent", "textStyle": { "italic": true } } },
            { "startIndex": 55, "endIndex": 59, "textRun": { "content": " 😄." } },
            { "startIndex": 59, "endIndex": 60, "textRun": { "content": "\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "paragraphStyle": { "namedStyleType": "NORMAL_TEXT" },
          "elements": [
            { "startIndex": 60, "endIndex": 64, "textRun": { "content": "both", "textStyle": { "bold": true, "italic": true } } },
            { "startIndex": 64, "endIndex": 65, "textRun": { "content": " " } },
            { "startIndex": 65, "endIndex": 75, "textRun": { "content": "underlined", "textStyle": { "underline": true } } },
            { "startIndex": 75, "endIndex": 76, "textRun": { "content": " " } },
            { "startIndex": 76, "endIndex": 83, "textRun": { "content": "removed", "textStyle": { "strikethrough": true } } },
            { "startIndex": 83, "endIndex": 84, "textRun": { "content": " " } },
            { "startIndex": 84, "endIndex": 88, "textRun": { "content": "blue", "textStyle": { "foregroundColor": { "color": { "rgbColor": { "red": 0, "green": 0.2, "blue": 1 } } }, "fontSize": { "magnitude": 19, "unit": "PT" } } } },
            { "startIndex": 88, "endIndex": 89, "textRun": { "content": "\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "paragraphStyle": { "alignment": "CENTER", "spaceBelow": { "magnitude": 9, "unit": "PT" }, "lineSpacing": 120 },
          "elements": [
            { "startIndex": 89, "endIndex": 103, "textRun": { "content": "Centered line\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "bullet": { "listId": "bullet-list", "nestingLevel": 0 },
          "paragraphStyle": { "indentStart": { "magnitude": 18, "unit": "PT" } },
          "elements": [
            { "startIndex": 103, "endIndex": 114, "textRun": { "content": "First item\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "bullet": { "listId": "bullet-list", "nestingLevel": 1 },
          "paragraphStyle": { "indentStart": { "magnitude": 36, "unit": "PT" } },
          "elements": [
            { "startIndex": 114, "endIndex": 126, "textRun": { "content": "Nested item\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "bullet": { "listId": "number-list", "nestingLevel": 0 },
          "paragraphStyle": { "indentStart": { "magnitude": 18, "unit": "PT" } },
          "elements": [
            { "startIndex": 126, "endIndex": 138, "textRun": { "content": "Number item\\n" } }
          ]
        }
      },
      {
        "paragraph": {
          "paragraphStyle": { "namedStyleType": "NORMAL_TEXT" },
          "elements": [
            { "startIndex": 138, "endIndex": 148, "textRun": { "content": "Reference", "textStyle": { "link": { "url": "https://example.com" } } } },
            { "startIndex": 148, "endIndex": 149, "textRun": { "content": "\\n" } }
          ]
        }
      }
    ]
  }
}
"""
