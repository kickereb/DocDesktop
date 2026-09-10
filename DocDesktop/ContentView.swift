import AppKit
import SwiftUI

struct ContentView: View {
    @State private var authManager = GoogleAuthManager.shared
    @State private var pickerViewModel = DocumentPickerViewModel()
    @State private var contentViewModel = DocumentContentViewModel()
    @State private var placeholderText = "Stage 5 document editor\n\nSelect one Google Doc from My Drive, Shared with me, a Shared Drive, or a pasted Google Docs URL."
    @State private var isHovering = false
    @State private var showsSetup = false
    @State private var showsDocumentPicker = false
    @State private var editorSelection = NSRange(location: 0, length: 0)

    var body: some View {
        VStack(spacing: 0) {
            header
                .opacity(isHovering ? 1 : 0)

            Divider()
                .opacity(isHovering ? 1 : 0)

            if !AppDevelopmentMode.localMarkdownEngineOnly,
               contentViewModel.document != nil,
               pickerViewModel.selectedDocument?.canEdit == true {
                formattingToolbar
                    .opacity(isHovering ? 1 : 0)

                Divider()
                    .opacity(isHovering ? 1 : 0)
            }

            ZStack(alignment: .top) {
                documentSurface
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showsSetup || !authManager.setupStatus.isReady {
                    setupPanel
                        .padding(14)
                } else if showsDocumentPicker {
                    DocumentPickerView(viewModel: pickerViewModel) {
                        showsDocumentPicker = false
                        loadSelectedDocument()
                    }
                    .padding(14)
                } else if !authManager.isSignedIn && contentViewModel.document == nil {
                    signedOutPanel
                        .padding(14)
                }
            }

            Divider()
                .opacity(isHovering ? 1 : 0)

            footer
                .opacity(isHovering ? 1 : 0)
        }
        .frame(minWidth: 320, minHeight: 360)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(isHovering ? 0.32 : 0.18), lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.16)) {
                isHovering = hovering
            }
        }
        .task {
            await authManager.restoreSession()
            await contentViewModel.load(selectedDocument: pickerViewModel.selectedDocument)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showDocumentPicker)) { _ in
            showsSetup = false
            showsDocumentPicker = true
            Task { await pickerViewModel.refresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .saveDocumentNow)) { _ in
            Task { await contentViewModel.saveNow() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hideDocumentOverlay)) { _ in
            NSApp.sendAction(#selector(AppDelegate.hideDocumentWindow), to: nil, from: nil)
        }
        .onReceive(NotificationCenter.default.publisher(for: .newLocalMarkdownFile)) { _ in
            startLocalMarkdownFile()
        }
    }

    @ViewBuilder
    private var documentSurface: some View {
        if let document = contentViewModel.document {
            if AppDevelopmentMode.localMarkdownEngineOnly {
                VStack(spacing: 0) {
                    MarkdownEditorView(
                        documentID: "\(document.documentID)-\(contentViewModel.editorVersion)",
                        text: contentViewModel.editedText,
                        isEditable: editorIsEditable,
                        onTextChange: { newText in
                            contentViewModel.updateEditedText(newText)
                        },
                        onSelectionChange: { range in
                            editorSelection = range
                        }
                    )

                    MarkdownImagePreviewStrip(markdown: contentViewModel.editedText)
                }
            } else {
                MacAttributedTextView(
                    documentID: "\(document.documentID)-\(document.revisionID ?? "")-\(contentViewModel.editorVersion)",
                    text: contentViewModel.editorAttributedText,
                    isEditable: editorIsEditable,
                    onTextChange: { newText in
                        contentViewModel.updateEditedText(newText)
                    },
                    onSelectionChange: { range in
                        editorSelection = range
                    }
                )
            }
        } else if contentViewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacTextView(text: $placeholderText)
        }
    }

    private var formattingToolbar: some View {
        HStack(spacing: 10) {
            formattingButton(systemName: "bold", isActive: selectionHasTrait(.boldFontMask)) {
                contentViewModel.applyFormatting(.bold, selection: editorSelection)
            }

            formattingButton(systemName: "italic", isActive: selectionHasTrait(.italicFontMask)) {
                contentViewModel.applyFormatting(.italic, selection: editorSelection)
            }

            formattingButton(systemName: "underline", isActive: selectionHasAttribute(.underlineStyle)) {
                contentViewModel.applyFormatting(.underline, selection: editorSelection)
            }

            formattingButton(systemName: "strikethrough", isActive: selectionHasAttribute(.strikethroughStyle)) {
                contentViewModel.applyFormatting(.strikethrough, selection: editorSelection)
            }

            Menu {
                Button("Normal") { contentViewModel.applyFormatting(.normalText, selection: editorSelection) }
                Button("Heading 1") { contentViewModel.applyFormatting(.heading(1), selection: editorSelection) }
                Button("Heading 2") { contentViewModel.applyFormatting(.heading(2), selection: editorSelection) }
                Button("Heading 3") { contentViewModel.applyFormatting(.heading(3), selection: editorSelection) }
            } label: {
                Image(systemName: "textformat.size")
            }
            .menuStyle(.borderlessButton)
            .help("Heading Style")

            formattingButton(systemName: "list.bullet", isActive: false) {
                contentViewModel.applyFormatting(.bulletList, selection: editorSelection)
            }

            formattingButton(systemName: "list.number", isActive: false) {
                contentViewModel.applyFormatting(.numberedList, selection: editorSelection)
            }

            formattingButton(systemName: "link", isActive: selectionHasAttribute(.link)) {
                applyLinkFromPrompt()
            }

            Spacer(minLength: 0)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(.ultraThinMaterial)
    }

    private func formattingButton(systemName: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .help(systemName)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(contentViewModel.document?.title ?? pickerViewModel.selectedDocument?.title ?? "No document selected")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            authButton

            if AppDevelopmentMode.localMarkdownEngineOnly {
                Button {
                    startLocalMarkdownFile()
                } label: {
                    Image(systemName: "doc.badge.plus")
                }
                .help("New Local File")
            }

            Button {
                showsDocumentPicker.toggle()
                if showsDocumentPicker {
                    showsSetup = false
                    Task { await pickerViewModel.refresh() }
                }
            } label: {
                Image(systemName: "folder")
            }
            .disabled(!authManager.isSignedIn)
            .help("Change Document")

            Button {
                showsSetup.toggle()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Setup")

            Button {
                Task { await contentViewModel.saveNow() }
            } label: {
                Image(systemName: "square.and.arrow.down")
            }
            .disabled(!contentViewModel.hasUnsavedChanges || contentViewModel.isSaving || !editorIsEditable)
            .help("Save")

            Button {
                refreshSelectedDocument()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!authManager.isSignedIn || contentViewModel.isLoading || contentViewModel.isSaving)
            .help("Refresh")

            Button {
                openSelectedDocument()
            } label: {
                Image(systemName: "safari")
            }
            .disabled(pickerViewModel.selectedDocument?.webViewLink == nil)
            .help("Open in Google Docs")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(.ultraThinMaterial)
    }

    private var authButton: some View {
        Button {
            if authManager.isSignedIn {
                signOut()
            } else {
                signIn()
            }
        } label: {
            Image(systemName: authManager.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle.badge.plus")
        }
        .help(authManager.isSignedIn ? "Sign Out" : "Sign In")
    }

    private var setupPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google setup")
                .font(.headline)

            Text(authManager.setupStatus.missingSetupMessage ?? "Google OAuth setup is ready.")
                .foregroundStyle(authManager.setupStatus.isReady ? Color.secondary : Color.red)

            Text("URL scheme")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(authManager.setupStatus.callbackScheme)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)

            Text("Redirect URI")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(authManager.setupStatus.redirectURI)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .font(.caption)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var signedOutPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start")
                .font(.headline)

            Text("Use a local Markdown note now, or sign in to select a Google Doc.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    startLocalMarkdownFile()
                } label: {
                    Label("New Local File", systemImage: "doc.badge.plus")
                }

                Button {
                    signIn()
                } label: {
                    Label("Sign In", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(!authManager.setupStatus.isReady)
            }
        }
        .buttonStyle(.borderless)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(errorText == nil ? Color.secondary : Color.red)
                    .lineLimit(1)

                if let errorText {
                    Text(errorText)
                        .font(.caption2)
                        .foregroundStyle(Color.red)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            Text(pickerViewModel.selectedDocument?.canEdit == false ? "Read only" : "100%")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: errorText == nil ? 32 : 56)
        .background(.ultraThinMaterial)
    }

    private var statusText: String {
        if contentViewModel.isLoading || contentViewModel.isSaving || contentViewModel.hasUnsavedChanges {
            return contentViewModel.statusMessage
        }

        if let selectedDocument = pickerViewModel.selectedDocument {
            return contentViewModel.statusMessage == "Loaded" || contentViewModel.statusMessage == "Loaded read-only" || contentViewModel.statusMessage == "Saved"
                ? "Selected: \(selectedDocument.title)"
                : contentViewModel.statusMessage
        }

        if contentViewModel.document != nil {
            return contentViewModel.statusMessage
        }

        if pickerViewModel.isLoading {
            return pickerViewModel.statusMessage
        }

        return authManager.statusText
    }

    private var errorText: String? {
        contentViewModel.errorMessage ?? pickerViewModel.errorMessage ?? authManager.errorMessage
    }

    private func loadSelectedDocument() {
        Task {
            await contentViewModel.load(selectedDocument: pickerViewModel.selectedDocument)
        }
    }

    private func startLocalMarkdownFile() {
        pickerViewModel.clearSelection()
        showsSetup = false
        showsDocumentPicker = false
        contentViewModel.loadLocalMarkdownScratch()
        NotificationCenter.default.post(name: .focusDocumentEditor, object: nil)
    }

    private func signIn() {
        Task {
            await authManager.signIn(presentationWindow: NSApp.windows.first { $0 is WidgetWindow })
            if authManager.isSignedIn {
                showsDocumentPicker = true
                await pickerViewModel.refresh()
            }
        }
    }

    private func signOut() {
        authManager.signOut()
        pickerViewModel.clearSelection()
        showsDocumentPicker = false
        showsSetup = false
        if AppDevelopmentMode.localMarkdownEngineOnly {
            contentViewModel.loadLocalMarkdownScratch()
        } else {
            contentViewModel = DocumentContentViewModel()
        }
    }

    private func refreshSelectedDocument() {
        Task {
            await contentViewModel.refresh()
        }
    }

    private func openSelectedDocument() {
        guard let url = pickerViewModel.selectedDocument?.webViewLink else { return }
        NSWorkspace.shared.open(url)
    }

    private func applyLinkFromPrompt() {
        let alert = NSAlert()
        alert.messageText = "Link URL"
        alert.informativeText = "Enter a URL for the selected text."
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "https://example.com"
        alert.accessoryView = field

        guard alert.runModal() == .alertFirstButtonReturn,
              let url = URL(string: field.stringValue),
              !field.stringValue.isEmpty else { return }

        contentViewModel.applyFormatting(.link(url), selection: editorSelection)
    }

    private func selectionHasTrait(_ trait: NSFontTraitMask) -> Bool {
        let text = contentViewModel.editorAttributedText
        let index = attributeIndex(in: text)
        guard index < text.length,
              let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont else {
            return false
        }

        return font.fontDescriptor.symbolicTraits.contains(trait == .boldFontMask ? .bold : .italic)
    }

    private func selectionHasAttribute(_ key: NSAttributedString.Key) -> Bool {
        let text = contentViewModel.editorAttributedText
        let index = attributeIndex(in: text)
        guard index < text.length else { return false }
        return text.attribute(key, at: index, effectiveRange: nil) != nil
    }

    private func attributeIndex(in text: NSAttributedString) -> Int {
        guard text.length > 0 else { return 0 }
        return min(max(0, editorSelection.location), text.length - 1)
    }

    private var editorIsEditable: Bool {
        AppDevelopmentMode.localMarkdownEngineOnly || pickerViewModel.selectedDocument?.canEdit == true
    }
}

