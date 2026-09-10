# DocDesktop Product Report

Date: 2026-09-10

## 1. Short Summary

DocDesktop is a native macOS app for quick note edits connected to Google Docs.

The first idea was a desktop widget that stayed on the desktop. That direction created focus and window-order problems on macOS, especially after the user clicked another app, Finder, or the desktop.

The product direction is now different. DocDesktop is now planned as a shortcut-first overlay editor, similar to Antinote, Spotlight, Raycast, or Quick Note.

The app should stay resident in the menu bar. The user presses a global shortcut, edits one selected note, and hides the app again.

## 2. Product Goal

The goal is to make a fast note editor that uses Google Docs as the remote source.

The ideal user flow is:

1. The user works in Safari, Chrome, Xcode, VS Code, or another app.
2. The user presses `Command + Shift + D`.
3. DocDesktop appears above the current app.
4. The selected note opens immediately.
5. The user writes or edits text.
6. The app saves locally first.
7. Later, the app syncs safe changes to the same Google Doc.
8. The user presses Escape or the shortcut again.
9. DocDesktop hides.
10. The previous app becomes active again.

The product is not a full Google Docs clone at this stage. It is a lightweight Google Docs companion for fast capture, review, and small edits.

## 3. Current Working Features

The app currently has these working parts:

- Native macOS Swift and SwiftUI app shell.
- Menu-bar presence.
- Global shortcut support.
- Overlay-style window direction.
- Saved window size and position.
- Google OAuth sign-in.
- Keychain token storage.
- Google Drive document discovery.
- My Drive document listing.
- Shared with me document listing.
- Shared Drive document listing, where available.
- Google Docs URL paste and validation.
- Selected document persistence.
- Google Docs document loading.
- Google Docs tab content loading.
- Plain text extraction.
- Basic rich text display from Google Docs.
- Inline image display from Google Docs in the old attributed text path.
- Basic text-only save to Google Docs.
- UTF-16 index mapping for Google Docs API ranges.
- `documents.batchUpdate` save path.
- `targetRevisionId` write control.
- Safe local conflict behavior for some remote-change cases.
- Local Markdown development mode.
- Local scratch note without Google sign-in.
- Local draft persistence in `UserDefaults`.
- Native Markdown text styling in `NSTextView`.
- Markdown list continuation when pressing Return.

## 4. Current Development Mode

The app is now in local Markdown engine development mode.

This mode exists because Google Docs sync was too risky while the editor behavior was not stable. The previous sync path could send invalid Google Docs requests when Markdown syntax or paragraph breaks changed.

In local Markdown development mode:

- Google sign-in is not required for editor testing.
- The app opens a local Markdown scratch note.
- The note saves locally.
- Google Docs sync is paused.
- The Markdown source text is kept.
- Styling is visual only.
- The app does not send local test edits to Google Docs.

This lets us perfect note-taking behavior before we reconnect cloud sync.

## 5. Why The Desktop Widget Direction Was Stopped

The desktop-widget design caused several macOS window problems.

Observed problems:

- The widget could become unclickable after the user clicked another app.
- The app sometimes needed Command-Tab before it accepted input again.
- The window could appear in front of other apps when it should stay below them.
- Mission Control behavior was inconsistent.
- Some window button states became blank or inactive.
- The desktop-space model fought against editable text input.

The root issue is that a passive desktop widget and an editable text editor need different AppKit behavior.

A desktop widget wants to sit behind apps. An editor must become key, accept keyboard focus, accept scroll events, and activate cleanly.

The new overlay model is a better fit because it is intentionally active only when the user asks for it.

## 6. New Product Definition

DocDesktop is now:

> A keyboard-first macOS overlay note editor backed by Google Docs.

The app should feel like:

- Antinote for fast note capture.
- Raycast for instant command access.
- Quick Note for temporary focus.
- A small native editor, not a browser tab.

The app should not feel like:

- A permanent desktop widget.
- A normal document app.
- A full Google Docs web replacement.
- A heavy Electron app.

## 7. Window And Shortcut Design

The planned window behavior is:

- The app stays in the menu bar.
- `Command + Shift + D` toggles the editor.
- When hidden, the app uses very little CPU.
- When shown, the window appears above normal apps.
- The editor becomes first responder immediately.
- The caret position is preserved where possible.
- Escape hides the window.
- Hiding the window restores the previous app where practical.
- The window is movable.
- The window remembers size and position.
- The app does not create a new window each time.

The old desktop pinning behavior should not be used going forward.

## 8. Google Backend Status

The Google backend should be preserved.

