import AppKit
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
    private(set) var editorAttributedText = NSAttributedString()
    private(set) var editorVersion = 0
    private(set) var hasUnsavedChanges = false

    @ObservationIgnored private let docsService: GoogleDocsService
    @ObservationIgnored private let indexMapper = GoogleDocsIndexMapper()
    @ObservationIgnored private let shortcutMapper = GoogleDocsFormattingShortcutMapper()
    @ObservationIgnored private let syncPolicy = DocumentSyncPolicy()
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var pendingFormattingRequests: [GoogleDocsFormattingRequest] = []
    @ObservationIgnored private let localDraftPrefix = "localMarkdownDraft."
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
            editorAttributedText = NSAttributedString()
            editorVersion += 1
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
            applyLocalDraftIfNeeded(for: selectedDocument.id)
            hasUnsavedChanges = false
            statusMessage = AppDevelopmentMode.localMarkdownEngineOnly ? "Local editor mode" : selectedDocument.canEdit ? "Loaded" : "Loaded read-only"
            if !AppDevelopmentMode.localMarkdownEngineOnly {
                startRemoteSync()
            }
        } catch {
            document = nil
            editedText = ""
            editorAttributedText = NSAttributedString()
            editorVersion += 1
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
        guard let document else {
            editedText = text
            return
        }

        if let shortcut = shortcutMapper.shortcut(from: document.plainText, to: text, segments: document.textSegments) {
            editedText = shortcut.normalizedText
            pendingFormattingRequests = shortcut.formattingRequests
            editorAttributedText = locallyFormattedText(
                baseText: shortcut.normalizedText,
                formattingRequests: shortcut.localFormattingRequests
            )
            editorVersion += 1
        } else {
            editedText = text
        }

        guard editedText != document.plainText || !pendingFormattingRequests.isEmpty else {
            hasUnsavedChanges = false
            return
        }

        hasUnsavedChanges = true
        errorMessage = nil
        statusMessage = AppDevelopmentMode.localMarkdownEngineOnly ? "Local draft" : "Unsaved"

        if AppDevelopmentMode.localMarkdownEngineOnly {
            saveLocalDraft()
            return
        }

        scheduleAutosave()
    }

    func saveNow() async {
        autosaveTask?.cancel()
        await savePendingChanges()
    }

    func applyFormatting(_ command: GoogleDocsToolbarFormattingCommand, selection: NSRange) {
        guard let document else { return }

        let selectedRange = clampedNonEmptyRange(selection, in: editedText)
        guard selectedRange.length > 0 else {
            statusMessage = "Select text"
            errorMessage = nil
            return
        }

        do {
            let googleRange = try indexMapper.googleRange(for: selectedRange, segments: document.textSegments)
            let remoteRequest = remoteFormattingRequest(for: command, googleRange: googleRange)
            let localRequest = localFormattingRequest(for: command, range: selectedRange)
            pendingFormattingRequests.append(remoteRequest)

            let mutableText = NSMutableAttributedString(attributedString: editorAttributedText)
            apply(localRequest, to: mutableText)
            editorAttributedText = mutableText
            editorVersion += 1
            hasUnsavedChanges = true
            errorMessage = nil
            statusMessage = AppDevelopmentMode.localMarkdownEngineOnly ? "Local draft" : "Unsaved format"
            if AppDevelopmentMode.localMarkdownEngineOnly {
                saveLocalDraft()
                return
            }
            scheduleAutosave()
        } catch {
            statusMessage = "Format failed"
            errorMessage = GoogleDocsServiceError.unsupportedEditRange.localizedDescription
        }
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
        if AppDevelopmentMode.localMarkdownEngineOnly {
            saveLocalDraft()
            hasUnsavedChanges = false
            statusMessage = "Local draft saved"
            errorMessage = nil
            return
        }

        guard let selectedDocument, let document else {
            errorMessage = GoogleDocsServiceError.noDocumentLoaded.localizedDescription
            return
        }

        guard selectedDocument.canEdit else {
            statusMessage = "Read only"
            errorMessage = nil
            return
        }

        guard editedText != document.plainText || !pendingFormattingRequests.isEmpty else {
            hasUnsavedChanges = false
            statusMessage = "Saved"
            return
        }

        do {
            let edit = try editForSave(from: document)
            let formattingRequests = pendingFormattingRequests
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
            hasUnsavedChanges = false
            pendingFormattingRequests = []
            replaceDocumentIfSafe(refreshedDocument)
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
        editorAttributedText = loadedDocument.attributedText
        editorVersion += 1
        pendingFormattingRequests = []
    }

    private func applyLocalDraftIfNeeded(for documentID: String) {
        guard AppDevelopmentMode.localMarkdownEngineOnly,
              let draft = UserDefaults.standard.string(forKey: localDraftKey(for: documentID)),
              !draft.isEmpty else {
            return
        }

        editedText = draft
        editorAttributedText = NSAttributedString(
            string: draft,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.white
            ]
        )
        editorVersion += 1
    }

    private func saveLocalDraft() {
        guard let document else { return }
        UserDefaults.standard.set(editedText, forKey: localDraftKey(for: document.documentID))
    }

    private func localDraftKey(for documentID: String) -> String {
        localDraftPrefix + documentID
    }

    private func locallyFormattedText(baseText: String, formattingRequests: [GoogleDocsLocalFormattingRequest]) -> NSAttributedString {
        let output = NSMutableAttributedString(
            string: baseText,
            attributes: [
                .font: NSFont.systemFont(ofSize: 16),
                .foregroundColor: NSColor.white
            ]
        )

        for request in formattingRequests {
            apply(request, to: output)
        }

        return output
    }

    private func apply(_ request: GoogleDocsLocalFormattingRequest, to text: NSMutableAttributedString) {
        switch request {
        case .heading(let level, let range):
            let size: CGFloat = level == 1 ? 30 : level == 2 ? 25 : 21
            text.addAttributes([.font: NSFont.boldSystemFont(ofSize: size)], range: safeRange(range, in: text))
        case .normalText(let range):
            let safeRange = safeRange(range, in: text)
            text.addAttributes([.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.white], range: safeRange)
            text.removeAttribute(.link, range: safeRange)
        case .bulletList(let range):
            applyList(.disc, to: text, range: range)
        case .numberedList(let range):
            applyList(.decimal, to: text, range: range)
        case .checkboxList(let range):
            applyList(.check, to: text, range: range)
        case .link(let url, let range):
            text.addAttributes([
                .link: url,
                .foregroundColor: NSColor.systemBlue,
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ], range: safeRange(range, in: text))
        case .textStyle(let range, let bold, let italic, let underline, let strikethrough):
            let safeRange = safeRange(range, in: text)
            if bold == true || italic == true {
                text.enumerateAttribute(.font, in: safeRange) { value, subrange, _ in
                    let currentFont = value as? NSFont ?? NSFont.systemFont(ofSize: 16)
                    var newFont = currentFont
                    if bold == true {
                        newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .boldFontMask)
                    }
                    if italic == true {
                        newFont = NSFontManager.shared.convert(newFont, toHaveTrait: .italicFontMask)
                    }
                    text.addAttribute(.font, value: newFont, range: subrange)
                }
            }
            if underline == true {
                text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: safeRange)
            }
            if strikethrough == true {
                text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: safeRange)
            }
        }
    }

    private func applyList(_ markerFormat: NSTextList.MarkerFormat, to text: NSMutableAttributedString, range: NSRange) {
        let clampedRange = safeRange(range, in: text)
        let fullRange = (text.string as NSString).lineRange(for: clampedRange)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.textLists = [NSTextList(markerFormat: markerFormat, options: [], startingItemNumber: 1)]
        paragraphStyle.headIndent = 28
        paragraphStyle.firstLineHeadIndent = 0
        paragraphStyle.paragraphSpacing = 4
        text.addAttribute(.paragraphStyle, value: paragraphStyle, range: safeRange(fullRange, in: text))
    }

    private func safeRange(_ range: NSRange, in text: NSAttributedString) -> NSRange {
        let location = min(max(0, range.location), text.length)
        let maxLength = max(0, text.length - location)
        return NSRange(location: location, length: min(range.length, maxLength))
    }

    private func editForSave(from document: GoogleDocsDocument) throws -> GoogleDocsTextEdit {
        if editedText == document.plainText {
            guard let firstSegment = document.textSegments.first else {
                throw GoogleDocsServiceError.unsupportedEditRange
            }

            return GoogleDocsTextEdit(
                tabID: firstSegment.tabID,
                googleStartIndex: firstSegment.googleStartIndex,
                googleEndIndex: firstSegment.googleStartIndex,
                replacementText: ""
            )
        }

        return try indexMapper.edit(from: document.plainText, to: editedText, segments: document.textSegments)
    }

    private func clampedNonEmptyRange(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    private func remoteFormattingRequest(for command: GoogleDocsToolbarFormattingCommand, googleRange: GoogleDocsTextEdit) -> GoogleDocsFormattingRequest {
        switch command {
        case .bold:
            return .textStyle(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex, bold: true)
        case .italic:
            return .textStyle(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex, italic: true)
        case .underline:
            return .textStyle(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex, underline: true)
        case .strikethrough:
            return .textStyle(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex, strikethrough: true)
        case .normalText:
            return .normalText(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex)
        case .heading(let level):
            return .heading(level: level, tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex)
        case .bulletList:
            return .bulletList(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex)
        case .numberedList:
            return .numberedList(tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex)
        case .link(let url):
            return .link(url: url, tabID: googleRange.tabID, startIndex: googleRange.googleStartIndex, endIndex: googleRange.googleEndIndex)
        }
    }

    private func localFormattingRequest(for command: GoogleDocsToolbarFormattingCommand, range: NSRange) -> GoogleDocsLocalFormattingRequest {
        switch command {
        case .bold:
            return .textStyle(range: range, bold: true)
        case .italic:
            return .textStyle(range: range, italic: true)
        case .underline:
            return .textStyle(range: range, underline: true)
        case .strikethrough:
            return .textStyle(range: range, strikethrough: true)
        case .normalText:
            return .normalText(range: range)
        case .heading(let level):
            return .heading(level: level, range: range)
        case .bulletList:
            return .bulletList(range: range)
        case .numberedList:
            return .numberedList(range: range)
        case .link(let url):
            return .link(url: url, range: range)
        }
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
