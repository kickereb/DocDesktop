import Foundation
import Observation

@MainActor
@Observable
final class DocumentPickerViewModel {
    private(set) var myDriveDocuments: [DriveFile] = []
    private(set) var sharedWithMeDocuments: [DriveFile] = []
    private(set) var sharedDrives: [SharedDrive] = []
    private(set) var sharedDriveDocuments: [String: [DriveFile]] = [:]
    private(set) var selectedDocument: SelectedDocument?
    private(set) var isLoading = false
    private(set) var statusMessage = "Select one Google Doc."
    private(set) var errorMessage: String?

    var pastedURL = ""
    var searchText = ""

    var filteredMyDriveDocuments: [DriveFile] {
        filtered(myDriveDocuments)
    }

    var filteredSharedWithMeDocuments: [DriveFile] {
        filtered(sharedWithMeDocuments)
    }

    func filteredSharedDriveDocuments(for sharedDrive: SharedDrive) -> [DriveFile] {
        filtered(sharedDriveDocuments[sharedDrive.id] ?? [])
    }

    @ObservationIgnored private let driveService: DriveService
    @ObservationIgnored private let activeDocumentStore = ActiveDocumentStore()

    init(driveService: DriveService = DriveService()) {
        self.driveService = driveService
        selectedDocument = activeDocumentStore.load()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Loading Drive documents"

        var loadErrors: [String] = []

        do {
            myDriveDocuments = try await driveService.listMyDriveDocuments()
        } catch {
            myDriveDocuments = []
            loadErrors.append("My Drive: \(error.localizedDescription)")
        }

        do {
            sharedWithMeDocuments = try await driveService.listSharedWithMeDocuments()
        } catch {
            sharedWithMeDocuments = []
            loadErrors.append("Shared with me: \(error.localizedDescription)")
        }

        do {
            sharedDrives = try await driveService.listSharedDrives()
            var documentsByDrive: [String: [DriveFile]] = [:]
            for sharedDrive in sharedDrives {
                do {
                    documentsByDrive[sharedDrive.id] = try await driveService.listDocuments(in: sharedDrive)
                } catch {
                    documentsByDrive[sharedDrive.id] = []
                    loadErrors.append("\(sharedDrive.name): \(error.localizedDescription)")
                }
            }
            sharedDriveDocuments = documentsByDrive
        } catch {
            sharedDrives = []
            sharedDriveDocuments = [:]
            loadErrors.append("Shared Drives: \(error.localizedDescription)")
        }

        if loadErrors.isEmpty {
            statusMessage = "Drive documents loaded"
            errorMessage = nil
        } else if hasAnyLoadedDocuments {
            statusMessage = "Some Drive documents loaded"
            errorMessage = loadErrors.first
        } else {
            statusMessage = "Drive load failed"
            errorMessage = loadErrors.first
        }

        isLoading = false
    }

    func select(_ file: DriveFile) {
        let selected = SelectedDocument(
            id: file.id,
            title: file.name,
            webViewLink: file.webViewLink,
            canEdit: file.canEdit
        )
        selectedDocument = selected
        activeDocumentStore.save(selected)
        statusMessage = "Selected \(file.name)"
        errorMessage = nil
    }

    func verifyPastedURL() async {
        isLoading = true
        errorMessage = nil
        statusMessage = "Checking document access"

        do {
            let file = try await driveService.verifyDocument(urlText: pastedURL)
            select(file)
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Document check failed"
        }

        isLoading = false
    }

    func clearSelection() {
        selectedDocument = nil
        activeDocumentStore.clear()
        statusMessage = "Select one Google Doc."
        errorMessage = nil
    }

    private func filtered(_ files: [DriveFile]) -> [DriveFile] {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !search.isEmpty else { return files }
        return files.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    private var hasAnyLoadedDocuments: Bool {
        !myDriveDocuments.isEmpty || !sharedWithMeDocuments.isEmpty || sharedDriveDocuments.values.contains { !$0.isEmpty }
    }
}