The following parts are useful and should stay:

- `GoogleAuthManager.swift`
- `GoogleOAuthConfig.swift`
- `KeychainManager.swift`
- `DriveService.swift`
- `DriveFile.swift`
- `DocumentPickerView.swift`
- `DocumentPickerViewModel.swift`
- `GoogleDocsService.swift`
- `GoogleDocsParser.swift`
- `GoogleDocsModels.swift`
- `GoogleDocsURLParser.swift`
- `ActiveDocumentStore.swift`
- `GoogleDocsIndexMapper.swift`
- `DocumentSyncPolicy.swift`

These files already solve important problems:

- Google sign-in.
- Token refresh.
- Secure token storage.
- Drive file lookup.
- Shared document access.
- Google Docs API access.
- Remote document IDs.
- Revision IDs.
- UTF-16 Google Docs indexes.
- Safe batch update structure.

The backend is not finished, but it is a strong base. It should not be rewritten unless there is a clear technical need.

## 9. Current Editor Status

The current editor is a native `NSTextView` wrapped in SwiftUI.

It uses:

- `MarkdownEditorView.swift` for the editor bridge.
- `MarkdownStyler.swift` for local visual styling.
- `MarkdownEditingEngine` for editor behavior such as Return in lists.

The current Markdown system keeps the source text. For example, `## Heading` still exists in the text buffer. The app applies visual style to make the heading look like a heading.

This is better than the earlier approach, which tried to convert shortcuts too early and then send them to Google Docs.

## 10. Markdown Behavior Done

The local Markdown editor currently supports visual styling for:

- Heading 1.
- Heading 2.
- Heading 3.
- Heading 4 to Heading 6.
- Bold.
- Italic.
- Bold plus italic.
- Strikethrough.
- Links.
- Bullet lists.
- Numbered lists.
- Checkbox text markers.
- Block quotes.
- Inline code.
- Code blocks.
- Horizontal rules.

The editor also supports:

- Keeping the Markdown source text.
- Styling without deleting syntax.
- Continuing a bullet list when the user presses Return.
- Continuing a numbered list with the next number.
- Continuing a checkbox list as a new unchecked item.
- Exiting an empty list item when the user presses Return.

## 11. Markdown Behavior Still Needed

The editor still needs work before we reconnect Google sync.

Needed next:

- Better display of Markdown markers.
- More Antinote-like editing.
- Tab to indent list items.
- Shift-Tab to outdent list items.
- Checkbox toggle.
- Better paste handling.
- Image preview for Markdown images.
- Stable cursor position after styling.
- Better selection behavior while styling.
- Better performance for long notes.
- Undo behavior checks after custom edits.

## 12. Image Support Plan

Images are needed because Google Docs can contain inline images, and Markdown notes can contain image syntax.

There are two different image cases:

### Local Markdown Images

Markdown image syntax:

```markdown
![Alt text](image-url-or-file-path)
```

The local editor should show a preview while preserving the Markdown text.

Good first version:

- Detect Markdown image syntax.
- Load local file images and remote URL images.
- Insert an inline preview attachment.
- Keep the Markdown source safe.
- Do not corrupt the draft if the image fails to load.
- Show a small placeholder if the image cannot load.

### Google Docs Images

Google Docs images are not normal text.

The app must treat them as protected document objects.

Rules:

- Do not delete images during text sync.
- Do not replace a document section that contains an image.
- Show images in the editor when possible.
- If editing around an image is unsafe, block the sync.
- Later, support image insert and image delete as separate Google Docs API actions.

## 13. Sync Status

Sync is intentionally paused in development mode.

Earlier Google sync work showed these problems:

- Google Docs rejected edits that included the final segment newline.
- Google Docs rejected edits across paragraph breaks.
- Google Docs rejected edits near unsupported content.
- Markdown syntax was sent as plain text in some cases.
- Formatting and text changes were not separated well enough.

The new direction is:

- Local edits first.
- Stable local Markdown model second.
- Google Docs conversion third.
- Cloud sync last.

This is the safer product path.

## 14. Future Sync Architecture

The desired sync flow is:

```text
Google Docs structure
-> Google Docs to Markdown converter
-> Markdown document model
-> Markdown editor
-> Local change model
-> Google Docs API requests
```

Text and formatting must be separate.

Examples:

- A text edit sends `insertText` or `deleteContentRange`.
- A bold command sends `updateTextStyle`.
- A heading command sends `updateParagraphStyle`.
- A bullet command sends `createParagraphBullets`.
- A link command sends `updateTextStyle` with a link field.

The app must not upload the full document after each edit.

