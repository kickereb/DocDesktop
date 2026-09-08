import AppKit
import Foundation

struct GoogleDocsAPIDocument: Decodable {
    let documentId: String
    let title: String
    let revisionId: String?
    let body: Body?
    let inlineObjects: [String: InlineObject]?
    let tabs: [Tab]?

    struct Body: Decodable {
        let content: [StructuralElement]?
    }

    struct Tab: Decodable {
        let tabProperties: TabProperties?
        let documentTab: DocumentTab?
        let childTabs: [Tab]?
    }

    struct TabProperties: Decodable {
        let tabId: String?
        let title: String?
    }

    struct DocumentTab: Decodable {
        let body: Body?
        let inlineObjects: [String: InlineObject]?
    }

    struct InlineObject: Decodable {
        let inlineObjectProperties: InlineObjectProperties?
    }

    struct InlineObjectProperties: Decodable {
        let embeddedObject: EmbeddedObject?
    }

    struct EmbeddedObject: Decodable {
        let title: String?
        let description: String?
        let imageProperties: ImageProperties?
        let size: Size?
    }

    struct ImageProperties: Decodable {
        let contentUri: URL?
        let sourceUri: URL?
    }

    struct Size: Decodable {
        let width: Dimension?
        let height: Dimension?
    }

    struct Dimension: Decodable {
        let magnitude: Double?
        let unit: String?
    }
}

struct StructuralElement: Decodable {
    let paragraph: Paragraph?
    let table: Table?
    let sectionBreak: SectionBreak?
}

struct SectionBreak: Decodable {}
struct Table: Decodable {}

struct Paragraph: Decodable {
    let elements: [ParagraphElement]?
    let bullet: Bullet?
    let paragraphStyle: ParagraphStyle?
}

struct Bullet: Decodable {}

struct ParagraphStyle: Decodable {
    let namedStyleType: String?
}

struct ParagraphElement: Decodable {
    let startIndex: Int?
    let endIndex: Int?
    let textRun: TextRun?
    let inlineObjectElement: InlineObjectElement?
    let person: UnsupportedElement?
    let richLink: UnsupportedElement?
}

struct InlineObjectElement: Decodable {
    let inlineObjectId: String?
}

struct UnsupportedElement: Decodable {}

struct TextRun: Decodable {
    let content: String?
    let textStyle: TextStyle?
}

struct TextStyle: Decodable {
    let bold: Bool?
    let italic: Bool?
    let underline: Bool?
    let strikethrough: Bool?
    let link: Link?
}

struct Link: Decodable {
    let url: URL?
}

struct GoogleDocsParser {
    private let loadedImages: [String: NSImage]
    private let defaultFont = NSFont.systemFont(ofSize: 16)
    private let headingFont = NSFont.boldSystemFont(ofSize: 20)
    private let textColor = NSColor.white
    private let secondaryTextColor = NSColor.secondaryLabelColor

    init(loadedImages: [String: NSImage] = [:]) {
        self.loadedImages = loadedImages
    }

    func parse(_ document: GoogleDocsAPIDocument) -> GoogleDocsDocument {
        let output = NSMutableAttributedString()
        var textSegments: [GoogleDocsTextSegment] = []
        let tabContents = contentsByTab(from: document)

        if tabContents.isEmpty {
            append(elements: document.body?.content ?? [], tabID: nil, to: output, textSegments: &textSegments)
        } else {
            for (index, tabContent) in tabContents.enumerated() {
                if tabContents.count > 1, let title = tabContent.title, !title.isEmpty {
                    if index > 0 {
                        output.append(line("\n"))
                    }
                    output.append(text(title + "\n", font: headingFont))
                }

                append(elements: tabContent.elements, tabID: tabContent.tabID, to: output, textSegments: &textSegments)
            }
        }

        if output.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            output.setAttributedString(text("No readable text was returned for this document."))
        }

