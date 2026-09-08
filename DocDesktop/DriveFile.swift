import Foundation

struct DriveFile: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let webViewLink: URL?
    let driveId: String?
    let modifiedTime: Date?
    let canEdit: Bool

    var accessLabel: String {
        canEdit ? "Can edit" : "Read only"
    }
}

struct SharedDrive: Identifiable, Decodable, Equatable {
    let id: String
    let name: String
}

struct SelectedDocument: Codable, Equatable {
    let id: String
    let title: String
    let webViewLink: URL?
    let canEdit: Bool
}
