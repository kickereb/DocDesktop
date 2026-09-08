import SwiftUI

struct ContentView: View {
    @State private var authManager = GoogleAuthManager.shared
    @State private var pickerViewModel = DocumentPickerViewModel()
    @State private var contentViewModel = DocumentContentViewModel()
    @State private var placeholderText = "Stage 5 document editor\n\nSelect one Google Doc from My Drive, Shared with me, a Shared Drive, or a pasted Google Docs URL."
    @State private var isHovering = false
    @State private var showsSetup = false
    @State private var showsDocumentPicker = false

    var body: some View {
        VStack(spacing: 0) {
            header
                .opacity(isHovering ? 1 : 0)

            Divider()
                .opacity(isHovering ? 1 : 0)

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
    }

    @ViewBuilder
    private var documentSurface: some View {
        if let document = contentViewModel.document {
            MacAttributedTextView(
                documentID: "\(document.documentID)-\(document.revisionID ?? "")",
                text: document.attributedText,
                isEditable: pickerViewModel.selectedDocument?.canEdit == true,
                onTextChange: { newText in
                    contentViewModel.updateEditedText(newText)
                }
            )
        } else if contentViewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            MacTextView(text: $placeholderText)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(pickerViewModel.selectedDocument?.title ?? "No document selected")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            authButton

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
            .disabled(!contentViewModel.hasUnsavedChanges || contentViewModel.isSaving || pickerViewModel.selectedDocument?.canEdit != true)
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
                authManager.signOut()
                pickerViewModel.clearSelection()
                contentViewModel = DocumentContentViewModel()
                showsDocumentPicker = false
            } else {
                Task {
                    await authManager.signIn(presentationWindow: NSApp.windows.first { $0 is WidgetWindow })
                    if authManager.isSignedIn {
                        showsDocumentPicker = true
                        await pickerViewModel.refresh()
                    }
                }
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

    private func refreshSelectedDocument() {
        Task {
            await contentViewModel.refresh()
        }
    }

    private func openSelectedDocument() {
        guard let url = pickerViewModel.selectedDocument?.webViewLink else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    ContentView()
        .frame(width: 420, height: 540)
}
