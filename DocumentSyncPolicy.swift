import Foundation

enum DocumentSyncDecision: Equatable {
    case loadRemote
    case keepLocalUnsaved
    case noChange
}

struct DocumentSyncPolicy {
    func decision(hasUnsavedChanges: Bool, localRevisionID: String?, remoteRevisionID: String?) -> DocumentSyncDecision {
        if hasUnsavedChanges {
            return .keepLocalUnsaved
        }

        if localRevisionID != remoteRevisionID {
            return .loadRemote
        }

        return .noChange
    }
}
