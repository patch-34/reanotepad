# Changelog

## 0.5.4 — 2026-10-29

### Documentation

- Rewritten English and Russian user manuals.
- Added the project MIT license and the repository screenshot to the release package.

### Added

- Column properties → Select elements: full-block selection, visible-only All/Clear, color assignment and confirmed bulk deletion.
- Single-block and bulk color markers in six preset colors, displayed as a narrow strip at the left edge while keeping the normal block background.
- Named, single-step Undo/Redo for bulk deletion and marker assignment.
- Compact Lucide icon fallbacks for selection actions in narrow columns.

### Storage and selection

- Color keys are saved as optional @color directives in storage v2. Existing uncolored notes keep the same serialization. Versions through 0.5.3 open documents containing markers read-only; remove all markers with 0.5.4 before downgrading.
- Selection is temporary and local to one column. Hidden completed blocks are pruned from it. Selection clears on owner/tab changes, Undo/Redo, leaving Edit mode and external document replacement.
- Selection mode displays block contents without editable fields, checkboxes or active dropdowns. Done or Esc exits; Esc first cancels an open deletion confirmation.

## 0.5.3 — 2026-10-29

### Changed

- Made action symbols distinct: square-check for checkbox notes, list-chevrons-down-up for dropdowns, and file-input for import.
- Replaced the import tray/down-arrow with an arrow entering a document.
- Kept button order, actions, tooltips, sizing and stroke weight unchanged.

## 0.5.2 — 2026-10-29

### Changed

- Replaced custom quick-action drawings with Lucide type, list-todo, square-chevron-down and import icons.
- Used a lighter 1.5 px source stroke, embedded high-resolution masks and theme-aware tinting. Installation still requires only the Lua file.
- Included original SVG sources and third-party icon licenses.

## 0.5.1 — 2026-10-29

### Changed

- Replaced each column's Add menu button with quick actions for text, checkbox notes, dropdowns and text import.
- Added English/Russian hover tooltips. Icon buttons use the existing button styling and text color.
- Wrapped column actions when space is limited and retained identical header geometry in Read and Edit modes.
- Kept the top-level Add menu and column properties menu.

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
