# DocDesktop

DocDesktop is a native macOS desktop editor for one selected Google Doc.

It shows the document in a small widget-style window on the desktop. You can sign in with Google, select a document from Drive, view the document, see inline images, and make basic text edits.

## Current Status

Done:

- Desktop widget window
- Saved window position and size
- Menu bar app
- Google OAuth sign-in
- Google Drive document picker
- My Drive, Shared with me, and Shared Drive discovery
- Paste Google Docs URL
- Google Docs read loading
- Google Docs tab content loading
- Inline image display
- Basic text edit and save
- Basic safe remote reload
- Global pop-up shortcut

Not done:

- Full conflict merge
- Offline edit queue
- Formatting edit toolbar
- Checkbox edit support
- Table editing
- Image editing
- Full tab selector
- Full settings screen

## App Definition

DocDesktop is a desktop-first Google Docs companion app.

The app has two window modes:

- Desktop mode: the document stays at the desktop layer and normal apps cover it.
- Pop-up mode: press `Option-D` to bring the document forward for quick editing.

When the app loses focus, it returns to the desktop layer. This keeps it from sitting above all other apps.

## Keyboard Shortcut

Press:

```text
Option-D
```

This pops up the document window and gives it focus.

This shortcut uses the macOS hotkey API. It does not need Accessibility permission and it does not need Input Monitoring permission.

If the shortcut does not work, another app can be using the same shortcut. Change the shortcut in `GlobalHotKeyManager.swift`.

## macOS Permissions

Required:

- Outgoing network access
- Keychain access
- URL scheme callback for Google OAuth

Not required for the fixed shortcut:

- Accessibility
- Input Monitoring
- Screen Recording

OAuth tokens are stored in Keychain. Document metadata is stored in `UserDefaults`. Access tokens and refresh tokens are not stored in plain text files.

## Google Cloud Setup

1. Create a Google Cloud project.
2. Enable the Google Drive API.
3. Enable the Google Docs API.
4. Configure the OAuth consent screen.
5. Add your test user if the app is in test mode.
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
- `drive.readonly`: support image loading and shared-drive document discovery.

## Build

Open the project in Xcode and build the `DocDesktop` scheme for `My Mac`.

Command-line build can also work from the repo root:

```zsh
xcodebuild -scheme DocDesktop -destination 'platform=macOS'
```

## GitHub Setup

Create an empty GitHub repo, then run:

```zsh
cd "/Users/evam/Desktop/XCode Dev/DocDesktop"
git init
git branch -M main
git add .
git commit -m "Initial DocDesktop app"
git remote add origin https://github.com/kickereb/DocDesktop.git
git push -u origin main
```

If `origin` already exists:

```zsh
git remote set-url origin https://github.com/kickereb/DocDesktop.git
git push -u origin main
```

## Editing Model

The current editor supports text-only saves.

The app:

- compares original text with edited text
- builds a small text edit
- maps the local text range to Google Docs UTF-16 indexes
- saves with `documents.batchUpdate`
- uses `targetRevisionId` write control

The app blocks edits that touch unsupported content. This prevents data loss.

Unsupported for save:

- images
- tables
- checkboxes
- drawings
- smart chips
- edits across multiple tabs

## Sync Rules

The app must not overwrite local work.

Rules:

- Remote reload is allowed only when there are no unsaved local edits.
- Refresh is blocked when local edits are unsaved.
- If save fails because the remote document changed, local text stays in the editor.
- The user must resolve the conflict manually for now.

## Stage Plan

Completed:

- Stage 1: desktop widget shell
- Stage 2: Google OAuth
- Stage 3: Drive discovery
- Stage 4: read-only Docs loading
- Stage 5: text editing and save
- Partial Stage 6: safer remote reload

Next:

- Finish Stage 6: stronger conflict state and tests
- Stage 7: simple formatting shortcuts
- Stage 8: offline pending edits
- Stage 9: polish and settings

## Stage 7 Direction

Stage 7 should keep text edits only, then add simple formatting commands.

Suggested shortcuts:

- `# Text` for Heading 1
- `## Text` for Heading 2
- `- Text` for bullet list
- `1. Text` for numbered list
- `[ ] Text` for checkbox later
- `[Label](https://example.com)` for link later

These should become Google Docs formatting API requests. The app should not convert the whole document to Markdown.

## Main Files

- `DocDesktopApp.swift`: app entry point
- `AppDelegate.swift`: menu bar item and shortcut connection
- `GlobalHotKeyManager.swift`: `Option-D` shortcut
- `DesktopWindowController.swift`: widget window setup
- `WidgetWindow.swift`: key-capable custom panel
- `GoogleAuthManager.swift`: Google OAuth
- `DriveService.swift`: Drive discovery
- `GoogleDocsService.swift`: Docs load and save
- `GoogleDocsParser.swift`: Docs API parsing
- `GoogleDocsIndexMapper.swift`: UTF-16 edit mapping
- `DocumentContentViewModel.swift`: editor load, save, and sync state
- `MacAttributedTextView.swift`: AppKit text editor bridge

## Known Limits

The current app is useful for simple text edits, but it is not a full Google Docs editor.

Use `Open in Google Docs` for complex document work, such as heavy formatting, tables, comments, suggestions, and image edits.
