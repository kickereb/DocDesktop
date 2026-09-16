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
        context.coordinator.applyFullStyle(to: textView)
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

        let documentChanged = context.coordinator.loadedDocumentID != documentID
        if !documentChanged && context.coordinator.isEditorEcho(text) {
            context.coordinator.debugLog(event: "updateNSViewSkippedEcho", textView: textView, editedRange: nil, origin: "SwiftUI")
            return
        }

        if documentChanged || context.coordinator.currentText != text {
            context.coordinator.debugLog(event: "updateNSViewApplyExternal", textView: textView, editedRange: nil, origin: "externalModel")
            context.coordinator.isApplyingProgrammaticText = true
            let selectedRange = textView.selectedRange()
            let visibleOrigin = context.coordinator.visibleOrigin(for: textView)
            textView.string = text
            context.coordinator.applyFullStyle(to: textView)
            context.coordinator.setSelectedRangeIfNeeded(clamp(selectedRange, in: textView.string), for: textView)
            context.coordinator.restoreVisibleOriginIfNeeded(visibleOrigin, for: textView)
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
        private var lastEditorEmittedText: String?
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
            lastEditorEmittedText = textView.string
            let selectedRange = textView.selectedRange()
            let visibleOrigin = visibleOrigin(for: textView)
            let editedRange = textView.textStorage?.editedRange ?? selectedRange
            debugLog(event: "textDidChange", textView: textView, editedRange: editedRange, origin: "user")
            applyStyle(to: textView, affectedBy: editedRange)
            setSelectedRangeIfNeeded(selectedRange, for: textView)
            restoreVisibleOriginIfNeeded(visibleOrigin, for: textView, delayedCheck: true)
            onTextChange(textView.string)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            debugLog(event: "selectionChange", textView: textView, editedRange: nil, origin: "user")
            onSelectionChange(textView.selectedRange())
        }

        func isEditorEcho(_ text: String) -> Bool {
            text == currentText || text == lastEditorEmittedText
        }

        func applyFullStyle(to textView: NSTextView) {
            guard let textStorage = textView.textStorage else { return }
            debugLog(event: "styleFullStart", textView: textView, editedRange: NSRange(location: 0, length: textStorage.length), origin: "styling")
            styler.apply(to: textStorage)
            debugLog(event: "styleFullEnd", textView: textView, editedRange: NSRange(location: 0, length: textStorage.length), origin: "styling")
        }

        func applyStyle(to textView: NSTextView, affectedBy editedRange: NSRange) {
            guard let textStorage = textView.textStorage else { return }
            debugLog(event: "styleDirtyStart", textView: textView, editedRange: editedRange, origin: "styling")
            let dirtyRange = styler.apply(to: textStorage, affectedBy: editedRange)
            debugLog(event: "styleDirtyEnd", textView: textView, editedRange: dirtyRange, origin: "styling")
        }

        func visibleOrigin(for textView: NSTextView) -> NSPoint? {
            textView.enclosingScrollView?.contentView.bounds.origin
        }

        func setSelectedRangeIfNeeded(_ range: NSRange, for textView: NSTextView) {
            let clampedRange = clamp(range, in: textView.string)
            guard textView.selectedRange() != clampedRange else {
                debugLog(event: "selectionRestoreSkipped", textView: textView, editedRange: clampedRange, origin: "selection")
                return
            }
            textView.setSelectedRange(clampedRange)
            debugLog(event: "selectionRestored", textView: textView, editedRange: clampedRange, origin: "selection")
        }

        private func clamp(_ range: NSRange, in text: String) -> NSRange {
            let length = (text as NSString).length
            let location = min(max(0, range.location), length)
            let maxLength = max(0, length - location)
            return NSRange(location: location, length: min(range.length, maxLength))
        }

        func restoreVisibleOriginIfNeeded(_ origin: NSPoint?, for textView: NSTextView, delayedCheck: Bool = false) {
            guard let origin,
                  let scrollView = textView.enclosingScrollView else {
                return
            }

            let clipView = scrollView.contentView
            restore(origin, in: clipView, scrollView: scrollView, textView: textView)

            if delayedCheck {
                DispatchQueue.main.async { [weak textView, weak scrollView] in
                    guard let textView,
                          let scrollView else {
                        return
                    }
                    self.restore(origin, in: scrollView.contentView, scrollView: scrollView, textView: textView)
                }
            }
        }

        private func restore(_ origin: NSPoint, in clipView: NSClipView, scrollView: NSScrollView, textView: NSTextView) {
            let currentOrigin = clipView.bounds.origin
            guard abs(currentOrigin.x - origin.x) > 0.5 || abs(currentOrigin.y - origin.y) > 0.5 else {
                debugLog(event: "scrollRestoreSkipped", textView: textView, editedRange: nil, origin: "scroll")
                return
            }

            guard caretWouldBeVisible(in: textView, clipView: clipView, origin: origin) else {
                debugLog(event: "scrollRestoreSkippedCaret", textView: textView, editedRange: nil, origin: "scroll")
                return
            }

            clipView.setBoundsOrigin(origin)
            scrollView.reflectScrolledClipView(clipView)
            debugLog(event: "scrollRestored", textView: textView, editedRange: nil, origin: "scroll")
        }

        private func caretWouldBeVisible(in textView: NSTextView, clipView: NSClipView, origin: NSPoint) -> Bool {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return true
            }

            let selectedRange = textView.selectedRange()
            let glyphRange = layoutManager.glyphRange(
                forCharacterRange: NSRange(location: selectedRange.location, length: 0),
                actualCharacterRange: nil
            )
            let caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let expectedVisibleRect = NSRect(origin: origin, size: clipView.bounds.size)
                .insetBy(dx: 0, dy: -24)
            return expectedVisibleRect.intersects(caretRect)
        }

        func debugLog(event: String, textView: NSTextView, editedRange: NSRange?, origin: String) {
            #if DEBUG
            let selectedRange = textView.selectedRange()
            let visibleY = textView.enclosingScrollView?.contentView.bounds.origin.y ?? 0
            let editedText = editedRange.map { "{\($0.location),\($0.length)}" } ?? "nil"
            print("[EditorDebug] event=\(event) editedRange=\(editedText) selection={\(selectedRange.location),\(selectedRange.length)} visibleY=\(String(format: "%.1f", visibleY)) length=\((textView.string as NSString).length) origin=\(origin)")
            #endif
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

        if isCommandIndentKey(event),
           let replacement = editingEngine.replacementForTab(in: string, selectedRange: selectedRange(), outdent: false) {
            applyReplacement(replacement)
            return
        }

        if isCommandOutdentKey(event),
           let replacement = editingEngine.replacementForTab(in: string, selectedRange: selectedRange(), outdent: true) {
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

    override func paste(_ sender: Any?) {
        if let markdown = MarkdownImagePasteboardWriter.markdownImageReference(from: .general) {
            let range = selectedRange()
            let replacement: MarkdownEditingEngine.TextReplacement = (
                range: range,
                text: markdown,
                selectedRange: NSRange(location: range.location + (markdown as NSString).length, length: 0)
            )
            applyReplacement(replacement)
            return
        }

        super.paste(sender)
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

    private func isCommandIndentKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "]"
    }

    private func isCommandOutdentKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "["
    }

    private func checkboxReplacement(for event: NSEvent) -> MarkdownEditingEngine.TextReplacement? {
        let point = convert(event.locationInWindow, from: nil)
        let insertionIndex = characterIndexForInsertion(at: point)
        guard let lineLocation = lineLocation(at: insertionIndex) else {
            return nil
        }
        return editingEngine.replacementForCheckboxToggle(in: string, location: lineLocation)
    }

    private func applyReplacement(_ replacement: MarkdownEditingEngine.TextReplacement) {
        guard shouldChangeText(in: replacement.range, replacementString: replacement.text) else { return }
        let visibleOrigin = enclosingScrollView?.contentView.bounds.origin
        textStorage?.replaceCharacters(in: replacement.range, with: replacement.text)
        didChangeText()
        setSelectedRangeIfNeeded(replacement.selectedRange)
        restoreVisibleOriginIfNeeded(visibleOrigin)
    }

    private func setSelectedRangeIfNeeded(_ range: NSRange) {
        let clampedRange = clamp(range)
        guard selectedRange() != clampedRange else { return }
        setSelectedRange(clampedRange)
    }

    private func restoreVisibleOriginIfNeeded(_ origin: NSPoint?) {
        guard let origin,
              let scrollView = enclosingScrollView else {
            return
        }

        let clipView = scrollView.contentView
        let currentOrigin = clipView.bounds.origin
        guard abs(currentOrigin.x - origin.x) > 0.5 || abs(currentOrigin.y - origin.y) > 0.5 else {
            return
        }

        guard caretWouldBeVisible(at: origin, in: clipView) else {
            return
        }

        clipView.setBoundsOrigin(origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    private func caretWouldBeVisible(at origin: NSPoint, in clipView: NSClipView) -> Bool {
        guard let layoutManager,
              let textContainer else {
            return true
        }

        let selectedRange = selectedRange()
        let glyphRange = layoutManager.glyphRange(
            forCharacterRange: NSRange(location: selectedRange.location, length: 0),
            actualCharacterRange: nil
        )
        let caretRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let expectedVisibleRect = NSRect(origin: origin, size: clipView.bounds.size)
            .insetBy(dx: 0, dy: -24)
        return expectedVisibleRect.intersects(caretRect)
    }

    private func clamp(_ range: NSRange) -> NSRange {
        let length = (string as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = max(0, length - location)
        return NSRange(location: location, length: min(range.length, maxLength))
    }

    private func lineLocation(at location: Int) -> Int? {
        let nsText = string as NSString
        guard nsText.length > 0 else { return nil }
        let safeLocation = min(max(0, location), max(0, nsText.length - 1))
        return nsText.lineRange(for: NSRange(location: safeLocation, length: 0)).location
    }
}

private enum MarkdownImagePasteboardWriter {
    static func markdownImageReference(from pasteboard: NSPasteboard) -> String? {
        if let fileURL = imageFileURL(from: pasteboard) {
            return markdownReference(for: fileURL)
        }

        guard let image = NSImage(pasteboard: pasteboard),
              let savedURL = save(image: image) else {
            return nil
        }

        return markdownReference(for: savedURL)
    }

    private static func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        guard let fileURLString = pasteboard.string(forType: .fileURL),
              let url = URL(string: fileURLString),
              NSImage(contentsOf: url) != nil else {
            return nil
        }
        return url
    }

    private static func save(image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        do {
            let directory = try imageDirectory()
            let fileURL = directory.appendingPathComponent("pasted-\(UUID().uuidString).png")
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func imageDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent("DocDesktop/LocalImages", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func markdownReference(for url: URL) -> String {
        let altText = url.deletingPathExtension().lastPathComponent
        return "\n![\(altText)](\(url.absoluteString))\n"
    }
}
