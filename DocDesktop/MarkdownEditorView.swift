import AppKit
import SwiftUI

struct MarkdownEditorView: NSViewRepresentable {
    let documentID: String
    let text: String
    let isEditable: Bool
    let onTextChange: (String) -> Void
    let onSelectionChange: (NSRange) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChange: onTextChange, onSelectionChange: onSelectionChange)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        let textView = MarkdownNSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 24, height: 22)
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.white
        ]
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .white
        textView.string = text
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)
        context.coordinator.applyStyle(to: textView)
        context.coordinator.loadedDocumentID = documentID
        context.coordinator.currentText = text
        context.coordinator.focusObserver = NotificationCenter.default.addObserver(
            forName: .focusDocumentEditor,
            object: nil,
            queue: .main
        ) { [weak textView] _ in
            guard let textView else { return }
            textView.window?.makeFirstResponder(textView)
        }

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable

        if context.coordinator.loadedDocumentID != documentID || context.coordinator.currentText != text {
            context.coordinator.isApplyingProgrammaticText = true
            let selectedRange = textView.selectedRange()
            textView.string = text
            context.coordinator.applyStyle(to: textView)
            textView.setSelectedRange(clamp(selectedRange, in: textView.string))
            context.coordinator.isApplyingProgrammaticText = false
            context.coordinator.loadedDocumentID = documentID
            context.coordinator.currentText = text
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        if let focusObserver = coordinator.focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
        }
    }

    private func clamp(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(range.length, maxLength))
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var loadedDocumentID: String?
        var currentText = ""
        var isApplyingProgrammaticText = false
        var focusObserver: NSObjectProtocol?
        private let styler = MarkdownStyler()
        private let onTextChange: (String) -> Void
        private let onSelectionChange: (NSRange) -> Void

        init(onTextChange: @escaping (String) -> Void, onSelectionChange: @escaping (NSRange) -> Void) {
            self.onTextChange = onTextChange
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammaticText,
                  let textView = notification.object as? NSTextView else { return }

            currentText = textView.string
            let selectedRange = textView.selectedRange()
            applyStyle(to: textView)
            textView.setSelectedRange(selectedRange)
            onTextChange(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSelectionChange(textView.selectedRange())
        }

        func applyStyle(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            styler.apply(to: textStorage)
        }
    }
}

private final class MarkdownNSTextView: NSTextView {
    private let editingEngine = MarkdownEditingEngine()

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        activateWindowForEditing()
        if let replacement = checkboxReplacement(for: event) {
            applyReplacement(replacement)
            return
        }
        super.mouseDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        activateWindowForEditing()
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if isReturnKey(event),
           let replacement = editingEngine.replacementForReturn(in: string, selectedRange: selectedRange()) {
            applyReplacement(replacement)
            return
        }

        if isTabKey(event),
           let replacement = editingEngine.replacementForTab(
            in: string,
            selectedRange: selectedRange(),
            outdent: event.modifierFlags.contains(.shift)
           ) {
            applyReplacement(replacement)
            return
        }

        super.keyDown(with: event)
    }

    private func activateWindowForEditing() {
        guard let window else { return }
        window.makeKey()
        window.makeFirstResponder(self)
    }

    private func isReturnKey(_ event: NSEvent) -> Bool {
        event.charactersIgnoringModifiers == "\r" || event.charactersIgnoringModifiers == "\n"
    }

    private func isTabKey(_ event: NSEvent) -> Bool {
        event.keyCode == 48
    }

    private func checkboxReplacement(for event: NSEvent) -> MarkdownEditingEngine.TextReplacement? {
        let point = convert(event.locationInWindow, from: nil)
        let insertionIndex = characterIndexForInsertion(at: point)
        return editingEngine.replacementForCheckboxToggle(in: string, location: insertionIndex)
    }

    private func applyReplacement(_ replacement: MarkdownEditingEngine.TextReplacement) {
        guard shouldChangeText(in: replacement.range, replacementString: replacement.text) else { return }
        textStorage?.replaceCharacters(in: replacement.range, with: replacement.text)
        didChangeText()
        setSelectedRange(replacement.selectedRange)
    }
}
