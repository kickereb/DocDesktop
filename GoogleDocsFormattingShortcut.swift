import Foundation

struct GoogleDocsFormattingShortcut: Equatable {
    let edit: GoogleDocsTextEdit
    let formattingRequests: [GoogleDocsFormattingRequest]
}

enum GoogleDocsFormattingRequest: Equatable {
    case heading(level: Int, tabID: String?, startIndex: Int, endIndex: Int)
    case bulletList(tabID: String?, startIndex: Int, endIndex: Int)
    case numberedList(tabID: String?, startIndex: Int, endIndex: Int)
    case checkboxList(tabID: String?, startIndex: Int, endIndex: Int)
    case link(url: URL, tabID: String?, startIndex: Int, endIndex: Int)
}

struct GoogleDocsFormattingShortcutMapper {
    private let indexMapper = GoogleDocsIndexMapper()

    func shortcut(from originalText: String, to editedText: String, segments: [GoogleDocsTextSegment]) -> GoogleDocsFormattingShortcut? {
        guard let detected = detectedShortcutLine(in: editedText) else { return nil }
        let normalizedText = (editedText as NSString).replacingCharacters(in: detected.replacementRange, with: detected.replacementText)
        let edit: GoogleDocsTextEdit

        do {
            edit = try indexMapper.edit(from: originalText, to: normalizedText, segments: segments)
        } catch GoogleDocsServiceError.noChangesToSave {
            guard let formatRange = try? formatRange(for: detected, segments: segments) else { return nil }
            return GoogleDocsFormattingShortcut(edit: GoogleDocsTextEdit(tabID: formatRange.tabID, googleStartIndex: formatRange.startIndex, googleEndIndex: formatRange.startIndex, replacementText: ""), formattingRequests: [request(for: detected.kind, range: formatRange)])
        } catch {
            return nil
        }

        let fallbackRange = GoogleRange(
            tabID: edit.tabID,
            startIndex: edit.googleStartIndex,
            endIndex: edit.googleStartIndex + (detected.replacementText as NSString).length
        )
        let formatRange = (try? formatRange(for: detected, segments: segments)) ?? fallbackRange

        return GoogleDocsFormattingShortcut(edit: edit, formattingRequests: [request(for: detected.kind, range: formatRange)])
    }

    private struct DetectedShortcutLine {
        let kind: ShortcutKind
        let replacementRange: NSRange
        let replacementText: String
        let contentRangeAfterReplacement: NSRange
    }

    private struct GoogleRange {
        let tabID: String?
        let startIndex: Int
        let endIndex: Int
    }

    private enum ShortcutKind {
        case heading(Int)
        case bullet
        case numbered
        case checkbox
        case link(URL)
    }

    private func detectedShortcutLine(in text: String) -> DetectedShortcutLine? {
        let nsText = text as NSString
        var lineStart = 0

        while lineStart <= nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let rawLine = nsText.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: .newlines)
            let lineContentLength = (line as NSString).length

            if let link = wholeLineLink(in: line) {
                let lineContentRange = NSRange(location: lineRange.location, length: lineContentLength)
                return DetectedShortcutLine(
                    kind: .link(link.url),
                    replacementRange: lineContentRange,
                    replacementText: link.label,
                    contentRangeAfterReplacement: NSRange(location: lineRange.location, length: (link.label as NSString).length)
                )
            }

            if let marker = marker(in: line) {
                let markerRange = NSRange(location: lineRange.location, length: marker.length)
                let contentRange = NSRange(
                    location: lineRange.location,
                    length: max(0, lineContentLength - marker.length)
                )
                return DetectedShortcutLine(
                    kind: marker.kind,
                    replacementRange: markerRange,
                    replacementText: "",
                    contentRangeAfterReplacement: contentRange
                )
            }

