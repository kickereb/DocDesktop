import AppKit
import Foundation

struct GoogleDocsService {
    private let authManager: GoogleAuthManager
    private let baseURL = URL(string: "https://docs.googleapis.com/v1")!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(authManager: GoogleAuthManager = .shared) {
        self.authManager = authManager
    }

    func loadDocument(id: String) async throws -> GoogleDocsDocument {
        var components = URLComponents(url: baseURL.appending(path: "documents/\(id)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "includeTabsContent", value: "true")
        ]

        guard let url = components?.url else {
            throw GoogleDocsServiceError.invalidURL
        }

        let accessToken = try await authManager.validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDocsServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(GoogleDocsErrorResponse.self, from: data)
            throw GoogleDocsServiceError.requestFailed(httpResponse.statusCode, errorResponse?.message)
        }

        let apiDocument = try decoder.decode(GoogleDocsAPIDocument.self, from: data)
        let images = await loadInlineImages(from: apiDocument, accessToken: accessToken)
        return GoogleDocsParser(loadedImages: images).parse(apiDocument)
    }

    func save(
        edit: GoogleDocsTextEdit,
        formattingRequests: [GoogleDocsFormattingRequest] = [],
        documentID: String,
        revisionID: String?
    ) async throws {
        guard edit.googleEndIndex > edit.googleStartIndex || !edit.replacementText.isEmpty || !formattingRequests.isEmpty else {
            throw GoogleDocsServiceError.noChangesToSave
        }

        let url = baseURL.appending(path: "documents/\(documentID):batchUpdate")
        let accessToken = try await authManager.validAccessToken()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(
            BatchUpdateRequest(edit: edit, formattingRequests: formattingRequests, revisionID: revisionID)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleDocsServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(GoogleDocsErrorResponse.self, from: data)
            throw GoogleDocsServiceError.requestFailed(httpResponse.statusCode, errorResponse?.message)
        }
    }

    private func loadInlineImages(from document: GoogleDocsAPIDocument, accessToken: String) async -> [String: NSImage] {
        let imageURLs = inlineImageURLs(from: document)
        guard !imageURLs.isEmpty else { return [:] }

        return await withTaskGroup(of: (String, NSImage?).self) { group in
            for (objectId, url) in imageURLs {
                group.addTask {
                    let image = await loadImage(from: url, accessToken: accessToken)
                    return (objectId, image)
                }
            }

            var loadedImages: [String: NSImage] = [:]
            for await (objectId, image) in group {
                if let image {
                    loadedImages[objectId] = image
                }
            }
            return loadedImages
        }
    }

    private func inlineImageURLs(from document: GoogleDocsAPIDocument) -> [String: URL] {
        var objectMap = document.inlineObjects ?? [:]

        for tab in document.tabs ?? [] {
            objectMap.merge(inlineObjects(from: tab)) { current, _ in current }
        }

        return objectMap.compactMapValues { inlineObject in
            inlineObject.inlineObjectProperties?.embeddedObject?.imageProperties?.contentUri
                ?? inlineObject.inlineObjectProperties?.embeddedObject?.imageProperties?.sourceUri
        }
    }

    private func inlineObjects(from tab: GoogleDocsAPIDocument.Tab) -> [String: GoogleDocsAPIDocument.InlineObject] {
        var objectMap = tab.documentTab?.inlineObjects ?? [:]

        for childTab in tab.childTabs ?? [] {
            objectMap.merge(inlineObjects(from: childTab)) { current, _ in current }
        }

        return objectMap
    }

    private func loadImage(from url: URL, accessToken: String) async -> NSImage? {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        if let (data, response) = try? await URLSession.shared.data(for: request),
           let httpResponse = response as? HTTPURLResponse,
           200..<300 ~= httpResponse.statusCode,
           let image = NSImage(data: data) {
            return image
        }

        if let (data, response) = try? await URLSession.shared.data(from: url),
           let httpResponse = response as? HTTPURLResponse,
           200..<300 ~= httpResponse.statusCode {
            return NSImage(data: data)
        }

        return nil
    }
}

private struct BatchUpdateRequest: Encodable {
    let requests: [BatchRequest]
    let writeControl: WriteControl?

    init(edit: GoogleDocsTextEdit, formattingRequests: [GoogleDocsFormattingRequest], revisionID: String?) {
        var requests: [BatchRequest] = []

        if edit.googleEndIndex > edit.googleStartIndex {
            requests.append(.deleteContentRange(DeleteContentRangeRequest(range: EditRange(startIndex: edit.googleStartIndex, endIndex: edit.googleEndIndex, tabID: edit.tabID))))
        }

        if !edit.replacementText.isEmpty {
            requests.append(.insertText(InsertTextRequest(text: edit.replacementText, location: EditLocation(index: edit.googleStartIndex, tabID: edit.tabID))))
        }

        requests.append(contentsOf: formattingRequests.map(BatchRequest.init(formattingRequest:)))
        if requests.isEmpty {
            self.requests = []
            self.writeControl = nil
            return
        }

        self.requests = requests
        self.writeControl = revisionID.map { WriteControl(targetRevisionId: $0) }
    }
}

private enum BatchRequest: Encodable {
    case deleteContentRange(DeleteContentRangeRequest)
    case insertText(InsertTextRequest)
    case updateParagraphStyle(UpdateParagraphStyleRequest)
    case createParagraphBullets(CreateParagraphBulletsRequest)
    case updateTextStyle(UpdateTextStyleRequest)

