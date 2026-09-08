import Foundation

struct ActiveDocumentStore {
    private static let selectedDocumentKey = "selectedDocument"

    func load() -> SelectedDocument? {
        guard let data = UserDefaults.standard.data(forKey: Self.selectedDocumentKey) else {
            return nil
        }

        return try? JSONDecoder().decode(SelectedDocument.self, from: data)
    }

    func save(_ document: SelectedDocument) {
        guard let data = try? JSONEncoder().encode(document) else { return }
        UserDefaults.standard.set(data, forKey: Self.selectedDocumentKey)
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: Self.selectedDocumentKey)
    }
}
