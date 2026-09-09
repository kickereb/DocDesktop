import AppKit
import SwiftUI

struct MacAttributedTextView: NSViewRepresentable {
    let documentID: String
    let text: NSAttributedString
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

        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.importsGraphics = true
        textView.isRichText = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.selectedTextAttributes = [
            .backgroundColor: NSColor.selectedTextBackgroundColor,
            .foregroundColor: NSColor.white
        ]
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        textView.font = .systemFont(ofSize: 15)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: .greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable

        if context.coordinator.loadedDocumentID != documentID {
            textView.textStorage?.setAttributedString(text)
            context.coordinator.loadedDocumentID = documentID
            context.coordinator.currentText = text.string
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var loadedDocumentID: String?
        var currentText = ""
        private let onTextChange: (String) -> Void
        private let onSelectionChange: (NSRange) -> Void

        init(onTextChange: @escaping (String) -> Void, onSelectionChange: @escaping (NSRange) -> Void) {
            self.onTextChange = onTextChange
            self.onSelectionChange = onSelectionChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            currentText = textView.string
            onTextChange(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            onSelectionChange(textView.selectedRange())
        }
    }
}
