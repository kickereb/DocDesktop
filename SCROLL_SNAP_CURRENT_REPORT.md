# DocDesktop Scroll Snap Report

Date: 2026-09-16

## 1. Summary

The local Markdown editor still has an annoying scroll snap while typing.

The issue is not fully fixed. The previous mitigation reduced some scroll jumps, but the editor can still move the visible text area when the user types or edits.

This must be treated as a core editor stability problem. DocDesktop is a shortcut-first note app. If typing moves the page unexpectedly, the app feels unreliable.

## 2. User Impact

The user experience should be:

1. Open DocDesktop.
2. Put the cursor where needed.
3. Type.
4. The visible editor area stays stable.

Current behavior:

1. User places the cursor.
2. User types one or more characters.
3. The editor scroll position can shift.
4. The user loses visual context.

This breaks fast note-taking. It is more important than adding new Markdown features.

## 3. Current Editor Architecture

The local editor uses:

- `MarkdownEditorView.swift`
- `MarkdownNSTextView`
- `MarkdownStyler.swift`
- `MarkdownEditingEngine`
- SwiftUI `ContentView`
- `DocumentContentViewModel`

Current edit path:

```text
User types
-> NSTextView textDidChange
-> MarkdownStyler reapplies attributes
-> selection is restored
-> scroll origin is restored
-> SwiftUI state is updated
-> SwiftUI can call updateNSView
```

The editor keeps Markdown source text. Styling is applied as AppKit attributes.

## 4. Current Mitigation

The current code attempts to preserve scroll position by saving the visible origin before styling and restoring it after styling.

This exists in:

- `MarkdownEditorView.Coordinator.textDidChange`
- `MarkdownEditorView.updateNSView`

This helps only if the scroll movement happens immediately. It does not fully prevent later TextKit or SwiftUI layout changes.

## 5. Likely Root Cause

The most likely root cause is full-document restyling on every text change.

`MarkdownStyler.apply(to:)` resets attributes across the whole text storage:

```swift
textStorage.setAttributes(..., range: wholeDocument)
styleBlocks(...)
styleInlineRuns(...)
```

This is too broad for live typing.

Each character can cause:

- full layout invalidation
- paragraph reflow
- line fragment recalculation
- selection scroll-to-visible behavior
- delayed scroll changes after the current run loop

The previous scroll restore handles only one point in time. TextKit can still scroll after that.

## 6. Other Contributing Causes

### Selection restoration

The code calls:

```swift
textView.setSelectedRange(selectedRange)
```

`NSTextView` can scroll to the selected range after this call.

### SwiftUI feedback loop

The editor sends each text change to SwiftUI state:

```swift
onTextChange(textView.string)
```

If SwiftUI sends that text back into `updateNSView`, the whole text view can be reset.

### Dynamic image preview area

The Markdown image preview strip appears when image syntax exists. If it appears or disappears, it changes layout height. This can affect scroll position.

This may not be the main cause, but it can worsen the problem.

### Paragraph styling

Headings, lists, quotes, and code blocks apply paragraph styles. Paragraph styles can change layout. When applied across the whole document, this can move content.

## 7. Why The Current Fix Is Not Enough

The current fix restores the clip view origin immediately after styling.

That is too early.

Scroll movement can happen after:

- TextKit completes layout
- `NSTextView` scrolls selection into view
- SwiftUI updates the view
- AppKit processes the next layout pass

Therefore, simple scroll restoration is a partial mitigation, not a real fix.

## 8. Recommended Engineering Fix

The correct fix is to stop full-document restyling during normal typing.

Recommended plan:

1. Style only the changed paragraph or block.
2. Avoid `setSelectedRange` unless the selection actually changed.
3. Stop SwiftUI from pushing the same text back into the text view during normal typing.
4. Restore visible origin after the next layout pass as a fallback.
5. Make image preview height stable.

## 9. Practical Next Patch

The next patch should be small and safe:

### Patch A: Avoid unnecessary selection reset

Only call `setSelectedRange` if the selected range changed.

### Patch B: Restore scroll after delayed layout

Restore visible origin immediately and again with:

```swift
DispatchQueue.main.async
```

### Patch C: Prevent SwiftUI echo updates

When the text change came from the editor, do not rewrite `textView.string` in `updateNSView`.

### Patch D: Stabilize image preview height

Reserve fixed space or move previews outside the main editor height flow.

## 10. Better Long-Term Fix

Build incremental styling.

Desired flow:

```text
User edits text
-> get edited range
-> expand to current Markdown block
-> clear and apply styles only in that block
-> preserve selection
-> preserve scroll
-> debounce local save
```

This is the correct long-term editor architecture.

It will also improve performance for long notes.

## 11. Product Priority

This should be fixed before multiple local notes.

Reason:

- Multiple notes will not matter if the editor feels unstable.
- The scroll snap damages trust in the product.
- The product promise is fast capture without interruption.

Priority order should be:

1. Fix scroll snap.
2. Verify long-note typing.
3. Verify undo and redo.
4. Add multiple local notes.
5. Add note switcher.

## 12. Acceptance Criteria

The fix is acceptable when:

- Typing a character does not move the visible scroll area.
- Typing in the middle of a long note stays visually stable.
- Return in a list does not jump the page.
- Tab and `Command + ]` do not jump the page.
- Shift-Tab and `Command + [` do not jump the page.
- Checkbox toggle does not jump the page.
- Image preview does not cause unexpected jumps during normal typing.

## 13. Final Diagnosis

The scroll snap is most likely caused by full-document Markdown styling and AppKit selection scroll behavior during every keystroke. The current scroll-origin restore is not enough because scroll changes can occur after TextKit finishes layout.

The next engineering fix should reduce editor feedback loops and move toward incremental block-level Markdown styling.
