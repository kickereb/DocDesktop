import Foundation
import Observation

@MainActor
@Observable
final class DocumentContentViewModel {
    private(set) var document: GoogleDocsDocument?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var statusMessage = "No document loaded"
    private(set) var errorMessage: String?
    private(set) var editedText = ""
    private(set) var hasUnsavedChanges = false

    @ObservationIgnored private let docsService: GoogleDocsService
    @ObservationIgnored private let indexMapper = GoogleDocsIndexMapper()
    @ObservationIgnored private let shortcutMapper = GoogleDocsFormattingShortcutMapper()
    @ObservationIgnored private let syncPolicy = DocumentSyncPolicy()
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    private var selectedDocument: SelectedDocument?

    init(docsService: GoogleDocsService = GoogleDocsService()) {
        self.docsService = docsService
    }

    deinit {
        autosaveTask?.cancel()
        syncTask?.cancel()
    }

    func load(selectedDocument: SelectedDocument?) async {
        autosaveTask?.cancel()
        syncTask?.cancel()
        self.selectedDocument = selectedDocument

        guard let selectedDocument else {
            document = nil
            editedText = ""
            hasUnsavedChanges = false
            statusMessage = "No document selected"
            errorMessage = nil
            return
        }

        isLoading = true
        statusMessage = "Loading document"
        errorMessage = nil

        do {
            let loadedDocument = try await docsService.loadDocument(id: selectedDocument.id)
            replaceDocumentIfSafe(loadedDocument)
            hasUnsavedChanges = false
            statusMessage = selectedDocument.canEdit ? "Loaded" : "Loaded read-only"
            startRemoteSync()
        } catch {
            document = nil
            editedText = ""
            hasUnsavedChanges = false
            statusMessage = "Document load failed"
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refresh() async {
        guard let selectedDocument else {
            await load(selectedDocument: nil)
            return
        }

        if hasUnsavedChanges {
            statusMessage = "Unsaved"
            errorMessage = "Save or discard local changes before refresh."
            return
        }

        isLoading = true
        statusMessage = "Refreshing"
        errorMessage = nil

        do {
            let loadedDocument = try await docsService.loadDocument(id: selectedDocument.id)
            replaceDocumentIfSafe(loadedDocument)
            statusMessage = selectedDocument.canEdit ? "Loaded" : "Loaded read-only"
        } catch {
            statusMessage = "Refresh failed"
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func updateEditedText(_ text: String) {
        editedText = text
        guard let document, text != document.plainText else {
            hasUnsavedChanges = false
            return
        }

        hasUnsavedChanges = true
        errorMessage = nil
        statusMessage = "Unsaved"
        scheduleAutosave()
    }

    func saveNow() async {
        autosaveTask?.cancel()
        await savePendingChanges()
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self?.savePendingChanges()
        }
    }

    private func savePendingChanges() async {
        guard let selectedDocument, let document else {
            errorMessage = GoogleDocsServiceError.noDocumentLoaded.localizedDescription
            return
        }

        guard selectedDocument.canEdit else {
            statusMessage = "Read only"
            errorMessage = nil
            return
        }

        guard editedText != document.plainText else {
            hasUnsavedChanges = false
            statusMessage = "Saved"
            return
        }

        do {
            let shortcut = shortcutMapper.shortcut(from: document.plainText, to: editedText, segments: document.textSegments)
            let edit = try shortcut?.edit ?? indexMapper.edit(from: document.plainText, to: editedText, segments: document.textSegments)
            let formattingRequests = shortcut?.formattingRequests ?? []
            isSaving = true
            statusMessage = formattingRequests.isEmpty ? "Saving" : "Saving format"
            errorMessage = nil
            try await docsService.save(
                edit: edit,
                formattingRequests: formattingRequests,
                documentID: document.documentID,
                revisionID: document.revisionID
            )
            let refreshedDocument = try await docsService.loadDocument(id: document.documentID)
            replaceDocumentIfSafe(refreshedDocument)
            hasUnsavedChanges = false
            statusMessage = formattingRequests.isEmpty ? "Saved" : "Formatted"
        } catch GoogleDocsServiceError.noChangesToSave {
            hasUnsavedChanges = false
            statusMessage = "Saved"
        } catch {
            statusMessage = "Save failed"
            errorMessage = safeSaveMessage(from: error)
        }

        isSaving = false
    }

    private func replaceDocumentIfSafe(_ loadedDocument: GoogleDocsDocument) {
        guard !hasUnsavedChanges else { return }
        document = loadedDocument
        editedText = loadedDocument.plainText
    }

    private func startRemoteSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                await self?.syncFromRemoteIfSafe()
            }
        }
    }

    private func syncFromRemoteIfSafe() async {
        guard let selectedDocument, !isLoading, !isSaving else { return }

        do {
            let remoteDocument = try await docsService.loadDocument(id: selectedDocument.id)
            switch syncPolicy.decision(hasUnsavedChanges: hasUnsavedChanges, localRevisionID: document?.revisionID, remoteRevisionID: remoteDocument.revisionID) {
            case .loadRemote:
                replaceDocumentIfSafe(remoteDocument)
                statusMessage = "Remote changes loaded"
                errorMessage = nil
            case .keepLocalUnsaved:
                statusMessage = "Unsaved"
            case .noChange:
                break
            }
        } catch {
            statusMessage = "Sync failed"
            errorMessage = error.localizedDescription
        }
    }

    private func safeSaveMessage(from error: Error) -> String {
        let message = error.localizedDescription
        if message.localizedCaseInsensitiveContains("revision") || message.localizedCaseInsensitiveContains("write control") {
            return "Remote document changed before save. Your local text is still here. Open in Google Docs or copy your text, then refresh."
        }
        return message
    }
}
