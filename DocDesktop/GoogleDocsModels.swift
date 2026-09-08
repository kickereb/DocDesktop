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

struct GoogleDocsTextSegment {
    let localRange: NSRange
    let googleStartIndex: Int
    let googleEndIndex: Int
    let tabID: String?
}

struct GoogleDocsTextEdit {
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
        }
    }
}
