# DocDesktop Manager Stage Progress

Date: 2026-09-13

## 1. Executive Summary

DocDesktop started as a desktop widget for one Google Doc. That path proved technically fragile because editable macOS text surfaces need reliable focus, activation, scrolling, keyboard input, and window ordering.

The product direction changed to a shortcut-first local Markdown note overlay with optional Google Docs backing.

This is now the recommended product shape:

> Press `Command + Shift + D`, edit a local Markdown note, hide it, and optionally sync safe changes to Google Docs later.

The current priority is to make local note-taking excellent before reconnecting Google write sync.

## 2. Original Stage Progression

The original plan moved in these broad stages:

1. Desktop widget window.
2. Google OAuth.
3. Google Drive document picker.
4. Google Docs loading.
5. Basic text editing and save.
6. Safer sync and conflict handling.
7. Formatting support.
8. Offline / local draft behavior.
9. Polish and release readiness.

Some of those stages are complete, but the product direction changed after Stage 6 and early Stage 7 exposed too much risk in the Google Docs sync model.

## 3. Current Stage Status

| Stage | Status | Notes |
|---|---:|---|
| Stage 1: macOS window shell | Complete but superseded | The old desktop widget behavior is no longer the target. |
| Stage 2: Google OAuth | Mostly complete | Sign-in, callback, token storage, and refresh infrastructure exist. |
| Stage 3: Drive discovery | Mostly complete | My Drive, Shared with me, Shared Drives, and URL paste support exist. |
| Stage 4: Google Docs loading | Partly complete | Text, some formatting, and images can load through the Google Docs path. |
| Stage 5: Basic text save | Partly complete | Simple text save exists, but it is too limited for production use. |
| Stage 6: Sync safety | Paused | Some safe reload and revision logic exists, but robust conflict handling is not done. |
| Stage 7: Formatting | Re-scoped | Formatting should now be built through local Markdown semantics first. |
| Stage 8: Offline/local mode | Active | Local Markdown development mode is now the main working path. |
| Stage 9: Polish | Not started | Needs stable editor, local notes, settings, and packaging first. |

## 4. Work Completed So Far

### macOS shell

Complete:

- Menu-bar app.
- Global shortcut.
- Overlay window model.
- Escape-to-hide behavior.
- Window size and position persistence.
- Reliable editor focus improvements.
- Removal of old always-on-desktop behavior from the active product direction.

Recent fix:

- `Command + Shift + D` now toggles instead of immediately reopening the overlay.

### Google backend

Complete or useful:

- Google OAuth.
- Keychain token storage.
- Drive file discovery.
- Google Docs URL parsing.
- Google Docs document loading.
- Google Docs batch update path.
- UTF-16 range mapper.
- Revision-aware write control.

Paused:

- Google write sync is intentionally paused while the local editor stabilizes.

### Local Markdown editor

Complete:

- Local scratch note without Google sign-in.
- Local draft save.
- Markdown heading styling.
- Bold, italic, bold plus italic, strikethrough.
- Links.
- Bullet and numbered list styling.
- Checkbox marker styling.
- Block quotes.
- Inline code.
- Code blocks.
- Horizontal rules.
- Return continues list items.
- Empty list item exits the list.
- Tab and Shift-Tab indentation behavior.
- Checkbox click toggling.
- Markdown image preview strip.
- Scroll jump fix for typing stability.

## 5. Important Product Decision

The app should not be a miniature Google Docs client.

The recommended direction is:

```text
Local Markdown note app first
Optional Google Docs backing second
Full Google Docs fidelity not a goal
```

Reason:

- Google Docs has strict UTF-16 indexes.
- It has non-text objects such as images, tables, smart chips, equations, drawings, headers, and footers.
- It has revision and paragraph boundary rules.
- A direct Google Docs editor can corrupt content if sync is not structure-aware.

Local-first editing gives us a safe, fast product while keeping Google Docs as an optional remote layer.

## 6. Current Product State

