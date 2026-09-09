import AppKit
import Foundation

struct GoogleDocsDocument {
    let documentID: String
    let title: String
    let revisionID: String?
    let attributedText: NSAttributedString
    let textSegments: [GoogleDocsTextSegment]

    var plainText: String {
        attributedText.string
    }
}

struct GoogleDocsTextSegment: Equatable {
    let localRange: NSRange
    let googleStartIndex: Int
    let googleEndIndex: Int
    let tabID: String?
    let textStyle: GoogleDocsTextRunStyle?
    let paragraphStyle: GoogleDocsParagraphRunStyle?
    let listMetadata: GoogleDocsListMetadata?

    init(
        localRange: NSRange,
        googleStartIndex: Int,
        googleEndIndex: Int,
        tabID: String?,
        textStyle: GoogleDocsTextRunStyle? = nil,
        paragraphStyle: GoogleDocsParagraphRunStyle? = nil,
        listMetadata: GoogleDocsListMetadata? = nil
    ) {
        self.localRange = localRange
        self.googleStartIndex = googleStartIndex
        self.googleEndIndex = googleEndIndex
        self.tabID = tabID
        self.textStyle = textStyle
        self.paragraphStyle = paragraphStyle
        self.listMetadata = listMetadata
    }
}

struct GoogleDocsTextRunStyle: Equatable {
    let bold: Bool
    let italic: Bool
    let underline: Bool
    let strikethrough: Bool
    let linkURL: URL?
    let fontSize: Double?
    let fontWeight: Int?
    let foregroundRed: Double?
    let foregroundGreen: Double?
    let foregroundBlue: Double?
    let baselineOffset: String?
}

struct GoogleDocsParagraphRunStyle: Equatable {
    let namedStyleType: String?
    let alignment: String?
    let lineSpacing: Double?
    let spaceAbove: Double?
    let spaceBelow: Double?
    let indentStart: Double?
    let indentEnd: Double?
    let indentFirstLine: Double?
}

struct GoogleDocsListMetadata: Equatable {
    let listID: String?
    let nestingLevel: Int
    let glyphType: String?
    let glyphFormat: String?
}

struct GoogleDocsTextEdit: Equatable {
    let tabID: String?
    let googleStartIndex: Int
    let googleEndIndex: Int
    let replacementText: String
}

enum GoogleDocsServiceError: LocalizedError {
    case invalidURL
    case requestFailed(Int, String?)
    case invalidResponse
    case noDocumentLoaded
    case noChangesToSave
    case unsupportedEditRange
    case paragraphBreakEditUnsupported

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Docs request URL is invalid."
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Docs request failed with status \(statusCode): \(message)"
            }
            return "Docs request failed with status \(statusCode)."
        case .invalidResponse:
            return "Google Docs returned invalid data."
        case .noDocumentLoaded:
            return "No document is loaded."
        case .noChangesToSave:
            return "No changes to save."
        case .unsupportedEditRange:
            return "This edit touches an image, table, or unsupported item. Save smaller text-only edits for now."
        case .paragraphBreakEditUnsupported:
            return "This edit changes a paragraph break. Save text inside one paragraph for now."
        }
    }
}