#Preview {
    ContentView()
        .frame(width: 420, height: 540)
}

private struct MarkdownImagePreviewStrip: View {
    private let images: [MarkdownImageReference]

    init(markdown: String) {
        images = MarkdownImageReference.extract(from: markdown)
    }

    var body: some View {
        if !images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(images) { image in
                        MarkdownImagePreview(reference: image)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .frame(height: 122)
            .background(.ultraThinMaterial)
        }
    }
}

private struct MarkdownImagePreview: View {
    let reference: MarkdownImageReference

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageContent
                .frame(width: 132, height: 82)
                .background(Color.black.opacity(0.28))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(reference.altText.isEmpty ? reference.displayName : reference.altText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 132, alignment: .leading)
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let image = reference.localImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
        } else if let url = reference.remoteURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                case .failure:
                    unavailableImage
                case .empty:
                    ProgressView()
                        .controlSize(.small)
                @unknown default:
                    unavailableImage
                }
            }
        } else {
            unavailableImage
        }
    }

    private var unavailableImage: some View {
        Image(systemName: "photo")
            .font(.title2)
            .foregroundStyle(.secondary)
    }
}

private struct MarkdownImageReference: Identifiable {
    let altText: String
    let source: String

    var id: String {
        source
    }

    var displayName: String {
        if let url = remoteURL {
            return url.lastPathComponent.isEmpty ? url.host() ?? source : url.lastPathComponent
        }
        return localURL?.lastPathComponent ?? source
    }

    var remoteURL: URL? {
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    var localURL: URL? {
        if source.hasPrefix("file://") {
            return URL(string: source)
        }
        if source.hasPrefix("/") {
            return URL(fileURLWithPath: source)
        }
        if source.hasPrefix("~/") {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            let path = home + String(source.dropFirst())
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    var localImage: NSImage? {
        guard let localURL else { return nil }
        return NSImage(contentsOf: localURL)
    }

    static func extract(from markdown: String) -> [MarkdownImageReference] {
        let nsText = markdown as NSString
        guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]\n]*)\]\(([^)\n]+)\)"#) else {
            return []
        }

        return regex.matches(in: markdown, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges == 3 else { return nil }
            let altText = nsText.substring(with: match.range(at: 1))
            let source = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !source.isEmpty else { return nil }
            return MarkdownImageReference(altText: altText, source: source)
        }
    }
}
