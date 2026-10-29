# Changelog

## 0.5.0 — 2026-10-29

Consolidates the 0.4.1–0.4.14 development updates. Storage remains v2; no document migration is required for 0.4.x notes.

### Added

- English/Russian interface switching and an About popup. Help opens https://github.com/patch-34/reanotepad.
- Right-click tab deletion with confirmation and Undo/Redo.
- Named Undo/Redo actions, including grouped typing and deletion, with boundaries for caret movement, selection changes, paste, cut and line breaks.
- Local error-recovery copies with previewed, undoable restoration.

### Changed

- Sized About to its contents and aligned Close to the right.
- Removed the embedded development changelog from the release Lua; version history remains in this file.

- Moved dropdown Edit buttons beside properties at the right of the field heading, using the same height and spacing as column Add controls.

- Renamed the script from ReaNotebook to ReaNotepad, preserving existing storage, preferences and recovery compatibility.
- Split the import header into controls on the left and standard-size hints on the right, separated from the panel headings by an extra gap. Reduced the preferred height to 440 px and removed excess space between the panels and action buttons. Shared table rows align the input and preview panels; the empty preview uses muted text.
- Kept document UI identifiers stable when changing language and added two transparent startup layout frames before showing the complete window.

- Reoriented import into a landscape dialog: source text on the left, preview on the right, with shorter instructions.
- Removed repeated deletion wording and unintended backgrounds behind dialog text in every theme.
- Removed the link instruction caption from About.
- Applied the Podcast Viewer UI components and palette; unified button dimensions, corners, spacing and theme definitions.
- Used the default interface font independently of note text size; aligned compact Add and properties buttons.
- Removed the plus sign from Add and the redundant standalone Checkbox creation command. Existing checkbox blocks still work.
- Made selected Dark-theme tabs lighter and tightened menu shortcut spacing.
- Made import numbering recognition more conservative for numeric prose, years and dates.
- Distributed inactive-session validation across frames and released inactive document models while keeping per-owner history.

### Fixed

- Import dialog crash when passing the empty-preview hint color to ReaImGui; color values are explicitly limited to one return value.
- Inline tab-renaming crash caused by layout cursor positions.
- Parent-window scrollbar caused by submitting the tab rename overlay after full-height content.
- Excess empty space in menus and oversized delete confirmations.
- Popup content and action placement in small windows.
- Brief narrow-column frames after switching tabs, themes or Undo/Redo.
- Error handling that could attempt an emergency write to native notes; recovery now uses separate copies.

### Release package

- Updated English and Russian READMEs, each with a screenshot placeholder.
- Added bilingual release notes and an updated validation/handoff checklist.
- All 18 automated suites pass against 0.5.0. Host checks and their limits are recorded in the checklist.

## 0.4.0

### Added

- Multiline notes with completion checkboxes.
- A top-level Hide completed filter for checked tasks and checkbox notes.
- Dark theme.
- Text import with paragraph/list detection, numbering removal, preview and destination-column selection.
- Right-click toolbar action to dock/undock the window and remember the last docker.
- A font-size slider in the top toolbar.

### Changed

- Reduced padding, spacing and minimum text-field height.
- Imported notes are appended as one undoable edit.
- The existing v2 storage format accepts multiline `@note` blocks. Older script versions reject these blocks without overwriting the document.

## 0.3.0

- Added separate Project, Track and Item note modes.
- Added selection-following note ownership, including the master track.
- Added object-specific history and pointer/GUID validation before writes.
- Stored item notes in the native item field and track notes in track extension data.

## 0.2.2

- Fixed popup dimensions.
- Moved tab renaming onto the tab itself.
- Added Esc and outside-click cancellation for popup drafts.

## 0.2.1

- Added manually resizable columns that share the available window width.
- Corrected dropdown sizing and constrained it to narrow columns.
- Kept Undo/Redo in the Edit menu and keyboard shortcuts.
- Added a visible blinking text caret and double-click renaming.

## 0.2.0

- Added columns with separate widget menus.
- Added session Undo/Redo.
- Kept section dividers visible in Read mode.
- Introduced the v2 storage format with migration from v1.

## 0.1.0

- Initial project-note editor with tabs, text blocks, checkboxes and editable dropdowns.
- Native project-note storage with malformed-data and write-conflict guards.