    init(formattingRequest: GoogleDocsFormattingRequest) {
        switch formattingRequest {
        case .heading(let level, let tabID, let startIndex, let endIndex):
            self = .updateParagraphStyle(
                UpdateParagraphStyleRequest(
                    range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID),
                    paragraphStyle: ParagraphStylePayload(namedStyleType: "HEADING_\(level)"),
                    fields: "namedStyleType"
                )
            )
        case .normalText(let tabID, let startIndex, let endIndex):
            self = .updateParagraphStyle(
                UpdateParagraphStyleRequest(
                    range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID),
                    paragraphStyle: ParagraphStylePayload(namedStyleType: "NORMAL_TEXT"),
                    fields: "namedStyleType"
                )
            )
        case .bulletList(let tabID, let startIndex, let endIndex):
            self = .createParagraphBullets(
                CreateParagraphBulletsRequest(range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID), bulletPreset: "BULLET_DISC_CIRCLE_SQUARE")
            )
        case .numberedList(let tabID, let startIndex, let endIndex):
            self = .createParagraphBullets(
                CreateParagraphBulletsRequest(range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID), bulletPreset: "NUMBERED_DECIMAL_ALPHA_ROMAN")
            )
        case .checkboxList(let tabID, let startIndex, let endIndex):
            self = .createParagraphBullets(
                CreateParagraphBulletsRequest(range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID), bulletPreset: "BULLET_CHECKBOX")
            )
        case .link(let url, let tabID, let startIndex, let endIndex):
            self = .updateTextStyle(
                UpdateTextStyleRequest(
                    range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID),
                    textStyle: TextStylePayload(link: LinkPayload(url: url.absoluteString)),
                    fields: "link"
                )
            )
        case .textStyle(let tabID, let startIndex, let endIndex, let bold, let italic, let underline, let strikethrough):
            self = .updateTextStyle(
                UpdateTextStyleRequest(
                    range: EditRange(startIndex: startIndex, endIndex: endIndex, tabID: tabID),
                    textStyle: TextStylePayload(
                        link: nil,
                        bold: bold,
                        italic: italic,
                        underline: underline,
                        strikethrough: strikethrough
                    ),
                    fields: textStyleFields(
                        bold: bold,
                        italic: italic,
                        underline: underline,
                        strikethrough: strikethrough,
                        link: false
                    )
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .deleteContentRange(let request):
            try container.encode(request, forKey: .deleteContentRange)
        case .insertText(let request):
            try container.encode(request, forKey: .insertText)
        case .updateParagraphStyle(let request):
            try container.encode(request, forKey: .updateParagraphStyle)
        case .createParagraphBullets(let request):
            try container.encode(request, forKey: .createParagraphBullets)
        case .updateTextStyle(let request):
            try container.encode(request, forKey: .updateTextStyle)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case deleteContentRange
        case insertText
        case updateParagraphStyle
        case createParagraphBullets
        case updateTextStyle
    }
}

private struct DeleteContentRangeRequest: Encodable {
    let range: EditRange
}

private struct InsertTextRequest: Encodable {
    let text: String
    let location: EditLocation
}

private struct UpdateParagraphStyleRequest: Encodable {
    let range: EditRange
    let paragraphStyle: ParagraphStylePayload
    let fields: String
}

private struct ParagraphStylePayload: Encodable {
    let namedStyleType: String
}

private struct CreateParagraphBulletsRequest: Encodable {
    let range: EditRange
    let bulletPreset: String
}

private struct UpdateTextStyleRequest: Encodable {
    let range: EditRange
    let textStyle: TextStylePayload
    let fields: String
}

private struct TextStylePayload: Encodable {
    let link: LinkPayload?
    let bold: Bool?
    let italic: Bool?
    let underline: Bool?
    let strikethrough: Bool?

    init(link: LinkPayload? = nil, bold: Bool? = nil, italic: Bool? = nil, underline: Bool? = nil, strikethrough: Bool? = nil) {
        self.link = link
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strikethrough = strikethrough
    }
}

private struct LinkPayload: Encodable {
    let url: String
}

private func textStyleFields(
    bold: Bool?,
    italic: Bool?,
    underline: Bool?,
    strikethrough: Bool?,
    link: Bool
) -> String {
    var fields: [String] = []
    if bold != nil { fields.append("bold") }
    if italic != nil { fields.append("italic") }
    if underline != nil { fields.append("underline") }
    if strikethrough != nil { fields.append("strikethrough") }
    if link { fields.append("link") }
    return fields.joined(separator: ",")
}

private struct EditRange: Encodable {
    let startIndex: Int
    let endIndex: Int
    let tabID: String?

    enum CodingKeys: String, CodingKey {
        case startIndex
        case endIndex
        case tabID = "tabId"
    }
}

private struct EditLocation: Encodable {
    let index: Int
    let tabID: String?

    enum CodingKeys: String, CodingKey {
        case index
        case tabID = "tabId"
    }
}

private struct WriteControl: Encodable {
    let targetRevisionId: String
}

private struct GoogleDocsErrorResponse: Decodable {
    let error: APIError?

    var message: String? {
        error?.message
    }

    struct APIError: Decodable {
        let message: String?
    }
}
