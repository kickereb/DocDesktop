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
        guard let edit = try? indexMapper.edit(from: originalText, to: editedText, segments: segments) else {
            return nil
        }

        let replacement = edit.replacementText
        if replacement.hasPrefix("## ") {
            return headingShortcut(level: 2, marker: "## ", edit: edit)
        }

        if replacement.hasPrefix("# ") {
            return headingShortcut(level: 1, marker: "# ", edit: edit)
        }

        if replacement.hasPrefix("[ ] ") {
            return listShortcut(marker: "[ ] ", edit: edit, kind: .checkbox)
        }

        if replacement.hasPrefix("[] ") {
            return listShortcut(marker: "[] ", edit: edit, kind: .checkbox)
        }

        if replacement.hasPrefix("- ") {
            return listShortcut(marker: "- ", edit: edit, kind: .bullet)
        }

        if replacement.range(of: #"^\d+\. "#, options: .regularExpression) != nil {
            return listShortcut(markerLength: numberMarkerLength(in: replacement), edit: edit, kind: .numbered)
        }

        if let linkShortcut = linkShortcut(edit: edit) {
            return linkShortcut
        }

        return nil
    }

    private func headingShortcut(level: Int, marker: String, edit: GoogleDocsTextEdit) -> GoogleDocsFormattingShortcut {
        let cleanText = String(edit.replacementText.dropFirst(marker.count))
        let cleanEdit = GoogleDocsTextEdit(
            tabID: edit.tabID,
            googleStartIndex: edit.googleStartIndex,
            googleEndIndex: edit.googleEndIndex,
            replacementText: cleanText
        )
        let formattingStart = edit.googleStartIndex
        let formattingEnd = edit.googleStartIndex + (cleanText as NSString).length

        return GoogleDocsFormattingShortcut(
            edit: cleanEdit,
            formattingRequests: [
                .heading(level: level, tabID: edit.tabID, startIndex: formattingStart, endIndex: max(formattingStart, formattingEnd))
            ]
        )
    }

    private enum ListKind {
        case bullet
        case numbered
        case checkbox
    }

    private func listShortcut(marker: String, edit: GoogleDocsTextEdit, kind: ListKind) -> GoogleDocsFormattingShortcut {
        listShortcut(markerLength: (marker as NSString).length, edit: edit, kind: kind)
    }

    private func listShortcut(markerLength: Int, edit: GoogleDocsTextEdit, kind: ListKind) -> GoogleDocsFormattingShortcut {
        let replacement = edit.replacementText as NSString
        let cleanText = replacement.substring(from: markerLength)
        let cleanEdit = GoogleDocsTextEdit(
            tabID: edit.tabID,
            googleStartIndex: edit.googleStartIndex,
            googleEndIndex: edit.googleEndIndex,
            replacementText: cleanText
        )
        let formattingStart = edit.googleStartIndex
        let formattingEnd = edit.googleStartIndex + (cleanText as NSString).length
        let request: GoogleDocsFormattingRequest

        switch kind {
        case .bullet:
            request = .bulletList(tabID: edit.tabID, startIndex: formattingStart, endIndex: max(formattingStart, formattingEnd))
        case .numbered:
            request = .numberedList(tabID: edit.tabID, startIndex: formattingStart, endIndex: max(formattingStart, formattingEnd))
        case .checkbox:
            request = .checkboxList(tabID: edit.tabID, startIndex: formattingStart, endIndex: max(formattingStart, formattingEnd))
        }

        return GoogleDocsFormattingShortcut(edit: cleanEdit, formattingRequests: [request])
    }

    private func linkShortcut(edit: GoogleDocsTextEdit) -> GoogleDocsFormattingShortcut? {
        let pattern = #"^\[([^\]]+)\]\((https?://[^\s)]+)\)$"#
        guard let match = edit.replacementText.range(of: pattern, options: .regularExpression) else { return nil }
        guard match.lowerBound == edit.replacementText.startIndex && match.upperBound == edit.replacementText.endIndex else { return nil }

        let nsText = edit.replacementText as NSString
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: edit.replacementText, range: NSRange(location: 0, length: nsText.length)),
              result.numberOfRanges == 3 else { return nil }

        let label = nsText.substring(with: result.range(at: 1))
        let urlText = nsText.substring(with: result.range(at: 2))
        guard let url = URL(string: urlText) else { return nil }

        let cleanEdit = GoogleDocsTextEdit(
            tabID: edit.tabID,
            googleStartIndex: edit.googleStartIndex,
            googleEndIndex: edit.googleEndIndex,
            replacementText: label
        )
        let linkEnd = edit.googleStartIndex + (label as NSString).length

        return GoogleDocsFormattingShortcut(
            edit: cleanEdit,
            formattingRequests: [
                .link(url: url, tabID: edit.tabID, startIndex: edit.googleStartIndex, endIndex: linkEnd)
            ]
        )
    }

    private func numberMarkerLength(in text: String) -> Int {
        let nsText = text as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^\d+\. "#),
              let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else {
            return 0
        }

        return match.range.length
    }
}