The app must not turn Google Docs headings into literal `##` text unless the user really typed those characters.

## 15. Data Safety Rules

These rules are mandatory:

- Never overwrite a Google Doc with the local draft.
- Never replace the full remote document as a shortcut.
- Never delete images, tables, equations, smart chips, drawings, headers, or footers by accident.
- Never reload remote content over unsaved local work.
- Always use `targetRevisionId` or another safe revision check.
- Keep local drafts when sync fails.
- Do not send empty batch requests.
- Do not send ranges that include unsupported objects.
- Keep text edits and formatting edits separate.

## 16. Recommended Editor Engine Direction

There are two reasonable paths.

### Path A: Native TextKit Editor

This is the current path.

Benefits:

- Fully native macOS.
- Strong keyboard and focus behavior.
- No web view bridge.
- Works well with AppKit.
- Easier to connect to native menus and shortcuts.
- Easier to keep app lightweight.

Costs:

- We must build Markdown editing behavior ourselves.
- Live preview is difficult.
- Inline image preview and syntax hiding need careful TextKit work.
- Complex Markdown features take time.

### Path B: CodeMirror 6 In WKWebView

This is the strongest full editor-engine option.

Benefits:

- Mature editor behavior.
- Strong Markdown language support.
- Good selection and transaction model.
- Easier syntax parsing.
- Easier rich Markdown display.
- Good base for future commands.

Costs:

- Requires a `WKWebView` bridge.
- Requires local JavaScript assets.
- More moving parts.
- Native input feel needs careful testing.
- Google sync must receive changes through a bridge.

### Recommendation

For the next two or three product iterations, continue with the native TextKit editor.

Reason:

The app is still proving core behavior: overlay, local note speed, Markdown feel, safe save, and later Google sync. A web editor migration now would add risk before the product behavior is stable.

If the native engine becomes too slow to make Antinote-like, then migrate to CodeMirror 6 in a controlled stage.

## 17. Short-Term Roadmap

### Stage 1: Local Markdown Editor Stability

Finish note-taking quality with no Google sync.

Tasks:

- List continuation.
- List indentation.
- Checkbox toggle.
- Markdown image preview.
- Better heading display.
- Better marker dimming.
- Paste cleanup.
- Undo and redo validation.
- Local draft save reliability.

### Stage 2: Local Document Model

Create a real local Markdown document model.

Tasks:

- Track blocks.
- Track inline marks.
- Track image placeholders.
- Track selection.
- Track safe text ranges.
- Track edit history.

### Stage 3: Google Docs To Markdown

Build a converter from Google Docs structure to local Markdown.

Tasks:

- Headings.
- Paragraphs.
- Bold and italic.
- Links.
- Lists.
- Nested lists.
- Images as protected placeholders.
- Unsupported objects as protected placeholders.

### Stage 4: Markdown To Google Docs Requests

Convert local semantic edits to small Google Docs API requests.

Tasks:

- Text insert.
- Text delete.
- Text replace.
- Heading changes.
- Bold and italic changes.
- Link changes.
- List changes.

### Stage 5: Conflict And Remote Refresh

Make sync safe for real use.

Tasks:

- Compare revision IDs.
- Queue local edits.
- Block unsafe remote reload.
- Show clear conflict messages.
- Keep local draft during errors.

## 18. Known Risks

Main risks:

- Google Docs API range rules are strict.
- Google Docs uses UTF-16 indexes.
- Images and tables are not simple text.
- Markdown source and Google Docs formatting are different models.
- The editor must not produce sync operations during remote load.
- Programmatic style updates must not count as user edits.
- A full live preview editor is hard in pure `NSTextView`.

The best way to reduce risk is to keep sync off until local editing is stable.

## 19. Product Manager Questions

Questions to settle:

1. Is the product a fast personal note layer, or a full Google Docs editor?
2. Should local notes exist without Google Docs long term?
3. Should Markdown syntax be visible, dimmed, or hidden?
4. Should Google Docs remain the only cloud store?
5. Should the first release support images as read-only previews only?
6. Should formatting sync wait until text sync is reliable?
7. Should we publish to the Mac App Store, distribute directly, or keep it private first?

## 20. Current Recommendation

The next product milestone should be:

> Make local Markdown note-taking feel excellent before turning Google sync back on.

That means:

- Keep development mode on.
- Add image preview.
- Add list indentation.
- Add checkbox toggle.
- Make the editor feel quick and predictable.
- Do not touch Google sync until these basics are stable.

This gives the team a stable editor core. After that, Google Docs sync can be added back with less risk to user documents.
