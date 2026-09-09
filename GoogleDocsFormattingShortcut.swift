import Foundation

struct GoogleDocsFormattingShortcut: Equatable {
    let edit: GoogleDocsTextEdit
    let formattingRequests: [GoogleDocsFormattingRequest]
    let normalizedText: String
    let localFormattingRequests: [GoogleDocsLocalFormattingRequest]
}

enum GoogleDocsFormattingRequest: Equatable {
    case heading(level: Int, tabID: String?, startIndex: Int, endIndex: Int)
    case normalText(tabID: String?, startIndex: Int, endIndex: Int)
    case bulletList(tabID: String?, startIndex: Int, endIndex: Int)
    case numberedList(tabID: String?, startIndex: Int, endIndex: Int)
    case checkboxList(tabID: String?, startIndex: Int, endIndex: Int)
    case link(url: URL, tabID: String?, startIndex: Int, endIndex: Int)
    case textStyle(tabID: String?, startIndex: Int, endIndex: Int, bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil)
}

enum GoogleDocsLocalFormattingRequest: Equatable {
    case heading(level: Int, range: NSRange)
    case normalText(range: NSRange)
    case bulletList(range: NSRange)
    case numberedList(range: NSRange)
    case checkboxList(range: NSRange)
    case link(url: URL, range: NSRange)
    case textStyle(range: NSRange, bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil)
}

enum GoogleDocsToolbarFormattingCommand: Equatable {
    case bold
    case italic
    case underline
    case strikethrough
    case normalText
    case heading(Int)
    case bulletList
    case numberedList
    case link(URL)
}

struct GoogleDocsFormattingShortcutMapper {
    private let indexMapper = GoogleDocsIndexMapper()

