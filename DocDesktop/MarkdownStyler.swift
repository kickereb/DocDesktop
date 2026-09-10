import AppKit
import Foundation

struct MarkdownStyler {
    private let baseFont = NSFont.systemFont(ofSize: 16)
    private let monospacedFont = NSFont.monospacedSystemFont(ofSize: 15, weight: .regular)
    private let textColor = NSColor.white
    private let markerColor = NSColor.white.withAlphaComponent(0.35)
    private let linkColor = NSColor.systemBlue
    private let quoteColor = NSColor.systemMint

    func attributedString(for markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString(
            string: markdown,
            attributes: baseAttributes(paragraphStyle: paragraphStyle())
        )

        styleBlocks(in: output)
        styleInlineRuns(in: output)
        return output
    }

    func apply(to textStorage: NSTextStorage) {
        let selectedRange = NSRange(location: 0, length: textStorage.length)
        textStorage.beginEditing()
        textStorage.setAttributes(baseAttributes(paragraphStyle: paragraphStyle()), range: selectedRange)
        styleBlocks(in: textStorage)
        styleInlineRuns(in: textStorage)
        textStorage.endEditing()
    }

    private func styleBlocks(in text: NSMutableAttributedString) {
        let nsText = text.string as NSString
        var lineStart = 0
        var orderedCounters: [Int: Int] = [:]
        var isInCodeBlock = false

        while lineStart <= nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let rawLine = nsText.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: .newlines)
            let contentLength = (line as NSString).length
            let paragraphRange = NSRange(location: lineRange.location, length: lineRange.length)

            if line.hasPrefix("```") {
                text.addAttributes([
                    .font: monospacedFont,
                    .foregroundColor: markerColor
                ], range: NSRange(location: lineRange.location, length: min(3, contentLength)))
                isInCodeBlock.toggle()
                advanceLine(from: &lineStart, next: NSMaxRange(lineRange), total: nsText.length)
                if lineStart < 0 { break }
                continue
            }

            if isInCodeBlock {
                text.addAttributes([
                    .font: monospacedFont,
                    .backgroundColor: NSColor.white.withAlphaComponent(0.07)
                ], range: paragraphRange)
                advanceLine(from: &lineStart, next: NSMaxRange(lineRange), total: nsText.length)
                if lineStart < 0 { break }
                continue
            }

            if let heading = headingPrefix(in: line) {
                let contentRange = NSRange(location: lineRange.location + heading.length, length: max(0, contentLength - heading.length))
                text.addAttributes([
                    .font: headingFont(level: heading.level),
                    .foregroundColor: textColor
                ], range: contentRange)
                text.addAttributes([
                    .font: headingFont(level: heading.level),
                    .foregroundColor: markerColor
                ], range: NSRange(location: lineRange.location, length: heading.length))
                text.addAttribute(.paragraphStyle, value: paragraphStyle(spacingBefore: 10, spacingAfter: 8), range: paragraphRange)
            } else if let quoteLength = quotePrefixLength(in: line) {
                text.addAttributes([
                    .foregroundColor: quoteColor,
                    .font: NSFont.systemFont(ofSize: 16)
                ], range: NSRange(location: lineRange.location, length: contentLength))
                text.addAttributes([.foregroundColor: markerColor], range: NSRange(location: lineRange.location, length: quoteLength))
                text.addAttribute(.paragraphStyle, value: paragraphStyle(indent: 18, spacingBefore: 4, spacingAfter: 4), range: paragraphRange)
            } else if let list = listPrefix(in: line, orderedCounters: &orderedCounters) {
                let style = paragraphStyle(indent: CGFloat(list.level + 1) * 24, firstLineIndent: CGFloat(list.level) * 24, spacingBefore: 2, spacingAfter: 2)
                text.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
                text.addAttributes([
                    .foregroundColor: markerColor,
                    .font: baseFont
                ], range: NSRange(location: lineRange.location, length: list.markerLength))
            } else if horizontalRule(in: line) {
                text.addAttributes([
                    .foregroundColor: markerColor,
                    .font: NSFont.boldSystemFont(ofSize: 18)
                ], range: NSRange(location: lineRange.location, length: contentLength))
                text.addAttribute(.paragraphStyle, value: paragraphStyle(spacingBefore: 10, spacingAfter: 10), range: paragraphRange)
            } else {
                orderedCounters.removeAll()
            }