            let next = NSMaxRange(lineRange)
            if next <= lineStart || next >= nsText.length { break }
            lineStart = next
        }

        return nil
    }

    private func marker(in line: String) -> (kind: ShortcutKind, length: Int)? {
        if line.hasPrefix("## ") {
            return (.heading(2), 3)
        }

        if line == "##" {
            return (.heading(2), 2)
        }

        if line.hasPrefix("# ") {
            return (.heading(1), 2)
        }

        if line == "#" {
            return (.heading(1), 1)
        }

        if line.hasPrefix("[ ] ") {
            return (.checkbox, 4)
        }

        if line == "[ ]" {
            return (.checkbox, 3)
        }

        if line.hasPrefix("[] ") {
            return (.checkbox, 3)
        }

        if line == "[]" {
            return (.checkbox, 2)
        }

        if line.hasPrefix("- ") {
            return (.bullet, 2)
        }

        if line == "-" {
            return (.bullet, 1)
        }

        if let numberMarker = numberMarkerLength(in: line), numberMarker > 0 {
            return (.numbered, numberMarker)
        }

        return nil
    }

    private func formatRange(for detected: DetectedShortcutLine, segments: [GoogleDocsTextSegment]) throws -> GoogleRange {
        if detected.contentRangeAfterReplacement.length == 0 {
            let segment = try segment(at: detected.contentRangeAfterReplacement.location, segments: segments)
            let index = segment.googleStartIndex + detected.contentRangeAfterReplacement.location - segment.localRange.location
            return GoogleRange(tabID: segment.tabID, startIndex: index, endIndex: min(segment.googleEndIndex, index + 1))
        }

        let startSegment = try segment(at: detected.contentRangeAfterReplacement.location, segments: segments)
        let endLocation = max(detected.contentRangeAfterReplacement.location, NSMaxRange(detected.contentRangeAfterReplacement) - 1)
        let endSegment = try segment(at: endLocation, segments: segments)

        guard startSegment.tabID == endSegment.tabID else {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        let startIndex = startSegment.googleStartIndex + detected.contentRangeAfterReplacement.location - startSegment.localRange.location
        let endIndex = endSegment.googleStartIndex + endLocation - endSegment.localRange.location + 1

        return GoogleRange(tabID: startSegment.tabID, startIndex: startIndex, endIndex: max(startIndex, endIndex))
    }

    private func segment(at localLocation: Int, segments: [GoogleDocsTextSegment]) throws -> GoogleDocsTextSegment {
        for segment in segments {
            if localLocation >= segment.localRange.location && localLocation < NSMaxRange(segment.localRange) {
                return segment
            }
        }

        throw GoogleDocsServiceError.unsupportedEditRange
    }

    private func request(for kind: ShortcutKind, range: GoogleRange) -> GoogleDocsFormattingRequest {
        switch kind {
        case .heading(let level):
            return .heading(level: level, tabID: range.tabID, startIndex: range.startIndex, endIndex: range.endIndex)
        case .bullet:
            return .bulletList(tabID: range.tabID, startIndex: range.startIndex, endIndex: range.endIndex)
        case .numbered:
            return .numberedList(tabID: range.tabID, startIndex: range.startIndex, endIndex: range.endIndex)
        case .checkbox:
            return .checkboxList(tabID: range.tabID, startIndex: range.startIndex, endIndex: range.endIndex)
        case .link(let url):
            return .link(url: url, tabID: range.tabID, startIndex: range.startIndex, endIndex: range.endIndex)
        }
    }

    private func numberMarkerLength(in text: String) -> Int? {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\. ?"#),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return nil
        }

        return match.range.length
    }

    private func wholeLineLink(in text: String) -> (label: String, url: URL)? {
        let pattern = #"^\[([^\]]+)\]\((https?://[^\s)]+)\)$"#
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)),
              result.numberOfRanges == 3 else { return nil }

        let label = nsText.substring(with: result.range(at: 1))
        let urlText = nsText.substring(with: result.range(at: 2))
        guard let url = URL(string: urlText) else { return nil }

        return (label, url)
    }
}
