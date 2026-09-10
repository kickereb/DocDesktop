import AppKit
import Foundation

struct MarkdownEditingEngine {
    typealias TextReplacement = (range: NSRange, text: String, selectedRange: NSRange)

    func replacementForReturn(in text: String, selectedRange: NSRange) -> TextReplacement? {
        guard selectedRange.length == 0 else { return nil }

        let nsText = text as NSString
        let caretLocation = min(max(0, selectedRange.location), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: caretLocation, length: 0))
        let caretOffset = max(0, caretLocation - lineRange.location)
        let textBeforeCaret = nsText.substring(with: NSRange(location: lineRange.location, length: caretOffset))
            .trimmingCharacters(in: .newlines)
        let fullLine = nsText.substring(with: lineRange)
            .trimmingCharacters(in: .newlines)

        guard let item = listItem(in: textBeforeCaret) else { return nil }

        if fullLineContentAfterMarker(in: fullLine, markerLength: item.markerLength).trimmingCharacters(in: .whitespaces).isEmpty {
            let markerRange = NSRange(location: lineRange.location, length: min(item.markerLength, nsText.length - lineRange.location))
            return (markerRange, "", NSRange(location: markerRange.location, length: 0))
        }

        let continuation = "\n" + item.indent + item.nextMarker
        let replacementRange = NSRange(location: caretLocation, length: 0)
        return (
            replacementRange,
            continuation,
            NSRange(location: caretLocation + (continuation as NSString).length, length: 0)
        )
    }

    func replacementForTab(in text: String, selectedRange: NSRange, outdent: Bool) -> TextReplacement? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let selectedLineRange = nsText.lineRange(for: selectedRange)
        var replacements: [(range: NSRange, text: String)] = []
        var location = selectedLineRange.location

        while location < NSMaxRange(selectedLineRange) {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)

            if lineHasListMarker(line) {
                if outdent {
                    let removableSpaces = removableIndentLength(in: line)
                    if removableSpaces > 0 {
                        replacements.append((NSRange(location: lineRange.location, length: removableSpaces), ""))
                    }
                } else {
                    replacements.append((NSRange(location: lineRange.location, length: 0), "  "))
                }
            }

            let next = NSMaxRange(lineRange)
            if next <= location { break }
            location = next
        }

        guard !replacements.isEmpty else { return nil }

        let replacement = combinedReplacement(from: replacements, in: text)
        let selectedShift = outdent ? -2 : 2
        let newLocation = max(selectedLineRange.location, selectedRange.location + selectedShift)
        return (replacement.range, replacement.text, NSRange(location: newLocation, length: selectedRange.length))
    }

    func replacementForCheckboxToggle(in text: String, location: Int) -> TextReplacement? {
        let nsText = text as NSString
        guard nsText.length > 0 else { return nil }

        let safeLocation = min(max(0, location), nsText.length)
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        guard let checkbox = checkboxMarker(in: line) else { return nil }

        let replacementRange = NSRange(location: lineRange.location + checkbox.markerLocation, length: 3)
        let replacementText = checkbox.isChecked ? "[ ]" : "[x]"
        return (replacementRange, replacementText, NSRange(location: safeLocation, length: 0))
    }

    private func listItem(in linePrefix: String) -> (indent: String, markerLength: Int, nextMarker: String)? {
        let nsLine = linePrefix as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)([-*+] |\d+\. |\[ \] |\[x\] )"#),
              let match = regex.firstMatch(in: linePrefix, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        let indent = nsLine.substring(with: match.range(at: 1))
        let marker = nsLine.substring(with: match.range(at: 2))
        let nextMarker: String
        if marker.range(of: #"^\d+\. $"#, options: .regularExpression) != nil {
            let numberText = String(marker.dropLast(2))
            let nextNumber = (Int(numberText) ?? 0) + 1
            nextMarker = "\(nextNumber). "
        } else if marker == "[x] " {
            nextMarker = "[ ] "
        } else {
            nextMarker = marker
        }

        return (indent, match.range.length, nextMarker)
    }

    private func fullLineContentAfterMarker(in line: String, markerLength: Int) -> String {
        let nsLine = line as NSString
        guard markerLength <= nsLine.length else { return "" }
        return nsLine.substring(from: markerLength)
    }

    private func lineHasListMarker(_ line: String) -> Bool {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^\s*([-*+] |\d+\. |\[ \] |\[x\] )"#) else {
            return false
        }
        return regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) != nil
    }

    private func removableIndentLength(in line: String) -> Int {
        let leadingSpaces = line.prefix { $0 == " " }.count
        return min(2, leadingSpaces)
    }

    private func checkboxMarker(in line: String) -> (markerLocation: Int, isChecked: Bool)? {
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^\s*(\[[ x]\]) "#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        let marker = nsLine.substring(with: match.range(at: 1))
        return (match.range(at: 1).location, marker == "[x]")
    }

    private func combinedReplacement(from replacements: [(range: NSRange, text: String)], in originalText: String) -> (range: NSRange, text: String) {
        let nsText = originalText as NSString
        let firstLocation = replacements.map(\.range.location).min() ?? 0
        let lastLocation = replacements.map { NSMaxRange($0.range) }.max() ?? firstLocation
        let combinedRange = NSRange(location: firstLocation, length: max(0, lastLocation - firstLocation))
        let mutable = NSMutableString(string: nsText.substring(with: combinedRange))

        for replacement in replacements.sorted(by: { $0.range.location > $1.range.location }) {
            let localRange = NSRange(location: replacement.range.location - combinedRange.location, length: replacement.range.length)
            mutable.replaceCharacters(in: localRange, with: replacement.text)
        }

        return (combinedRange, mutable as String)
    }
}

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