DocDesktop is now usable as a local overlay Markdown note editor.

The user can:

- Open the overlay with `Command + Shift + D`.
- Type into a local Markdown note.
- Use Markdown syntax with visual styling.
- Continue lists with Return.
- Indent and outdent list items.
- Toggle checkbox markers.
- Preview Markdown images.
- Hide the overlay.
- Continue later with the local draft.

This is the first real product spine.

## 7. Current Known Issues

Known risks or unfinished areas:

- There is still only one main local scratch note.
- There is no multi-note local store yet.
- There is no note switcher or note search yet.
- Markdown image previews are shown below the editor, not inline.
- Google sync is paused.
- Google formatting sync is not production-ready.
- Xcode workspace UI state has been committed before and should be ignored later.
- The old class names `DesktopWindowController` and `WidgetWindow` remain even though the product is no longer a widget.

## 8. Recommended Next Stages

### Stage A: Local editor stability

Goal:

Make the local editor feel reliable.

Tasks:

- Confirm no scroll jumps with long notes.
- Confirm undo and redo.
- Confirm paste behavior.
- Confirm Tab and Shift-Tab on multi-line selections.
- Confirm checkbox clicks do not move scroll position.
- Add tests for editing commands where possible.

Exit criteria:

- The editor feels stable for normal note-taking.

### Stage B: Multiple local notes

Goal:

Move beyond one scratch note.

Tasks:

- Add `Note` model.
- Add local note store.
- Save notes atomically.
- Store title, body, created date, updated date, caret position, and scroll position.
- Add note switcher/search.
- Add new note command.

Exit criteria:

- User can create, switch, search, edit, and persist multiple local notes without Google.

### Stage C: Editor polish

Goal:

Make the editor feel closer to Antinote.

Tasks:

- Improve syntax dimming.
- Add `Command + [` and `Command + ]` indentation shortcuts.
- Add `Command + B`, `Command + I`, and `Command + K`.
- Improve image previews.
- Improve visual spacing.
- Add settings for shortcut and syntax visibility later.

Exit criteria:

- Local editing feels fast, predictable, and keyboard-first.

### Stage D: Google import

Goal:

Import a Google Doc into a local Markdown note safely.

Tasks:

- Convert Google Docs headings to Markdown headings.
- Convert bold, italic, strike, and links.
- Convert lists.
- Convert images to protected Markdown references or placeholders.
- Protect unsupported content.

Exit criteria:

- User can select a Google Doc and view a safe local Markdown version.

### Stage E: Safe Google text sync

Goal:

Sync only safe text edits.

Tasks:

- Track local text changes.
- Map local edits to Google Docs ranges.
- Use revision guards.
- Refuse edits that touch protected objects.
- Keep local draft if sync fails.

Exit criteria:

- Simple text changes can sync without data loss.

### Stage F: Formatting sync

Goal:

Map Markdown semantics to Google Docs formatting requests.

Tasks:

- Headings to `updateParagraphStyle`.
- Bold, italic, strike, links to `updateTextStyle`.
- Lists to `createParagraphBullets`.
- Do not upload Markdown syntax as formatting.

Exit criteria:

- Formatting sync is semantic and minimal.

## 9. Recommended Immediate Next Step

Do Stage A first.

Specifically:

1. Add `Command + ]` to indent.
2. Add `Command + [` to outdent.
3. Verify no scroll jumps during these commands.
4. Add tests for those commands.
5. Then start local multi-note storage.

This keeps the product on the local-first path and reduces risk before Google sync returns.

## 10. Management Recommendation

The project should be judged as a local-first note app now, not as a Google Docs clone.

Google integration is still a valuable differentiator, but it should be treated as a remote backing layer. It should return only after the local editor and local note model are stable.

Recommended milestone for the next demo:

> A fast overlay note app with multiple local Markdown notes, stable keyboard editing, list behavior, checkbox behavior, image preview, and no scroll jumps.

That milestone will show the product value without risking user Google Docs content.
