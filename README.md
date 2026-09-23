# DocDesktop

DocDesktop is a native macOS overlay note editor that is being developed toward an Antinote-style writing surface for Google Docs.

The current product direction is:

```text
Global shortcut
-> fast floating editor
-> local Markdown-style note-taking
-> later semantic sync back to Google Docs
```

The Google backend is still preserved, but current development is focused on making the local Markdown editor feel fast, stable, and predictable before reconnecting rich sync.

## Current Status

Working:

- Native macOS app shell
- Menu bar app
- Overlay-style window
- Global shortcut
- Local Markdown development mode
- Local new note flow
- Headings
- Bold
- Italic
- Bold italic
- Strikethrough
- Inline code
- Links
- Bullet lists
- Numbered lists
- Nested lists
- Checkbox list items
- Clickable checkbox toggle
- Checkbox hover state
- Checked-item strikethrough
- Return-to-continue list behavior
- Tab and Shift-Tab indentation
- Command `[` and Command `]` indentation shortcuts
- Inline image previews
- Pasted local image paths
- Pasted image files and clipboard image data
- Scroll stability improvements during typing

Preserved Google backend:

- Google OAuth sign-in
- Keychain token storage
- Google Drive file discovery
- My Drive discovery
- Shared with me discovery
- Shared Drive discovery
- Pasted Google Docs URL parsing
- Google Docs loading
- UTF-16 index mapping
- Basic text save pipeline
- Revision-aware write control

Not ready:

- Production Google Docs Markdown sync
- Semantic Markdown-to-Google formatting sync
- Full conflict merge
- Offline edit queue
- Multi-note local storage
- Table editing
- Google Docs image write-back
- Comments and suggestions
- Full settings screen

## App Definition

DocDesktop is no longer being treated as a passive desktop widget.

The current target is a lightweight macOS overlay editor:

- The user works in another app.
- The user presses a global shortcut.
- DocDesktop appears above the current app.
- The editor is immediately writable.
- The user writes in a Markdown-style note surface.
- The same shortcut or Escape hides the editor.

This puts the app closer to Spotlight, Raycast, Quick Note, or Antinote than a normal document window.

## Keyboard Shortcut

Current shortcut:

```text
Control-Command-D
```

The shortcut is implemented with Carbon hotkeys in `GlobalHotKeyManager.swift`.

This shortcut does not require:

- Accessibility permission
- Input Monitoring permission
- Screen Recording permission

If it conflicts with another app, change the modifier flags in `GlobalHotKeyManager.swift`.

## Local Markdown Editor

The local editor uses `NSTextView` and TextKit.

Important behavior:

- Markdown source remains the stored text.
- Styling is visual only.
- The editor does not rewrite Markdown syntax while styling.
- Normal typing restyles only affected blocks where possible.
- Scroll position should not jump during ordinary typing.

Supported visual Markdown features:

- `# Heading 1`
- `## Heading 2`
- `### Heading 3`
- `**bold**`
- `*italic*`
- `***bold italic***`
- `~~strikethrough~~`
- `` `inline code` ``
- `[label](https://example.com)`
- `- bullet`
- `1. numbered`
- `[ ] task`
- `[x] done`
- `> quote`
- `---`
- `![alt](file:///path/to/image.png)`
- `/Users/name/path/to/image.jpg`

## Images

Inline images are currently local-editor features.

Supported:

- Dragging image files into the editor
- Pasting a local image file path
- Pasting copied image data from the clipboard where macOS exposes image pasteboard data
- Displaying inline previews inside the Markdown editor

Preview behavior:

- Images use aspect-fit.
- The full image should remain visible.
- The preview row has a fixed height to protect scroll stability.
- The Markdown source remains a path or image reference.

Not supported yet:

- Image resizing handles
- Image crop controls
- Image captions
- Uploading local images back into Google Docs
- Google Drive asset storage for pasted images

## Google Cloud Setup

For Google-backed document loading, configure Google Cloud:

