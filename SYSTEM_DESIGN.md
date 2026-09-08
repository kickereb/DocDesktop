# DocDesktop System Design

## Purpose

DocDesktop is a native macOS app that shows one selected Google Doc in a small desktop-style window.

The app is not a full Google Docs replacement. It is a focused widget-style editor for one document, with simple text edits and safe sync behavior.

## Current Product Scope

Implemented:

- Desktop widget-style macOS window
- Menu bar app controls
- Google OAuth sign-in
- Google Drive document discovery
- Google Docs URL paste and validation
- Read-only Google Docs loading
- Inline image display
- Basic text editing
- Text save through Google Docs `documents.batchUpdate`
- Basic remote reload when there are no unsaved local edits

Not implemented:

- Full formatting edit toolbar
- Offline edit queue
- Full conflict merge
- Table editing
- Image editing
- Checkbox edit support
- Full multi-tab UI
- Full production settings UI

## High-Level Architecture

The app has five main layers:

1. macOS shell
2. Authentication
3. Drive discovery
4. Docs loading and editing
5. SwiftUI/AppKit editor UI

### macOS Shell

Files:

- `DocDesktopApp.swift`
- `AppDelegate.swift`
- `DesktopWindowController.swift`
- `WidgetWindow.swift`
- `WindowStateStore.swift`

Responsibilities:

- Start the app.
- Create the menu bar item.
- Create and manage the widget window.
- Save and restore window size and position.
- Keep the window visually on the desktop.
- Let the window receive mouse, scroll, and keyboard events.

### Authentication

Files:

- `GoogleAuthManager.swift`
- `GoogleOAuthConfig.swift`
- `KeychainManager.swift`
- `Info.plist`
- `DocDesktop.entitlements`

Responsibilities:

- Start Google OAuth with `ASWebAuthenticationSession`.
- Use PKCE.
- Receive the custom URL callback.
- Store refresh tokens in Keychain.
- Refresh access tokens.
- Never store tokens in `UserDefaults`.

Current scopes:

- `https://www.googleapis.com/auth/documents`
- `https://www.googleapis.com/auth/drive.metadata.readonly`
- `https://www.googleapis.com/auth/drive.readonly`

### Drive Discovery

Files:

- `DriveService.swift`
- `DriveFile.swift`
- `DocumentPickerViewModel.swift`
- `DocumentPickerView.swift`
- `GoogleDocsURLParser.swift`
- `ActiveDocumentStore.swift`

Responsibilities:

- List Google Docs from My Drive.
- List Google Docs shared with the user.
- List Google Docs in Shared Drives.
- Search visible document lists.
- Parse pasted Google Docs URLs.
- Store the active selected document.
- Store only document metadata, not document content.

### Docs Loading And Parsing

Files:

- `GoogleDocsService.swift`
- `GoogleDocsParser.swift`
- `GoogleDocsModels.swift`

Responsibilities:

- Call `documents.get`.
- Use `includeTabsContent=true`.
- Read top-level document body content and tab body content.
- Read text runs.
- Read links and basic text styles.
- Read inline image metadata.
- Fetch inline image content.
- Build an AppKit `NSAttributedString`.
- Build local-to-Google text index segments.

Unsupported elements must not crash the app. They must show a placeholder or read-only representation.

### Text Editing And Save

Files:

- `MacAttributedTextView.swift`
- `DocumentContentViewModel.swift`
- `GoogleDocsIndexMapper.swift`
- `GoogleDocsService.swift`

Responsibilities:

- Show the loaded document in `NSTextView`.
- Allow editing only when Drive says the user can edit.
- Track changed text.
- Autosave text-only edits after a short delay.
- Save with `documents.batchUpdate`.
- Use Google Docs `WriteControl` with `targetRevisionId`.
- Map AppKit `NSString` ranges to Google Docs UTF-16 indexes.

Important rule:

The app must not replace the whole document. It must save small text edits only.

## Google Docs Data Flow

### Load

1. User signs in.
2. App gets a valid access token.
3. App calls Drive API to list documents.
4. User selects one document.
5. App calls Docs API `documents.get`.
6. App parses:
   - title
   - revision ID
   - tabs
   - paragraphs
   - text runs
   - inline objects
   - image URLs
7. App downloads available inline images.
8. App displays an attributed text document.

### Edit

1. User edits the `NSTextView`.
2. App stores local edited text.
3. App marks state as `Unsaved`.
4. Autosave waits for a short quiet period.
5. App compares original text with edited text.
6. App builds one safe text edit.
7. App maps local UTF-16 indexes to Google Docs indexes.
8. App sends `documents.batchUpdate`.
9. App reloads the document after save.
10. App updates the revision ID.

### Sync

1. App checks remote state every 20 seconds.
2. If there are no unsaved local edits, app can reload remote content.
3. If there are unsaved local edits, app must not replace local text.
4. If a save fails because the revision changed, app must keep local text.

## Data Safety Rules

The app must never silently lose content.

Rules:

- Do not reload over unsaved local edits.
- Do not save edits that cross images, tables, or unsupported placeholders.
- Do not delete unsupported content to make a save easier.
- Do not save a whole-document replacement.
- Use `targetRevisionId` for write control.
- If Google rejects a write because the document changed, keep the local edit.
- Tell the user about the conflict.

## Current Save Limitation

The current edit path supports one text diff at a time.

Supported:

- Insert text inside a text run
- Delete text inside a text run
- Replace text inside a text run
- Basic edits across normal text in one tab

Blocked:

- Edits that touch images
- Edits that touch tables
- Edits across multiple tabs
- Edits across unsupported content
- Rich formatting saves

This is intentional. It protects user data until the sync engine becomes stronger.

## Window And Focus Design

The widget must feel like a desktop widget, but it must still behave like an editable app window.

Current window type:

- `WidgetWindow` subclasses `NSPanel`.
- It returns `canBecomeKey = true`.
- It returns `canBecomeMain = false`.
- It uses the desktop icon window level.
- It joins all Spaces.
- It uses transient and stationary collection behavior.
- It hides title bar buttons.

Current problem:

After the user clicks another app or the desktop, the widget can become visible but not interactive. Command-Tab can recover it, which means the app still exists, but the first click is not activating or keying the editor correctly.

Likely cause:

The window uses `.nonactivatingPanel`. This is useful for a passive desktop widget, but it is risky for an editable text widget because AppKit can avoid normal app activation. The `NSTextView` then does not always receive keyboard focus after the app loses active state.

Recommended fix:

Use two interaction modes.

### Passive Mode

Passive mode is for reading on the desktop.

Window behavior:

- Desktop-level window
- Minimal controls
- Does not float above normal app windows
- Visible in Show Desktop
- Does not force the app active

### Editing Mode

Editing mode starts when the user clicks inside document content.

Window behavior:

- Activate `NSApp`.
- Make the widget key.
- Make the `NSTextView` first responder.
- Keep the same visual design.
- Do not force the app to stay active after the user switches away.

Implementation plan:

1. Replace `.nonactivatingPanel` if it prevents reliable focus.
2. Keep the custom `NSPanel` or use a borderless `NSWindow` subclass.
3. Keep `canBecomeKey = true`.
4. On mouse down inside the editor:
   - call `NSApp.activate(ignoringOtherApps: true)`
   - call `window.makeKeyAndOrderFront(nil)`
   - call `window.makeFirstResponder(textView)`
5. On scroll events:
   - make the window key if needed
   - do not force text editing focus
6. On app resign active:
   - return the window to desktop level
   - do not keep reactivating the app

## Recommended Next Window Fix

The next code change should focus on this only:

- Remove `.nonactivatingPanel`.
- Keep a custom key-capable window.
- Keep hidden title bar controls.
- Ensure the editor explicitly becomes first responder on click.
- Keep desktop-level collection behavior.

This gives AppKit a normal activation path and should fix the click-away bug with less special behavior.

Risk:

Removing `.nonactivatingPanel` can make the app feel more like a normal app when clicked. That is acceptable while editing because text editing needs a real key window.

## Stage 7 Design

Stage 7 should add simple formatting commands without enabling full Google Docs editing.

Supported commands:

- Heading 1
- Heading 2
- Bold
- Italic
- Underline
- Bullet list
- Numbered list
- Link

The app should convert selected text or typed shortcuts into Google Docs formatting requests. It must not rewrite the complete document.

## Markdown-Style Shortcut Design

Use a small shortcut layer, not a full Markdown renderer.

Shortcuts:

- `# Text` becomes Heading 1
- `## Text` becomes Heading 2
- `- Text` becomes a bullet item
- `1. Text` becomes a numbered item
- `[ ] Text` becomes a checkbox item later
- `[Label](https://example.com)` becomes a link later

Save strategy:

- First save the plain text safely.
- Then send formatting requests for the affected range.
- If formatting fails, keep the text save and show a formatting warning.

This keeps the document useful and reduces data loss risk.

## Stage 8 Offline Design

Offline support should store pending text operations locally.

Rules:

- Store pending edits, not tokens.
- Keep document visible.
- Let the user continue editing.
- Mark state as `Offline`.
- Retry after the network returns.
- Before upload, fetch the latest revision.
- If remote changed, enter conflict state.

Suggested files:

- `NetworkMonitor.swift`
- `PendingEditStore.swift`
- `DocumentCache.swift`

## Stage 9 Polish Design

Polish should come after the focus and sync rules are stable.

Items:

- Settings UI
- Opacity setting
- Font scale setting
- Width and height setting
- Launch at login
- Better empty and error states
- Better status messages
- Better tab selector
- Scroll position restore

## Test Plan

Required unit tests:

- URL parser tests
- UTF-16 index mapper tests
- Insert at end of paragraph
- Emoji before edit
- Accented characters
- Combining characters
- Replacement edit
- Unsupported range rejection
- Revision conflict error handling

Manual tests:

- Click editor and type.
- Click Finder.
- Click widget again and type.
- Scroll after switching apps.
- Use Show Desktop and click the widget.
- Save insert at end of document.
- Save edit in middle of paragraph.
- Try edit near image.
- Confirm image is not deleted.
- Edit the same Google Doc in browser, then confirm app does not overwrite unsaved local text.

## Open Design Questions

1. Should clicking the widget always activate DocDesktop, or only clicking the editor?
2. Should passive reading keep the app inactive when clicked outside the editor?
3. Should the app support one tab only first, or show all tabs with a selector?
4. Should checkbox editing be deferred until Stage 7 or Stage 8?
5. Should local cached document content be stored on disk, and if yes, should it be encrypted?

## Current Recommendation

Fix the click-away bug before more editing features.

Then implement Stage 6 as text-only sync safety:

- stronger revision conflict handling
- explicit conflict state
- do not reload over unsaved text
- preserve local text after failed save
- add tests for conflict and unsupported edits

After that, add Stage 7 shortcuts for simple formatting.
