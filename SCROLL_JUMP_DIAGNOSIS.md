# DocDesktop Scroll Jump Diagnosis

Date: 2026-09-13

## 1. Issue Summary

The local Markdown editor still jumps or snaps the scroll position while the user types.

Observed behavior:

- The user places the cursor in one visible part of the note.
- The user types one character.
- The editor immediately scrolls to another position.
- This makes typing feel unstable because the visible content moves during normal input.

This is a high-priority editor quality issue because DocDesktop's product promise is fast, low-friction note-taking. The editor must not move the page unless the user scrolls or types past the visible area.

## 2. Product Impact

This problem breaks the core interaction model.

The intended experience is:

1. Press `Command + Shift + D`.
2. Place cursor.
3. Type naturally.
4. Hide the overlay.

The current behavior adds friction at step 3. The user cannot trust that the editor will keep the current context stable.

For a shortcut-first note app, this is more serious than a visual polish issue. It affects writing speed and confidence.

## 3. Relevant Current Architecture

The local Markdown editor uses:

- `MarkdownEditorView.swift`
- `MarkdownNSTextView`, a custom `NSTextView`
- `MarkdownStyler.swift`
- `MarkdownEditingEngine`
- `DocumentContentViewModel`
- SwiftUI `ContentView`

The editor flow is:

```text
User types
-> NSTextView textDidChange
-> MarkdownStyler reapplies attributes to whole text storage
-> selected range is restored
-> SwiftUI state is updated through onTextChange
-> ContentView re-renders
-> MarkdownEditorView.updateNSView may run
```

## 4. Current Scroll Preservation Attempt

The code currently tries to preserve scroll position in two places:

### In `textDidChange`

`MarkdownEditorView.Coordinator.textDidChange` does:

```swift
let selectedRange = textView.selectedRange()
let visibleOrigin = visibleOrigin(for: textView)
applyStyle(to: textView)
textView.setSelectedRange(selectedRange)
restoreVisibleOrigin(visibleOrigin, for: textView)
onTextChange(textView.string)
```

### In `updateNSView`

`MarkdownEditorView.updateNSView` does:

```swift
let selectedRange = textView.selectedRange()
let visibleOrigin = context.coordinator.visibleOrigin(for: textView)
textView.string = text
context.coordinator.applyStyle(to: textView)
textView.setSelectedRange(...)
context.coordinator.restoreVisibleOrigin(visibleOrigin, for: textView)
```

This reduced one class of jumps, but it did not eliminate the problem.

## 5. Most Likely Root Causes

### Cause 1: Full-document style reset on every keystroke

`MarkdownStyler.apply(to:)` currently does this:

```swift
textStorage.setAttributes(baseAttributes(...), range: wholeDocumentRange)
styleBlocks(in: textStorage)
styleInlineRuns(in: textStorage)
```

This means every single typed character triggers a full attribute reset across the entire document.

That can force TextKit to:

- invalidate layout for the full document
- recalculate paragraph heights
- update line fragments
- move the visible rect
- scroll to maintain selection visibility

This is likely the main issue.

### Cause 2: `setSelectedRange` can scroll the text view

After styling, the code calls:

```swift
textView.setSelectedRange(selectedRange)
```

`NSTextView` can scroll the selection into view when the selection changes or is restored. Even if the range is the same, TextKit may treat it as a new selection after layout changes.

The code restores `visibleOrigin` after `setSelectedRange`, but another scroll can happen later in the same run loop after layout is recalculated.

This explains why the jump can still happen after the immediate restore call.

### Cause 3: SwiftUI update path may rewrite the string

Typing calls:

```swift
onTextChange(textView.string)
```

That updates `DocumentContentViewModel.editedText`, which triggers a SwiftUI re-render.

`updateNSView` checks:

```swift
if coordinator.loadedDocumentID != documentID || coordinator.currentText != text
```

In the common typing path, `currentText` should match `text`, so the editor should not rewrite `textView.string`.

However, if `currentText` and model text differ temporarily because of:

- custom key handling
- programmatic replacements
- timing between `textDidChange` and SwiftUI update
- checkbox toggle
- Return handling
- Tab handling

then `updateNSView` can rewrite the whole text view string. Rewriting `textView.string` is a strong scroll-jump trigger.

### Cause 4: The image preview strip changes layout height

In local Markdown mode, the editor is in:

```swift
VStack {
    MarkdownEditorView(...)
    MarkdownImagePreviewStrip(markdown: editedText)
}
```

When the note gains or loses Markdown image syntax, the preview strip appears or disappears. That changes the editor height.

This can also move visible content.

This is not the main issue shown in the screenshot, because the jump happens while typing normal text. But it is a future risk.