1. Create a Google Cloud project.
2. Enable the Google Drive API.
3. Enable the Google Docs API.
4. Configure the OAuth consent screen.
5. Add test users if the app is still in test mode.
6. Create an OAuth client for a native app.
7. Add the client ID to `GoogleOAuthConfig.swift`.
8. Add the reversed client ID URL scheme to the app target.
9. Make sure `Info.plist` contains the same URL scheme.
10. Run the app and sign in.

Current scopes:

```text
https://www.googleapis.com/auth/documents
https://www.googleapis.com/auth/drive.metadata.readonly
https://www.googleapis.com/auth/drive.readonly
```

Why these scopes exist:

- `documents`: read and edit the selected Google Doc.
- `drive.metadata.readonly`: find document files and read file permissions.
- `drive.readonly`: support Drive-based file access and shared-drive discovery.

OAuth tokens are stored in Keychain. Document metadata is stored in `UserDefaults`. Access tokens and refresh tokens are not stored in plain text project files.

## Build

Open the project in Xcode and build the `DocDesktop` scheme for `My Mac`.

Command-line build from the repo root:

```zsh
xcodebuild -scheme DocDesktop -destination 'platform=macOS'
```

## GitHub Workflow

Normal update flow:

```zsh
cd "/Users/evam/Desktop/XCode Dev/DocDesktop"

git status --short
git add <changed-files>
git commit -m "Describe the change"
git pull --rebase --autostash origin main
git push origin main
```

Do not commit Xcode user interface state unless you explicitly want it:

```text
DocDesktop.xcodeproj/project.xcworkspace/xcuserdata/evam.xcuserdatad/UserInterfaceState.xcuserstate
```

## Sync Direction

The eventual sync model is semantic, not literal Markdown upload.

Target architecture:

```text
Google Docs structure
-> local Markdown representation
-> Markdown editor
-> semantic edit model
-> Google Docs API requests
```

Important rule:

```text
## Heading
```

should become a real Google Docs Heading 2 paragraph when synced. It should not be uploaded as literal hash characters unless the user intentionally wants literal Markdown text.

Future Google Docs updates should use:

- `insertText`
- `deleteContentRange`
- `updateTextStyle`
- `updateParagraphStyle`
- `createParagraphBullets`
- `deleteParagraphBullets`

The app should avoid replacing complete Google Docs documents for small edits.

## Main Files

- `DocDesktopApp.swift`: app entry point
- `AppDelegate.swift`: menu bar, app commands, shortcut connection
- `GlobalHotKeyManager.swift`: global `Control-Command-D` shortcut
- `DesktopWindowController.swift`: overlay/window controller behavior
- `WidgetWindow.swift`: key-capable custom panel, now reused toward overlay behavior
- `ContentView.swift`: main app UI
- `MarkdownEditorView.swift`: native Markdown editor bridge and editor commands
- `MarkdownStyler.swift`: TextKit Markdown styling
- `GoogleAuthManager.swift`: Google OAuth
- `KeychainManager.swift`: secure token persistence
- `DriveService.swift`: Drive discovery
- `GoogleDocsService.swift`: Docs load and save calls
- `GoogleDocsParser.swift`: Docs API parsing
- `GoogleDocsIndexMapper.swift`: UTF-16 edit mapping
- `DocumentContentViewModel.swift`: editor load, save, and sync state
- `DocumentSyncPolicy.swift`: sync safety rules

## Development Priority

Current priority:

1. Make the local Markdown editor reliable.
2. Keep overlay show/hide behavior stable.
3. Keep scroll position stable while typing.
4. Polish Markdown interactions.
5. Then resume Google Docs semantic sync.

Do not expand Google sync until the local editor feels dependable.

## Known Limits

DocDesktop is not yet a production Google Docs replacement.

Use Google Docs directly for:

- Complex tables
- Comments
- Suggestions
- Headers and footers
- Smart chips
- Collaborative editing
- Production document formatting

The local Markdown editor is the current development surface.