            advanceLine(from: &lineStart, next: NSMaxRange(lineRange), total: nsText.length)
            if lineStart < 0 { break }
        }
    }

    private func styleInlineRuns(in text: NSMutableAttributedString) {
        applyInline(pattern: #"(`)([^`\n]+)(`)"#, in: text) { match, nsText in
            [
                (match.range(at: 1), [.foregroundColor: markerColor]),
                (match.range(at: 2), [.font: monospacedFont, .backgroundColor: NSColor.white.withAlphaComponent(0.08)]),
                (match.range(at: 3), [.foregroundColor: markerColor])
            ]
        }

        applyInline(pattern: #"(\*\*\*)(.+?)(\*\*\*)"#, in: text) { match, _ in
            [
                (match.range(at: 1), [.foregroundColor: markerColor]),
                (match.range(at: 2), [.font: NSFontManager.shared.convert(NSFont.boldSystemFont(ofSize: 16), toHaveTrait: .italicFontMask)]),
                (match.range(at: 3), [.foregroundColor: markerColor])
            ]
        }

        applyInline(pattern: #"(\*\*)([^*\n]+)(\*\*)"#, in: text) { match, _ in
            [
                (match.range(at: 1), [.foregroundColor: markerColor]),
                (match.range(at: 2), [.font: NSFont.boldSystemFont(ofSize: 16)]),
                (match.range(at: 3), [.foregroundColor: markerColor])
            ]
        }

        applyInline(pattern: #"(?<!\*)(\*)([^*\n]+)(\*)(?!\*)"#, in: text) { match, _ in
            [
                (match.range(at: 1), [.foregroundColor: markerColor]),
                (match.range(at: 2), [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: 16), toHaveTrait: .italicFontMask)]),
                (match.range(at: 3), [.foregroundColor: markerColor])
            ]
        }

        applyInline(pattern: #"(~~)([^~\n]+)(~~)"#, in: text) { match, _ in
            [
                (match.range(at: 1), [.foregroundColor: markerColor]),
                (match.range(at: 2), [.strikethroughStyle: NSUnderlineStyle.single.rawValue]),
                (match.range(at: 3), [.foregroundColor: markerColor])
            ]
        }

        applyInline(pattern: #"(\[)([^\]\n]+)(\]\()([^\s)]+)(\))"#, in: text) { match, nsText in
            let urlText = nsText.substring(with: match.range(at: 4))
            let url = URL(string: urlText)
            var linkAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            if let url {
                linkAttrs[.link] = url
            }
            return [
                (match.range(at: 1), [.foregroundColor: markerColor]),
                (match.range(at: 2), linkAttrs),
                (match.range(at: 3), [.foregroundColor: markerColor]),
                (match.range(at: 4), [.foregroundColor: markerColor]),
                (match.range(at: 5), [.foregroundColor: markerColor])
            ]
        }
    }

    private func applyInline(
        pattern: String,
        in text: NSMutableAttributedString,
        attributes: (NSTextCheckingResult, NSString) -> [(NSRange, [NSAttributedString.Key: Any])]
    ) {
        let nsText = text.string as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let matches = regex.matches(in: text.string, range: NSRange(location: 0, length: nsText.length))

        for match in matches {
            for (range, attrs) in attributes(match, nsText) where range.location != NSNotFound && range.length > 0 {
                text.addAttributes(attrs, range: range)
            }
        }
    }

    private func headingPrefix(in line: String) -> (level: Int, length: Int)? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^(#{1,6})\s+"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        return (min(6, match.range(at: 1).length), match.range.length)
    }

    private func quotePrefixLength(in line: String) -> Int? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^\s*>\s?"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }
        return match.range.length
    }

    private func listPrefix(in line: String, orderedCounters: inout [Int: Int]) -> (level: Int, markerLength: Int)? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)([-*+] |\d+\. |\[ \] |\[x\] )"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        let indentLength = match.range(at: 1).length
        return (indentLength / 2, match.range.length)
    }

    private func horizontalRule(in line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed == "---" || trimmed == "***" || trimmed == "___"
    }

    private func headingFont(level: Int) -> NSFont {
        let size: CGFloat
        switch level {
        case 1:
            size = 30
        case 2:
            size = 25
        case 3:
            size = 21
        case 4:
            size = 18
        default:
            size = 16
        }
        return NSFont.boldSystemFont(ofSize: size)
    }

    private func paragraphStyle(indent: CGFloat = 0, firstLineIndent: CGFloat = 0, spacingBefore: CGFloat = 4, spacingAfter: CGFloat = 6) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacingBefore = spacingBefore
        style.paragraphSpacing = spacingAfter
        style.headIndent = indent
        style.firstLineHeadIndent = firstLineIndent
        return style
    }

    private func baseAttributes(paragraphStyle: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: baseFont,
            .foregroundColor: textColor,
            .paragraphStyle: paragraphStyle
        ]
    }

    private func advanceLine(from lineStart: inout Int, next: Int, total: Int) {
        if next <= lineStart || next >= total {
            lineStart = -1
        } else {
            lineStart = next
        }
    }
}
