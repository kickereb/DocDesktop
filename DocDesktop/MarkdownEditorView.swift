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
            let editedRange = (textView as? MarkdownNSTextView)?.consumePendingStylingRange()
                ?? textView.textStorage?.editedRange
                ?? selectedRange
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
    private struct CheckboxRenderInfo {
        let lineRange: NSRange
        let markerRange: NSRange
        let isChecked: Bool
    }

    private struct ImageRenderInfo {
        let lineRange: NSRange
        let source: String
        let altText: String
    }

    private let editingEngine = MarkdownEditingEngine()
    private let inlineImageHeight: CGFloat = 170
    private var pendingStylingRange: NSRange?
    private var hoverTrackingArea: NSTrackingArea?
    private var hoveredCheckboxRange: NSRange?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        if let replacementString {
            pendingStylingRange = NSRange(
                location: affectedCharRange.location,
                length: max(affectedCharRange.length, (replacementString as NSString).length)
            )
        }

        return super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
    }

    override func updateTrackingAreas() {
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let nextRange = checkboxInfo(at: point)?.markerRange
        if hoveredCheckboxRange != nextRange {
            hoveredCheckboxRange = nextRange
            needsDisplay = true
        }
        super.mouseMoved(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        if hoveredCheckboxRange != nil {
            hoveredCheckboxRange = nil
            needsDisplay = true
        }
        super.mouseExited(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawMarkdownImages()
        drawMarkdownCheckboxes()
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
        if isPasteKey(event),
           let markdown = MarkdownImagePasteboardWriter.markdownImageReference(from: .general) {
            insertMarkdownImageReference(markdown)
            return
        }

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
            insertMarkdownImageReference(markdown)
            return
        }

        super.paste(sender)
    }

    override func readSelection(from pasteboard: NSPasteboard, type: NSPasteboard.PasteboardType) -> Bool {
        if let markdown = MarkdownImagePasteboardWriter.markdownImageReference(from: pasteboard) {
            insertMarkdownImageReference(markdown)
            return true
        }

        return super.readSelection(from: pasteboard, type: type)
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

    private func isPasteKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "v"
    }

    private func isCommandIndentKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "]"
    }

    private func isCommandOutdentKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "["
    }

    private func checkboxReplacement(for event: NSEvent) -> MarkdownEditingEngine.TextReplacement? {
        let point = convert(event.locationInWindow, from: nil)
        guard let checkbox = checkboxInfo(at: point) else {
            return nil
        }
        return editingEngine.replacementForCheckboxToggle(in: string, location: checkbox.lineRange.location)
    }

    private func insertMarkdownImageReference(_ markdown: String) {
        let range = selectedRange()
        let replacement: MarkdownEditingEngine.TextReplacement = (
            range: range,
            text: markdown,
            selectedRange: NSRange(location: range.location + (markdown as NSString).length, length: 0)
        )
        applyReplacement(replacement)
    }

    private func applyReplacement(_ replacement: MarkdownEditingEngine.TextReplacement) {
        guard shouldChangeText(in: replacement.range, replacementString: replacement.text) else { return }
        let visibleOrigin = enclosingScrollView?.contentView.bounds.origin
        pendingStylingRange = NSRange(
            location: replacement.range.location,
            length: max(replacement.range.length, (replacement.text as NSString).length)
        )
        textStorage?.replaceCharacters(in: replacement.range, with: replacement.text)
        didChangeText()
        setSelectedRangeIfNeeded(replacement.selectedRange)
        restoreVisibleOriginIfNeeded(visibleOrigin)
        needsDisplay = true
    }

    func consumePendingStylingRange() -> NSRange? {
        let range = pendingStylingRange
        pendingStylingRange = nil
        return range
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

    private func drawMarkdownImages() {
        guard let layoutManager,
              let textContainer,
              !string.isEmpty else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let nsText = string as NSString
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            if let imageInfo = imageInfo(in: lineRange),
               let image = image(for: imageInfo.source) {
                drawImage(image, for: imageInfo, layoutManager: layoutManager, textContainer: textContainer)
            }

            let next = NSMaxRange(lineRange)
            if next <= location { break }
            location = next
        }
    }

    private func drawImage(
        _ image: NSImage,
        for imageInfo: ImageRenderInfo,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) {
        let imageRect = imageRect(for: imageInfo, layoutManager: layoutManager, textContainer: textContainer)
        guard imageRect.width > 1, imageRect.height > 1 else { return }

        let backgroundPath = NSBezierPath(roundedRect: imageRect, xRadius: 9, yRadius: 9)
        NSColor.black.withAlphaComponent(0.22).setFill()
        backgroundPath.fill()

        NSGraphicsContext.saveGraphicsState()
        backgroundPath.addClip()
        image.draw(
            in: aspectFitRect(for: image.size, in: imageRect),
            from: NSRect(origin: .zero, size: image.size),
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.18).setStroke()
        backgroundPath.lineWidth = 1
        backgroundPath.stroke()
    }

    private func imageInfo(in lineRange: NSRange) -> ImageRenderInfo? {
        let nsText = string as NSString
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^\s*!\[([^\]\n]*)\]\(([^)]+)\)\s*$"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
              match.range(at: 2).location != NSNotFound else {
            let source = line.trimmingCharacters(in: .whitespaces)
            guard isLocalImagePath(source) else { return nil }
            return ImageRenderInfo(
                lineRange: lineRange,
                source: source,
                altText: URL(fileURLWithPath: source).deletingPathExtension().lastPathComponent
            )
        }

        let altText = match.range(at: 1).location == NSNotFound ? "" : nsLine.substring(with: match.range(at: 1))
        let source = nsLine.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
        return ImageRenderInfo(lineRange: lineRange, source: source, altText: altText)
    }

    private func isLocalImagePath(_ source: String) -> Bool {
        guard source.hasPrefix("/"),
              source.rangeOfCharacter(from: .newlines) == nil else {
            return false
        }

        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "heic", "tiff", "tif", "webp"]
        return imageExtensions.contains(URL(fileURLWithPath: source).pathExtension.lowercased())
    }

    private func image(for source: String) -> NSImage? {
        if let url = URL(string: source), url.isFileURL {
            return NSImage(contentsOf: url)
        }

        if source.hasPrefix("/") {
            return NSImage(contentsOf: URL(fileURLWithPath: source))
        }

        return nil
    }

    private func imageRect(
        for imageInfo: ImageRenderInfo,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: imageInfo.lineRange, actualCharacterRange: nil)
        let lineRect: NSRect
        if glyphRange.length > 0 {
            lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        } else {
            lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
                .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        }
        let availableWidth = max(120, bounds.width - textContainerInset.width * 2 - 16)
        let width = min(availableWidth, 520)
        let x = lineRect.isEmpty ? textContainerOrigin.x : lineRect.minX + 4
        let y = lineRect.isEmpty ? textContainerOrigin.y : lineRect.minY + 10
        return NSRect(x: x, y: y, width: width, height: inlineImageHeight).integral
    }

    private func aspectFitRect(for imageSize: NSSize, in boundingRect: NSRect) -> NSRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              boundingRect.width > 0,
              boundingRect.height > 0 else {
            return boundingRect
        }

        let imageAspect = imageSize.width / imageSize.height
        let targetAspect = boundingRect.width / boundingRect.height
        let fittedSize: NSSize

        if imageAspect > targetAspect {
            fittedSize = NSSize(width: boundingRect.width, height: boundingRect.width / imageAspect)
        } else {
            fittedSize = NSSize(width: boundingRect.height * imageAspect, height: boundingRect.height)
        }

        return NSRect(
            x: boundingRect.midX - fittedSize.width / 2,
            y: boundingRect.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        ).integral
    }

    private func drawMarkdownCheckboxes() {
        guard let layoutManager,
              let textContainer,
              !string.isEmpty else {
            return
        }

        layoutManager.ensureLayout(for: textContainer)
        let nsText = string as NSString
        var location = 0

        while location < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: location, length: 0))
            if let checkbox = checkboxInfo(in: lineRange) {
                drawCheckbox(checkbox, layoutManager: layoutManager, textContainer: textContainer)
            }

            let next = NSMaxRange(lineRange)
            if next <= location { break }
            location = next
        }
    }

    private func drawCheckbox(_ checkbox: CheckboxRenderInfo, layoutManager: NSLayoutManager, textContainer: NSTextContainer) {
        let boxRect = checkboxBoxRect(for: checkbox, layoutManager: layoutManager, textContainer: textContainer)
        let isHovered = hoveredCheckboxRange == checkbox.markerRange
        let borderColor = isHovered ? NSColor.systemRed : NSColor.white.withAlphaComponent(0.78)
        let fillColor = checkbox.isChecked ? NSColor.systemPink.withAlphaComponent(0.24) : NSColor.clear
        let path = NSBezierPath(roundedRect: boxRect, xRadius: 3.5, yRadius: 3.5)

        fillColor.setFill()
        path.fill()
        borderColor.setStroke()
        path.lineWidth = 1.8
        path.stroke()

        guard checkbox.isChecked else { return }

        let tickPath = NSBezierPath()
        tickPath.move(to: NSPoint(x: boxRect.minX + 4.0, y: boxRect.midY - 0.5))
        tickPath.line(to: NSPoint(x: boxRect.midX - 1.0, y: boxRect.maxY - 4.0))
        tickPath.line(to: NSPoint(x: boxRect.maxX - 3.5, y: boxRect.minY + 4.0))
        NSColor.systemPink.setStroke()
        tickPath.lineWidth = 2.0
        tickPath.lineCapStyle = .round
        tickPath.lineJoinStyle = .round
        tickPath.stroke()
    }

    private func checkboxInfo(at point: NSPoint) -> CheckboxRenderInfo? {
        guard let layoutManager,
              let textContainer,
              !string.isEmpty else {
            return nil
        }

        let insertionIndex = characterIndexForInsertion(at: point)
        let nsText = string as NSString
        let safeLocation = min(max(0, insertionIndex), max(0, nsText.length - 1))
        let lineRange = nsText.lineRange(for: NSRange(location: safeLocation, length: 0))
        guard let checkbox = checkboxInfo(in: lineRange) else {
            return nil
        }

        let hitRect = checkboxBoxRect(for: checkbox, layoutManager: layoutManager, textContainer: textContainer)
            .insetBy(dx: -4, dy: -4)
        return hitRect.contains(point) ? checkbox : nil
    }

    private func checkboxInfo(in lineRange: NSRange) -> CheckboxRenderInfo? {
        let nsText = string as NSString
        let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
        let nsLine = line as NSString
        guard let regex = try? NSRegularExpression(pattern: #"^(\s*)(\[[ x]\]) "#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) else {
            return nil
        }

        let markerRange = match.range(at: 2)
        let marker = nsLine.substring(with: markerRange)
        return CheckboxRenderInfo(
            lineRange: lineRange,
            markerRange: NSRange(location: lineRange.location + markerRange.location, length: markerRange.length),
            isChecked: marker == "[x]"
        )
    }

    private func checkboxBoxRect(
        for checkbox: CheckboxRenderInfo,
        layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: checkbox.markerRange, actualCharacterRange: nil)
        let markerRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let lineGlyphRange = layoutManager.glyphRange(forCharacterRange: checkbox.lineRange, actualCharacterRange: nil)
        let lineRect = layoutManager.boundingRect(forGlyphRange: lineGlyphRange, in: textContainer)
            .offsetBy(dx: textContainerOrigin.x, dy: textContainerOrigin.y)
        let size: CGFloat = 18
        let y = lineRect.isEmpty ? markerRect.minY : lineRect.midY - size / 2
        return NSRect(x: markerRect.minX + 2, y: y, width: size, height: size)
    }
}