    func shortcut(from originalText: String, to editedText: String, segments: [GoogleDocsTextSegment]) -> GoogleDocsFormattingShortcut? {
        let detectedLines = detectedShortcutLines(in: editedText)
        guard !detectedLines.isEmpty else { return nil }

        var normalizedText = editedText
        var localFormattingRequests: [GoogleDocsLocalFormattingRequest] = []

        for detected in detectedLines.reversed() {
            normalizedText = (normalizedText as NSString).replacingCharacters(in: detected.replacementRange, with: detected.replacementText)
        }

        for detected in detectedLines {
            let localRange = normalizedRange(for: detected, in: detectedLines)
            localFormattingRequests.append(localRequest(for: detected.kind, range: localRange))
        }

        let edit: GoogleDocsTextEdit

        do {
            edit = try indexMapper.edit(from: originalText, to: normalizedText, segments: segments)
        } catch GoogleDocsServiceError.noChangesToSave {
            let formattingRequests = detectedLines.compactMap { detected -> GoogleDocsFormattingRequest? in
                guard let range = try? formatRange(for: normalizedRange(for: detected, in: detectedLines), segments: segments) else { return nil }
                return request(for: detected.kind, range: range)
            }
            guard !formattingRequests.isEmpty else { return nil }
            let firstRequest = formattingRequests[0]
            return GoogleDocsFormattingShortcut(
                edit: GoogleDocsTextEdit(tabID: firstRequest.tabID, googleStartIndex: firstRequest.startIndex, googleEndIndex: firstRequest.startIndex, replacementText: ""),
                formattingRequests: formattingRequests,
                normalizedText: normalizedText,
                localFormattingRequests: localFormattingRequests
            )
        } catch {
            return nil
        }

        let formattingRequests = detectedLines.map { detected in
            let localRange = normalizedRange(for: detected, in: detectedLines)
            let fallbackRange = GoogleRange(
                tabID: edit.tabID,
                startIndex: edit.googleStartIndex + localRange.location - normalizedEditStart(originalText: originalText, normalizedText: normalizedText),
                endIndex: edit.googleStartIndex + NSMaxRange(localRange) - normalizedEditStart(originalText: originalText, normalizedText: normalizedText)
            )
            let formatRange = (try? formatRange(for: localRange, segments: segments)) ?? fallbackRange
            return request(for: detected.kind, range: formatRange)
        }

        return GoogleDocsFormattingShortcut(
            edit: edit,
            formattingRequests: formattingRequests,
            normalizedText: normalizedText,
            localFormattingRequests: localFormattingRequests
        )
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

    private func detectedShortcutLines(in text: String) -> [DetectedShortcutLine] {
        let nsText = text as NSString
        var lineStart = 0
        var detectedLines: [DetectedShortcutLine] = []

        while lineStart <= nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let rawLine = nsText.substring(with: lineRange)
            let line = rawLine.trimmingCharacters(in: .newlines)
            let lineContentLength = (line as NSString).length

            if let link = wholeLineLink(in: line) {
                let lineContentRange = NSRange(location: lineRange.location, length: lineContentLength)
                detectedLines.append(DetectedShortcutLine(
                    kind: .link(link.url),
                    replacementRange: lineContentRange,
                    replacementText: link.label,
                    contentRangeAfterReplacement: NSRange(location: lineRange.location, length: (link.label as NSString).length)
                ))
                let next = NSMaxRange(lineRange)
                if next <= lineStart || next >= nsText.length { break }
                lineStart = next
                continue
            }

            if let marker = marker(in: line) {
                let markerRange = NSRange(location: lineRange.location, length: marker.length)
                let contentRange = NSRange(
                    location: lineRange.location,
                    length: max(0, lineContentLength - marker.length)
                )
                detectedLines.append(DetectedShortcutLine(
                    kind: marker.kind,
                    replacementRange: markerRange,
                    replacementText: "",
                    contentRangeAfterReplacement: contentRange
                ))
            }

            let next = NSMaxRange(lineRange)
            if next <= lineStart || next >= nsText.length { break }
            lineStart = next
        }

        return detectedLines
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

    private func normalizedRange(for detected: DetectedShortcutLine, in detectedLines: [DetectedShortcutLine]) -> NSRange {
        let precedingDelta = detectedLines
            .filter { $0.replacementRange.location < detected.replacementRange.location }
            .reduce(0) { partialResult, line in
                partialResult + (line.replacementText as NSString).length - line.replacementRange.length
            }
        let start = detected.contentRangeAfterReplacement.location + precedingDelta
        return NSRange(location: start, length: detected.contentRangeAfterReplacement.length)
    }

    private func normalizedEditStart(originalText: String, normalizedText: String) -> Int {
        let original = originalText as NSString
        let normalized = normalizedText as NSString
        let limit = min(original.length, normalized.length)
        var index = 0

        while index < limit && original.character(at: index) == normalized.character(at: index) {
            index += 1
        }

        return index
    }

    private func formatRange(for localRange: NSRange, segments: [GoogleDocsTextSegment]) throws -> GoogleRange {
        if localRange.length == 0 {
            let segment = try segment(at: localRange.location, segments: segments)
            let index = segment.googleStartIndex + localRange.location - segment.localRange.location
            return GoogleRange(tabID: segment.tabID, startIndex: index, endIndex: min(segment.googleEndIndex, index + 1))
        }

        let startSegment = try segment(at: localRange.location, segments: segments)
        let endLocation = max(localRange.location, NSMaxRange(localRange) - 1)
        let endSegment = try segment(at: endLocation, segments: segments)

        guard startSegment.tabID == endSegment.tabID else {
            throw GoogleDocsServiceError.unsupportedEditRange
        }

        let startIndex = startSegment.googleStartIndex + localRange.location - startSegment.localRange.location
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

    private func localRequest(for kind: ShortcutKind, range: NSRange) -> GoogleDocsLocalFormattingRequest {
        switch kind {
        case .heading(let level):
            return .heading(level: level, range: range)
        case .bullet:
            return .bulletList(range: range)
        case .numbered:
            return .numberedList(range: range)
        case .checkbox:
            return .checkboxList(range: range)
        case .link(let url):
            return .link(url: url, range: range)
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

private extension GoogleDocsFormattingRequest {
    var tabID: String? {
        switch self {
        case .heading(_, let tabID, _, _),
             .normalText(let tabID, _, _),
             .bulletList(let tabID, _, _),
             .numberedList(let tabID, _, _),
             .checkboxList(let tabID, _, _),
             .link(_, let tabID, _, _),
             .textStyle(let tabID, _, _, _, _, _, _):
            return tabID
        }
    }

    var startIndex: Int {
        switch self {
        case .heading(_, _, let startIndex, _),
             .normalText(_, let startIndex, _),
             .bulletList(_, let startIndex, _),
             .numberedList(_, let startIndex, _),
             .checkboxList(_, let startIndex, _),
             .link(_, _, let startIndex, _),
             .textStyle(_, let startIndex, _, _, _, _, _):
            return startIndex
        }
    }
}