        return GoogleDocsDocument(
            documentID: document.documentId,
            title: document.title,
            revisionID: document.revisionId,
            attributedText: output,
            textSegments: textSegments
        )
    }

    private func append(
        elements: [StructuralElement],
        tabID: String?,
        to output: NSMutableAttributedString,
        textSegments: inout [GoogleDocsTextSegment]
    ) {
        for element in elements {
            if let paragraph = element.paragraph {
                append(paragraph: paragraph, tabID: tabID, to: output, textSegments: &textSegments)
            } else if element.table != nil {
                output.append(text("[Table not shown in this version]\n\n", color: secondaryTextColor))
            } else if element.sectionBreak != nil {
                output.append(line("\n"))
            }
        }
    }

    private func contentsByTab(from document: GoogleDocsAPIDocument) -> [(tabID: String?, title: String?, elements: [StructuralElement])] {
        (document.tabs ?? []).flatMap { contentsByTab(from: $0) }
    }

    private func contentsByTab(from tab: GoogleDocsAPIDocument.Tab) -> [(tabID: String?, title: String?, elements: [StructuralElement])] {
        var results: [(tabID: String?, title: String?, elements: [StructuralElement])] = []
        let elements = tab.documentTab?.body?.content ?? []
        let tabID = tab.tabProperties?.tabId

        if !elements.isEmpty {
            results.append((tabID: tabID, title: tab.tabProperties?.title, elements: elements))
        }

        for childTab in tab.childTabs ?? [] {
            results.append(contentsOf: contentsByTab(from: childTab))
        }

        return results
    }

    private func append(
        paragraph: Paragraph,
        tabID: String?,
        to output: NSMutableAttributedString,
        textSegments: inout [GoogleDocsTextSegment]
    ) {
        if paragraph.bullet != nil {
            output.append(text("• "))
        }

        for element in paragraph.elements ?? [] {
            if let textRun = element.textRun {
                let run = attributedTextRun(textRun, paragraphStyle: paragraph.paragraphStyle)
                let localStart = output.length
                output.append(run)

                if let googleStart = element.startIndex, let googleEnd = element.endIndex, run.length > 0 {
                    textSegments.append(
                        GoogleDocsTextSegment(
                            localRange: NSRange(location: localStart, length: run.length),
                            googleStartIndex: googleStart,
                            googleEndIndex: googleEnd,
                            tabID: tabID
                        )
                    )
                }
            } else if let inlineObjectId = element.inlineObjectElement?.inlineObjectId {
                output.append(imageAttachment(for: inlineObjectId))
            } else if element.person != nil || element.richLink != nil {
                output.append(text("[Unsupported item]", color: secondaryTextColor))
            }
        }

        if !output.string.hasSuffix("\n") {
            output.append(line("\n"))
        }
    }

    private func attributedTextRun(_ textRun: TextRun, paragraphStyle: ParagraphStyle?) -> NSAttributedString {
        let isHeading = paragraphStyle?.namedStyleType?.hasPrefix("HEADING") == true
        let baseFont = isHeading ? headingFont : defaultFont
        var font = baseFont

        if textRun.textStyle?.bold == true {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
        }
        if textRun.textStyle?.italic == true {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        if textRun.textStyle?.underline == true {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        if textRun.textStyle?.strikethrough == true {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        if let url = textRun.textStyle?.link?.url {
            attributes[.link] = url
            attributes[.foregroundColor] = NSColor.systemBlue
        }

        return NSAttributedString(string: textRun.content ?? "", attributes: attributes)
    }

    private func imageAttachment(for inlineObjectId: String) -> NSAttributedString {
        guard let image = loadedImages[inlineObjectId] else {
            return text("[Image unavailable]", color: secondaryTextColor)
        }

        let attachment = NSTextAttachment()
        attachment.image = scaledImage(image, maximumSize: NSSize(width: 560, height: 360))
        return NSAttributedString(attachment: attachment)
    }

    private func scaledImage(_ image: NSImage, maximumSize: NSSize) -> NSImage {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return image }

        let scale = min(maximumSize.width / imageSize.width, maximumSize.height / imageSize.height, 1)
        guard scale < 1 else { return image }

        let targetSize = NSSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let scaledImage = NSImage(size: targetSize)
        scaledImage.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: imageSize), operation: .copy, fraction: 1)
        scaledImage.unlockFocus()
        return scaledImage
    }

    private func text(_ string: String, font: NSFont? = nil, color: NSColor? = nil) -> NSAttributedString {
        NSAttributedString(
            string: string,
            attributes: [
                .font: font ?? defaultFont,
                .foregroundColor: color ?? textColor
            ]
        )
    }

    private func line(_ string: String) -> NSAttributedString {
        text(string)
    }
}