### Cause 5: TextKit layout is being forced by paragraph style changes

The styler applies paragraph styles to:

- headings
- lists
- quotes
- horizontal rules
- normal paragraphs

Paragraph style changes can change line height, indentation, and paragraph spacing. When this happens on the full document on every keystroke, TextKit may recalculate large parts of the layout.

This is likely another direct contributor.

## 6. Why The First Fix Was Not Enough

The first fix preserved the clip view origin immediately before and after styling. That only handles scroll changes that happen synchronously inside `textDidChange`.

The likely remaining jump is happening later, after:

- TextKit finishes layout
- `setSelectedRange` triggers scroll-to-selection
- SwiftUI calls `updateNSView`
- the text view processes the next layout pass

So restoring `visibleOrigin` once is not enough.

## 7. Technical Diagnosis

The current editor is using a "restyle whole document after every text change" model.

That model is simple but not stable enough for a live note editor.

The scroll jump is probably not a single bug. It is an emergent result of:

- full text storage attribute resets
- full layout invalidation
- selection restoration
- SwiftUI update timing
- TextKit scroll-to-caret behavior

The fix should move from "restore scroll after damage" to "avoid causing the damage."

## 8. Recommended Fix Strategy

### Step 1: Do not call `setSelectedRange` unless needed

If the selection did not change, avoid calling:

```swift
textView.setSelectedRange(selectedRange)
```

This reduces scroll-to-selection calls.

### Step 2: Restore scroll position on the next run loop too

After styling, restore scroll immediately and again with:

```swift
DispatchQueue.main.async { ... }
```

This handles delayed TextKit layout scroll.

This is a tactical fix, not the long-term solution.

### Step 3: Stop full-document restyling on each keystroke

Replace current full-document styling with scoped styling.

When the user types in one paragraph, only restyle:

- the current line
- surrounding lines if needed
- active Markdown block if inside code block or list

This should reduce layout invalidation and scroll movement.

### Step 4: Separate source edits from display styling

The editor should keep a stable plain text source and apply style in a controlled way.

The source string should not be rewritten from SwiftUI during normal typing.

Only these events should rewrite the entire editor string:

- loading a new document
- switching note
- restoring draft
- explicit external reload

Normal typing should remain inside `NSTextView`.

### Step 5: Add an editor-local state object

Currently SwiftUI state is updated on each text change. That makes SwiftUI part of the typing loop.

Better:

- `NSTextView` owns text while editing
- local model receives debounced updates
- SwiftUI does not push text back unless the document identity changes

This reduces feedback loops.

## 9. Short-Term Patch Proposal

The fastest safe patch is:

1. Add a helper that restores visible origin immediately and asynchronously.
2. Only call `setSelectedRange` if the current selected range is different.
3. In `updateNSView`, do not rewrite `textView.string` for normal local typing.
4. Add a flag for "text came from editor" so SwiftUI updates do not reflect back into the text view.

Expected result:

- Scroll jump should reduce significantly.
- It may not be fully gone for long documents because full-document styling remains.

Risk:

- Low.
- It changes editor update behavior only.
- It does not touch Google sync.

## 10. Long-Term Fix Proposal

The correct long-term fix is incremental Markdown styling.

Needed architecture:

```text
NSTextView edit event
-> identify changed range
-> expand to current Markdown block
-> clear/apply attributes only in that block
-> preserve selection and visible rect
-> debounce model save
```

This turns styling from full-document work into local work.

It also improves performance for long notes.

## 11. Product Recommendation

Fix this before adding more Markdown features.

Reason:

- Images, lists, and checkboxes are useful, but typing stability is more important.
- If the editor moves while typing, users will not trust the app.
- The app's core promise is fast capture and low interruption.

Recommended next sprint priority:

1. Stop scroll jumps.
2. Confirm stable typing with long notes.
3. Confirm selection and undo behavior.
4. Then continue with more Markdown features.

## 12. Acceptance Criteria

The issue is fixed when:

- Typing one character does not change scroll position.
- Typing in the middle of a long note keeps the same visible area.
- Pressing Return in a list continues the list without jumping.
- Pressing Tab or Shift-Tab does not jump the document.
- Clicking a checkbox toggles the marker without moving the page unexpectedly.
- Markdown image preview appearing or disappearing does not create surprise jumps during normal text editing.

## 13. Final Diagnosis

The scroll jump is most likely caused by full-document Markdown restyling and selection restoration inside `NSTextView` on every keystroke. The existing scroll restore happens too early and does not fully defend against later TextKit or SwiftUI layout updates.

The right fix is to reduce editor feedback loops and move toward incremental styling. The immediate fix should preserve scroll after delayed layout and prevent unnecessary selection and string resets.