private enum MarkdownImagePasteboardWriter {
    static func markdownImageReference(from pasteboard: NSPasteboard) -> String? {
        if let fileURL = imageFileURL(from: pasteboard) {
            return markdownReference(for: fileURL)
        }

        guard let image = image(from: pasteboard),
              let savedURL = save(image: image) else {
            return nil
        }

        return markdownReference(for: savedURL)
    }

    private static func imageFileURL(from pasteboard: NSPasteboard) -> URL? {
        if let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL],
           let imageURL = urls.first(where: { NSImage(contentsOf: $0) != nil }) {
            return imageURL
        }

        if let string = pasteboard.string(forType: .string),
           let url = imageURL(from: string) {
            return url
        }

        guard let fileURLString = pasteboard.string(forType: .fileURL),
              let url = URL(string: fileURLString),
              NSImage(contentsOf: url) != nil else {
            return nil
        }
        return url
    }

    private static func imageURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        if let url = URL(string: trimmed),
           url.isFileURL,
           NSImage(contentsOf: url) != nil {
            return url
        }

        let fileURL = URL(fileURLWithPath: trimmed)
        guard fileURL.isFileURL,
              NSImage(contentsOf: fileURL) != nil else {
            return nil
        }
        return fileURL
    }

    private static func image(from pasteboard: NSPasteboard) -> NSImage? {
        if let image = NSImage(pasteboard: pasteboard) {
            return image
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .tiff,
            .png,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif")
        ]

        for type in imageTypes {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        for type in pasteboard.types ?? [] where looksLikeImageType(type) {
            if let data = pasteboard.data(forType: type),
               let image = NSImage(data: data) {
                return image
            }
        }

        return nil
    }

    private static func looksLikeImageType(_ type: NSPasteboard.PasteboardType) -> Bool {
        let rawValue = type.rawValue.lowercased()
        return rawValue.contains("image")
            || rawValue.contains("png")
            || rawValue.contains("jpeg")
            || rawValue.contains("jpg")
            || rawValue.contains("tiff")
            || rawValue.contains("heic")
            || rawValue.contains("gif")
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
