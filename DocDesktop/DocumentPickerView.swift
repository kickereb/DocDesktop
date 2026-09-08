import SwiftUI

struct DocumentPickerView: View {
    @Bindable var viewModel: DocumentPickerViewModel
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchSection
            pastedURLSection
            documentSections
            statusSection
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Choose document")
                .font(.headline)

            Spacer(minLength: 8)

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(viewModel.isLoading)
            .help("Refresh")

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("Close")
        }
        .buttonStyle(.borderless)
    }

    private var searchSection: some View {
        TextField("Search files", text: $viewModel.searchText)
            .textFieldStyle(.roundedBorder)
    }

    private var pastedURLSection: some View {
        HStack(spacing: 8) {
            TextField("Paste Google Docs URL", text: $viewModel.pastedURL)
                .textFieldStyle(.roundedBorder)

            Button {
                Task { await viewModel.verifyPastedURL() }
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .disabled(viewModel.pastedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            .help("Use URL")
        }
    }

    private var documentSections: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                documentSection(title: "My Drive", files: viewModel.filteredMyDriveDocuments)
                documentSection(title: "Shared with me", files: viewModel.filteredSharedWithMeDocuments)

                ForEach(viewModel.sharedDrives) { sharedDrive in
                    documentSection(
                        title: sharedDrive.name,
                        files: viewModel.filteredSharedDriveDocuments(for: sharedDrive)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 320)
    }

    private func documentSection(title: String, files: [DriveFile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            if files.isEmpty {
                Text(viewModel.isLoading ? "Loading" : "No Google Docs found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(files) { file in
                    Button {
                        viewModel.select(file)
                        onClose()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .lineLimit(1)
                                Text(file.accessLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 8)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(viewModel.errorMessage == nil ? Color.secondary : Color.red)

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption2)
                    .foregroundStyle(Color.red)
                    .lineLimit(2)
            }
        }
    }
}
