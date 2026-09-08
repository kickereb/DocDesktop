import Foundation

enum DriveServiceError: LocalizedError {
    case invalidURL
    case requestFailed(Int, String?)
    case invalidResponse
    case notGoogleDoc
    case documentIDNotFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The Drive request URL is invalid."
        case .requestFailed(let statusCode, let message):
            if let message, !message.isEmpty {
                return "Drive request failed with status \(statusCode): \(message)"
            }
            return "Drive request failed with status \(statusCode)."
        case .invalidResponse:
            return "Google Drive returned invalid data."
        case .notGoogleDoc:
            return "The selected file is not a Google Doc."
        case .documentIDNotFound:
            return "Paste a valid Google Docs URL."
        }
    }
}

struct DriveService {
    private let authManager: GoogleAuthManager
    private let baseURL = URL(string: "https://www.googleapis.com/drive/v3")!
    private let decoder: JSONDecoder

    init(authManager: GoogleAuthManager = .shared) {
        self.authManager = authManager
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func listMyDriveDocuments() async throws -> [DriveFile] {
        try await listDocuments(query: "mimeType='application/vnd.google-apps.document' and trashed=false", corpus: .user, driveID: nil)
    }

    func listSharedWithMeDocuments() async throws -> [DriveFile] {
        try await listDocuments(query: "mimeType='application/vnd.google-apps.document' and trashed=false and sharedWithMe=true", corpus: .user, driveID: nil)
    }

    func listSharedDrives() async throws -> [SharedDrive] {
        var components = URLComponents(url: baseURL.appending(path: "drives"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "fields", value: "drives(id,name)")
        ]

        let response: SharedDrivesResponse = try await send(components: components)
        return response.drives
    }

    func listDocuments(in sharedDrive: SharedDrive) async throws -> [DriveFile] {
        try await listDocuments(query: "mimeType='application/vnd.google-apps.document' and trashed=false", corpus: .drive, driveID: sharedDrive.id)
    }

    func verifyDocument(urlText: String) async throws -> DriveFile {
        guard let documentID = GoogleDocsURLParser.documentID(from: urlText) else {
            throw DriveServiceError.documentIDNotFound
        }

        return try await file(id: documentID)
    }

    private func file(id: String) async throws -> DriveFile {
        var components = URLComponents(url: baseURL.appending(path: "files/\(id)"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: "id,name,mimeType,webViewLink,driveId,modifiedTime,capabilities(canEdit)")
        ]

        let response: DriveFileResponse = try await send(components: components)
        guard response.mimeType == "application/vnd.google-apps.document" else {
            throw DriveServiceError.notGoogleDoc
        }

        return response.driveFile
    }

    private func listDocuments(query: String, corpus: Corpus, driveID: String?) async throws -> [DriveFile] {
        var components = URLComponents(url: baseURL.appending(path: "files"), resolvingAgainstBaseURL: false)
        var queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "pageSize", value: "25"),
            URLQueryItem(name: "orderBy", value: "modifiedTime desc"),
            URLQueryItem(name: "supportsAllDrives", value: "true"),
            URLQueryItem(name: "includeItemsFromAllDrives", value: "true"),
            URLQueryItem(name: "fields", value: "files(id,name,mimeType,webViewLink,driveId,modifiedTime,capabilities(canEdit))")
        ]

        switch corpus {
        case .user:
            queryItems.append(URLQueryItem(name: "corpora", value: "user"))
        case .drive:
            queryItems.append(URLQueryItem(name: "corpora", value: "drive"))
            queryItems.append(URLQueryItem(name: "driveId", value: driveID))
        }

        components?.queryItems = queryItems
        let response: DriveFilesResponse = try await send(components: components)
        return response.files
            .filter { $0.mimeType == "application/vnd.google-apps.document" }
            .map(\.driveFile)
    }

    private func send<Response: Decodable>(components: URLComponents?) async throws -> Response {
        guard let url = components?.url else {
            throw DriveServiceError.invalidURL
        }

        let accessToken = try await authManager.validAccessToken()
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DriveServiceError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorResponse = try? decoder.decode(GoogleAPIErrorResponse.self, from: data)
            throw DriveServiceError.requestFailed(httpResponse.statusCode, errorResponse?.message)
        }

        return try decoder.decode(Response.self, from: data)
    }

    private enum Corpus {
        case user
        case drive
    }
}

private struct DriveFilesResponse: Decodable {
    let files: [DriveFileResponse]
}

private struct SharedDrivesResponse: Decodable {
    let drives: [SharedDrive]
}

private struct DriveFileResponse: Decodable {
    let id: String
    let name: String
    let mimeType: String
    let webViewLink: URL?
    let driveId: String?
    let modifiedTime: Date?
    let capabilities: Capabilities?

    var driveFile: DriveFile {
        DriveFile(
            id: id,
            name: name,
            webViewLink: webViewLink,
            driveId: driveId,
            modifiedTime: modifiedTime,
            canEdit: capabilities?.canEdit ?? false
        )
    }

    struct Capabilities: Decodable {
        let canEdit: Bool?
    }
}

private struct GoogleAPIErrorResponse: Decodable {
    let error: APIError?

    var message: String? {
        error?.message
    }

    struct APIError: Decodable {
        let message: String?
    }
}
