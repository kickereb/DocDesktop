import Foundation

enum GoogleDocsURLParser {
    static func documentID(from text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.host == "docs.google.com" else {
            return nil
        }

        let parts = url.pathComponents
        guard parts.count >= 4, parts[1] == "document", parts[2] == "d" else {
            return nil
        }

        let documentID = parts[3]
        return documentID.isEmpty ? nil : documentID
    }
}
