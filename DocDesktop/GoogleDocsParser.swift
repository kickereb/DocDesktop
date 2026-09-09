import AppKit
import Foundation

struct GoogleDocsAPIDocument: Decodable {
    let documentId: String
    let title: String
    let revisionId: String?
    let body: Body?
    let inlineObjects: [String: InlineObject]?
    let lists: [String: ListDefinition]?
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
        let lists: [String: ListDefinition]?
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

    struct ListDefinition: Decodable {
        let listProperties: ListProperties?
    }

    struct ListProperties: Decodable {
        let nestingLevels: [NestingLevel]?
    }

    struct NestingLevel: Decodable {
        let glyphType: String?
        let glyphFormat: String?
        let startNumber: Int?
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

struct Bullet: Decodable {
    let listId: String?
    let nestingLevel: Int?
}

struct ParagraphStyle: Decodable {
    let namedStyleType: String?
    let alignment: String?
    let lineSpacing: Double?
    let spaceAbove: GoogleDocsAPIDocument.Dimension?
    let spaceBelow: GoogleDocsAPIDocument.Dimension?
    let indentStart: GoogleDocsAPIDocument.Dimension?
    let indentEnd: GoogleDocsAPIDocument.Dimension?
    let indentFirstLine: GoogleDocsAPIDocument.Dimension?
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
    let foregroundColor: OptionalColor?
    let fontSize: GoogleDocsAPIDocument.Dimension?
    let weightedFontFamily: WeightedFontFamily?
    let baselineOffset: String?
}

struct Link: Decodable {
    let url: URL?
}

struct OptionalColor: Decodable {
    let color: GoogleColor?
}

struct GoogleColor: Decodable {
    let rgbColor: RGBColor?
}

struct RGBColor: Decodable {
    let red: Double?
    let green: Double?
    let blue: Double?
}

struct WeightedFontFamily: Decodable {
    let fontFamily: String?
    let weight: Int?
}

struct GoogleDocsParser {
    private let loadedImages: [String: NSImage]
    private let defaultFont = NSFont.systemFont(ofSize: 16)
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
                append(elements: document.body?.content ?? [], tabID: nil, listDefinitions: document.lists ?? [:], to: output, textSegments: &textSegments)
        } else {
            for (index, tabContent) in tabContents.enumerated() {
                if tabContents.count > 1, let title = tabContent.title, !title.isEmpty {
                    if index > 0 {
                        output.append(line("\n"))
                    }
                    output.append(text(title + "\n", font: font(for: "TITLE", textStyle: nil)))
                }

                append(elements: tabContent.elements, tabID: tabContent.tabID, listDefinitions: tabContent.lists, to: output, textSegments: &textSegments)
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
        listDefinitions: [String: GoogleDocsAPIDocument.ListDefinition],
        to output: NSMutableAttributedString,
        textSegments: inout [GoogleDocsTextSegment]
    ) {
        for element in elements {
            if let paragraph = element.paragraph {
                append(paragraph: paragraph, tabID: tabID, listDefinitions: listDefinitions, to: output, textSegments: &textSegments)
            } else if element.table != nil {
                output.append(text("[Table not shown in this version]\n\n", color: secondaryTextColor))
            } else if element.sectionBreak != nil {
                output.append(line("\n"))
            }
        }
    }

    private func contentsByTab(from document: GoogleDocsAPIDocument) -> [(tabID: String?, title: String?, elements: [StructuralElement], lists: [String: GoogleDocsAPIDocument.ListDefinition])] {
        (document.tabs ?? []).flatMap { contentsByTab(from: $0) }
    }

    private func contentsByTab(from tab: GoogleDocsAPIDocument.Tab) -> [(tabID: String?, title: String?, elements: [StructuralElement], lists: [String: GoogleDocsAPIDocument.ListDefinition])] {
        var results: [(tabID: String?, title: String?, elements: [StructuralElement], lists: [String: GoogleDocsAPIDocument.ListDefinition])] = []
        let elements = tab.documentTab?.body?.content ?? []
        let tabID = tab.tabProperties?.tabId
        let lists = tab.documentTab?.lists ?? [:]

        if !elements.isEmpty {
            results.append((tabID: tabID, title: tab.tabProperties?.title, elements: elements, lists: lists))
        }

        for childTab in tab.childTabs ?? [] {
            results.append(contentsOf: contentsByTab(from: childTab))
        }

        return results
    }

    private func append(
        paragraph: Paragraph,
        tabID: String?,
        listDefinitions: [String: GoogleDocsAPIDocument.ListDefinition],
        to output: NSMutableAttributedString,
        textSegments: inout [GoogleDocsTextSegment]
    ) {
        let paragraphStart = output.length

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
                            tabID: tabID,
                            textStyle: runStyle(from: textRun.textStyle),
                            paragraphStyle: paragraphRunStyle(from: paragraph.paragraphStyle),
                            listMetadata: listMetadata(from: paragraph.bullet, in: listDefinitions)
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

        let paragraphRange = NSRange(location: paragraphStart, length: output.length - paragraphStart)
        apply(paragraphStyle: paragraph.paragraphStyle, bullet: paragraph.bullet, listDefinitions: listDefinitions, to: output, range: paragraphRange)
    }

    private func attributedTextRun(_ textRun: TextRun, paragraphStyle: ParagraphStyle?) -> NSAttributedString {
        let font = font(for: paragraphStyle?.namedStyleType, textStyle: textRun.textStyle)

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color(from: textRun.textStyle?.foregroundColor) ?? textColor
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
        if let baselineOffset = textRun.textStyle?.baselineOffset {
            switch baselineOffset {
            case "SUPERSCRIPT":
                attributes[.baselineOffset] = font.pointSize * 0.35
                attributes[.font] = NSFontManager.shared.convert(font, toSize: max(9, font.pointSize * 0.75))
            case "SUBSCRIPT":
                attributes[.baselineOffset] = -font.pointSize * 0.2
                attributes[.font] = NSFontManager.shared.convert(font, toSize: max(9, font.pointSize * 0.75))
            default:
                break
            }
        }

        return NSAttributedString(string: textRun.content ?? "", attributes: attributes)
    }

    private func apply(
        paragraphStyle: ParagraphStyle?,
        bullet: Bullet?,
        listDefinitions: [String: GoogleDocsAPIDocument.ListDefinition],
        to output: NSMutableAttributedString,
        range: NSRange
    ) {
        guard range.length > 0 else { return }

        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = points(from: paragraphStyle?.spaceAbove) ?? 2
        style.paragraphSpacing = points(from: paragraphStyle?.spaceBelow) ?? spacingAfter(namedStyleType: paragraphStyle?.namedStyleType)

        if let lineSpacing = paragraphStyle?.lineSpacing {
            style.lineHeightMultiple = max(0.5, lineSpacing / 100)
        }

        switch paragraphStyle?.alignment {
        case "CENTER":
            style.alignment = .center
        case "END":
            style.alignment = .right
        case "JUSTIFIED":
            style.alignment = .justified
        default:
            style.alignment = .left
        }

        let indentStart = points(from: paragraphStyle?.indentStart) ?? 0
        let firstLineIndent = points(from: paragraphStyle?.indentFirstLine) ?? 0
        let listLevel = bullet?.nestingLevel ?? 0
        let listIndent = bullet == nil ? 0 : CGFloat(listLevel + 1) * 24
        style.headIndent = indentStart + listIndent
        style.firstLineHeadIndent = indentStart + firstLineIndent + (bullet == nil ? 0 : CGFloat(listLevel) * 24)
        style.tailIndent = -(points(from: paragraphStyle?.indentEnd) ?? 0)

        if let bullet {
            style.textLists = [textList(for: bullet, in: listDefinitions)]
        }

        output.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func textList(for bullet: Bullet, in listDefinitions: [String: GoogleDocsAPIDocument.ListDefinition]) -> NSTextList {
        let nestingLevel = bullet.nestingLevel ?? 0
        let listDefinition = bullet.listId.flatMap { listDefinitions[$0] }
        let nesting = listDefinition?.listProperties?.nestingLevels?.dropFirst(nestingLevel).first
        let format = markerFormat(from: nesting)
        let start = nesting?.startNumber ?? 1
        return NSTextList(markerFormat: format, options: [], startingItemNumber: start)
    }

    private func runStyle(from textStyle: TextStyle?) -> GoogleDocsTextRunStyle {
        let rgbColor = textStyle?.foregroundColor?.color?.rgbColor
        return GoogleDocsTextRunStyle(
            bold: textStyle?.bold == true,
            italic: textStyle?.italic == true,
            underline: textStyle?.underline == true,
            strikethrough: textStyle?.strikethrough == true,
            linkURL: textStyle?.link?.url,
            fontSize: textStyle?.fontSize?.magnitude,
            fontWeight: textStyle?.weightedFontFamily?.weight,
            foregroundRed: rgbColor?.red,
            foregroundGreen: rgbColor?.green,
            foregroundBlue: rgbColor?.blue,
            baselineOffset: textStyle?.baselineOffset
        )
    }

    private func paragraphRunStyle(from paragraphStyle: ParagraphStyle?) -> GoogleDocsParagraphRunStyle {
        GoogleDocsParagraphRunStyle(
            namedStyleType: paragraphStyle?.namedStyleType,
            alignment: paragraphStyle?.alignment,
            lineSpacing: paragraphStyle?.lineSpacing,
            spaceAbove: paragraphStyle?.spaceAbove?.magnitude,
            spaceBelow: paragraphStyle?.spaceBelow?.magnitude,
            indentStart: paragraphStyle?.indentStart?.magnitude,
            indentEnd: paragraphStyle?.indentEnd?.magnitude,
            indentFirstLine: paragraphStyle?.indentFirstLine?.magnitude
        )
    }

    private func listMetadata(from bullet: Bullet?, in listDefinitions: [String: GoogleDocsAPIDocument.ListDefinition]) -> GoogleDocsListMetadata? {
        guard let bullet else { return nil }
        let nestingLevel = bullet.nestingLevel ?? 0
        let listDefinition = bullet.listId.flatMap { listDefinitions[$0] }
        let nesting = listDefinition?.listProperties?.nestingLevels?.dropFirst(nestingLevel).first

        return GoogleDocsListMetadata(
            listID: bullet.listId,
            nestingLevel: nestingLevel,
            glyphType: nesting?.glyphType,
            glyphFormat: nesting?.glyphFormat
        )
    }

    private func markerFormat(from nesting: GoogleDocsAPIDocument.NestingLevel?) -> NSTextList.MarkerFormat {
        switch nesting?.glyphType {
        case "DECIMAL":
            return .decimal
        case "ALPHA", "LOWER_ALPHA":
            return .lowercaseAlpha
        case "UPPER_ALPHA":
            return .uppercaseAlpha
        case "ROMAN", "LOWER_ROMAN":
            return .lowercaseRoman
        case "UPPER_ROMAN":
            return .uppercaseRoman
        case "SQUARE":
            return .square
        case "CIRCLE":
            return .circle
        case "CHECKBOX":
            return .check
        default:
            if nesting?.glyphFormat?.contains("%0") == true {
                return .decimal
            }
            return .disc
        }
    }

    private func font(for namedStyleType: String?, textStyle: TextStyle?) -> NSFont {
        let size = points(from: textStyle?.fontSize) ?? defaultSize(for: namedStyleType)
        let wantsBold = textStyle?.bold == true || isHeading(namedStyleType)
        let wantsItalic = textStyle?.italic == true
        let family = textStyle?.weightedFontFamily?.fontFamily
        let weight = textStyle?.weightedFontFamily?.weight ?? (wantsBold ? 700 : 400)
        var font = baseFont(family: family, size: size, weight: weight, bold: wantsBold)

        if wantsItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
        }

        return font
    }

    private func baseFont(family: String?, size: CGFloat, weight: Int, bold: Bool) -> NSFont {
        if let family,
           let font = NSFontManager.shared.font(withFamily: family, traits: bold ? .boldFontMask : [], weight: appKitWeight(from: weight), size: size) {
            return font
        }

        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }

    private func isHeading(_ namedStyleType: String?) -> Bool {
        guard let namedStyleType else { return false }
        return namedStyleType == "TITLE" || namedStyleType == "SUBTITLE" || namedStyleType.hasPrefix("HEADING")
    }

    private func defaultSize(for namedStyleType: String?) -> CGFloat {
        switch namedStyleType {
        case "TITLE":
            return 34
        case "SUBTITLE":
            return 22
        case "HEADING_1":
            return 30
        case "HEADING_2":
            return 25
        case "HEADING_3":
            return 21
        case "HEADING_4":
            return 18
        case "HEADING_5", "HEADING_6":
            return 16
        default:
            return defaultFont.pointSize
        }
    }

    private func spacingAfter(namedStyleType: String?) -> CGFloat {
        switch namedStyleType {
        case "TITLE", "SUBTITLE":
            return 12
        case "HEADING_1", "HEADING_2":
            return 10
        case "HEADING_3", "HEADING_4", "HEADING_5", "HEADING_6":
            return 8
        default:
            return 6
        }
    }

    private func appKitWeight(from weight: Int) -> Int {
        switch weight {
        case 0..<300:
            return 3
        case 300..<500:
            return 5
        case 500..<700:
            return 7
        case 700..<900:
            return 9
        default:
            return 12
        }
    }

    private func points(from dimension: GoogleDocsAPIDocument.Dimension?) -> CGFloat? {
        guard let magnitude = dimension?.magnitude else { return nil }
        return CGFloat(magnitude)
    }

    private func color(from optionalColor: OptionalColor?) -> NSColor? {
        guard let rgbColor = optionalColor?.color?.rgbColor else { return nil }
        return NSColor(
            calibratedRed: CGFloat(rgbColor.red ?? 0),
            green: CGFloat(rgbColor.green ?? 0),
            blue: CGFloat(rgbColor.blue ?? 0),
            alpha: 1
        )
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
