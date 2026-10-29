# ReaNotepad

**English** · [Русский](README_RU.md)

**Version 0.5.4** · [Downloads](https://github.com/patch-34/reanotepad/releases) · [Changelog](CHANGELOG.md)

ReaNotepad is a structured notes editor for REAPER projects, tracks and items. Documents contain tabs, resizable columns, text blocks, checkbox notes and dropdown fields. Notes are stored in the REAPER project.

![ReaNotepad in REAPER](assets/screenshot.png)

## Requirements

| Component | Version |
| --- | --- |
| REAPER | 7 or later |
| ReaImGui | 0.10 or later |

ReaImGui is available through [ReaPack](https://reapack.com/).

## Installation

1. Install ReaImGui through ReaPack.
2. Download the release archive and extract `ReaNotepad_v0.5.4.lua` to the REAPER `Scripts` directory. The resource directory is available under **Options → Show REAPER resource path in explorer/finder**.
3. Open **Actions → Show action list** and select the **Main** section.
4. Select **New action → Load ReaScript**, then open `ReaNotepad_v0.5.4.lua`.
5. Select the registered action and click **Run**.

## Documents and storage

The selector in the top toolbar sets the note scope.

| Scope | Note owner | Storage |
| --- | --- | --- |
| Project | Current project | Native project notes |
| Track | One selected track, including the master track | Track extension data in the `.rpp` file |
| Item | One selected item | Native item notes |

Track and Item modes follow the REAPER selection. Each owner has an independent document and Undo/Redo history.

Edits are written to the open project. Save the REAPER project to persist them to disk.

Existing plain-text notes are displayed as a text block. Opening notes does not change their contents. The first edit converts plain text to the structured notes format.

## Tabs, columns and blocks

A document contains tabs. Each tab supports up to eight columns.

| Operation | Control |
| --- | --- |
| Create, rename, reorder or delete tabs | **Tab** menu |
| Rename a tab inline | Double-click the tab |
| Delete a specific tab | Right-click the tab → **Delete tab…** |
| Add a column | **Add → Column** |
| Resize columns | Drag the divider between columns |
| Rename a column | Double-click its name, or **… → Rename column…** |
| Move or delete a column | Column **…** menu |

For inline tab renaming, Enter or a click outside the field applies the name; Esc cancels. The last tab cannot be deleted. Column width proportions are retained for the current session.

The icons in each column heading create or import blocks in that column. Hovering over an icon displays its action name.

| Action | Result |
| --- | --- |
| Text | Multiline text block |
| Note with checkbox | Multiline note with a completion checkbox |
| Dropdown | Named field with editable options |
| Import text | Text import dialog |

The top-level **Add** menu provides the same block types. A block's **…** menu contains movement, color and deletion commands.

### Editing

Enable **Edit** in the top toolbar to edit text and display column controls. With Edit disabled, text is displayed with word wrapping. Completion checkboxes and dropdown values remain interactive in both modes. Text-editing fields use horizontal scrolling.

For dropdown configuration, select **Edit…** beside the field name or **… → Edit field…**. The dialog supports renaming the field, editing and reordering options, and setting the selected value.

**Apply** commits a dialog. Esc or a click outside cancels it. Changing the note owner cancels unapplied dialogs and inline tab renaming.

## Multiple selection

1. Enable **Edit**.
2. Open the column's **… → Select elements…** menu command.
3. Click blocks to select or deselect them. Selected blocks display an outline and a corner check mark.
4. Use the selection toolbar to apply an operation.

| Control | Function |
| --- | --- |
| All / Clear selection | Select or deselect all visible blocks in the column |
| Color… | Assign or remove a color marker |
| Delete… | Delete selected blocks after confirmation |
| Done | Exit selection mode |

Block contents are read-only during selection. Each bulk deletion or color assignment is a single Undo/Redo operation. In narrow columns, toolbar controls wrap or use icons with tooltips.

Enabling **Hide completed** removes newly hidden blocks from the selection. Selection is cleared by changing the owner or tab, loading external note changes, using Undo/Redo, or leaving Edit mode. Esc exits selection mode; when a deletion confirmation is open, it cancels that dialog first.

## Color markers

For an individual block, use **… → Color marker**. For multiple blocks, use **Color…** in the selection toolbar.

Available markers: red, orange, yellow, green, blue and purple. **No marker** removes the marker. Colors are not assigned fixed priority values.

A marker is displayed as a narrow strip at the left edge of the block. The text and background retain their standard colors. Marker changes are saved with the document and support Undo/Redo.

## Text import

Open **Edit → Import text…** or select the import icon in a column heading.

1. Select the destination column.
2. Paste source text into the left field.
3. Set **Remove numbering** and review the result in the right pane.
4. Select **Import**.

Imported entries are appended as unchecked notes. The complete import is one Undo/Redo operation.

Parsing rules:

- Blank lines separate paragraphs. Numbered list entries may include continuation lines.
- Without blank lines or recognized numbering, each nonempty line becomes a separate note.
- Supported markers include `1.`, `2)`, `(3)`, `[4]`, `5:`, `6 —` and compound forms such as `1.2.`.
- Numbers without punctuation require a consecutive sequence. Isolated numbers, years, dates and decimal values are retained when not recognized as list numbering.
- **Remove numbering** is enabled by default.

## View and language

| Setting | Function |
| --- | --- |
| Hide completed | Hide completed checkbox notes without deleting them |
| Font | Set note text size from 12 to 32 px |
| View → theme | Select Pages, REAPER Grey, Google Docs White or Dark |
| View → Language | Select English or Russian |
| Toolbar context menu → Dock to docker | Dock or undock the window |

Interface font size is independent of note text size. Language changes apply to interface controls; document text and user-defined names are preserved.

## Undo and Redo

The **Edit** menu displays the next Undo and Redo actions.

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Undo | Ctrl+Z | Cmd+Z |
| Redo | Ctrl+Shift+Z or Ctrl+Y | Cmd+Shift+Z or Cmd+Y |

History includes text edits, structural changes, completion states, dropdown selections, imports, color markers and restoration. Consecutive typing or deletion in the same field is grouped with a pause threshold of approximately 0.8 seconds. Caret movement, selection changes, paste, cut, replacement and line breaks separate editing operations.

History is maintained independently for each note owner during the script session. Each stack retains up to 100 entries, subject to an approximate 16 MiB limit. Restarting the script or loading external changes resets the relevant history. Appearance settings are not included in document history.

## Recovery

Malformed or unsupported structured notes are opened read-only. External changes are loaded when no local edits are pending. Conflicting changes suspend writing and display a diagnostic message.

The recovery directory is:

```text
<REAPER resource directory>/Data/Patch34_Project_Notes_Recovery/
```

Recovery files may include original notes, the local draft, pending dialog text and a diagnostic report.

To restore notes, select **Edit → Open recovery copy…**, open a `.notes` file, review the preview and select **Restore**. The copy replaces the current owner's document. Restoration supports Undo/Redo.

## Format compatibility

- Storage format: v2. Version v1 documents are converted on edit.
- Color markers use optional `@color` directives. Versions through 0.5.3 open documents containing these directives read-only. Remove all markers in 0.5.4 before editing the document with an earlier version.
- Legacy checkbox blocks remain supported.
- Internal Patch34 storage keys are retained for compatibility with existing notes and settings.

## License and credits

Author: [Aleksei Vorobev / Patch34](https://github.com/patch-34).

ReaNotepad is distributed under the [MIT License](LICENSE).

Interface: [ReaImGui](https://github.com/cfillion/reaimgui). Icons: [Lucide](https://lucide.dev/). Third-party icon licenses are included in [LUCIDE_LICENSE.txt](docs/licenses/LUCIDE_LICENSE.txt).

