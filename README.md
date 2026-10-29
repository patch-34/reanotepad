# ReaNotepad

**English** · [Русский](README_RU.md)

**Version 0.5.0** · A Lua ReaScript by Aleksei Vorobev / Patch34.

Organize REAPER project, track and item notes into tabs and resizable columns. Add text blocks, multiline notes with completion checkboxes, and dropdown fields with editable choices. Notes are stored with the REAPER project. Earlier names were ReaNotebook and Patch34 Project Notes.

![ReaNotepad in REAPER](assets/screenshot.png)

## Requirements and installation

- REAPER 7 or newer.
- ReaImGui 0.10 or newer, available through [ReaPack](https://reapack.com/).

SWS is not required. The script runs from one Lua file.

1. Install ReaImGui through ReaPack. Restart REAPER if prompted.
2. Extract the archive and copy `ReaNotepad_v0.5.0.lua` into a permanent folder, such as `Scripts` in the REAPER resource directory. Open that directory through **Options → Show REAPER resource path in explorer/finder**.
3. Open **Actions → Show action list**, select the Main section, then **New action → Load ReaScript** and select the Lua file.
4. Run the script. Assign a shortcut or toolbar button in the Action List if needed.

When updating, stop the older script first. If its filename has changed, load the new file and update shortcuts or toolbar assignments that point to the old action. Run only one version at a time. Documentation is not needed at runtime.

## Where notes are stored

Choose **Project / Track / Item** at the top. Track and Item follow the REAPER selection and require exactly one selected object. The master track is supported. Every object has its own document and Undo/Redo history.

| Mode | Storage |
| --- | --- |
| Project | Native project notes |
| Track | Track extension data (`P_EXT:PATCH34_PROJECT_NOTES`) in the `.rpp` project |
| Item | Native item notes (`P_NOTES`) |

Edits update the open project immediately. **Save the REAPER project to keep them on disk.** Track notes are independent of SWS Track Notes. Normal editing creates no separate note files; error recovery can create copies as described below.

Existing plain notes appear as a text block. Opening them does not rewrite the original text. The first edit saves a structured document with readable text and structural markers. Keep those markers intact when using another notes editor. Earlier v1 documents are read without modification and converted on edit. Version 0.5.0 keeps the v2 storage format used by 0.4.x. The rename preserves existing note fields, settings and recovery paths; their internal Patch34 identifiers remain for compatibility.

## Edit and organize

Enable **Edit** to edit text and expose column controls. Turn it off for wrapped reading. Checkboxes and dropdown choices remain interactive in either mode.

- The **Tab** menu adds, renames, reorders and deletes tabs. Right-click any tab for **Delete tab…**; deletion asks for confirmation and can be undone. The last remaining tab cannot be deleted. Double-click a tab to rename it in place: Enter or a click outside applies; Esc cancels.
- **Add → Column** adds a column, up to eight per tab. Drag column boundaries to redistribute width. Double-click a column name to rename it in a dialog.
- Each column's **Add** menu inserts blocks into that column. The main **Add** menu offers a column choice when needed.
- A block's **…** menu moves it up/down, moves it to another column, edits a dropdown field, or deletes the block.

| Block | Use |
| --- | --- |
| Text | A multiline text block |
| Note with checkbox | A multiline task or note with a completion checkbox |
| Dropdown | A named field with editable choices |

The separate Checkbox creation command has been removed. Checkbox blocks saved by older versions remain supported.

Use **Edit…** beside a dropdown’s properties button, or **… → Edit field…** to change its name, add or reorder options, and set the selected value. Apply a dialog to save its draft; Esc or a click outside cancels it. Switching to another project, track or item also cancels unapplied dialogs and inline tab renames.

## Import text

Choose **Edit → Import text…**, or **Import text…** in a column's Add menu. In the landscape dialog, choose the destination column and numbering option at the top left; the hints use the standard interface text size on the right, with extra space before the panel headings. The shorter dialog keeps Import and Cancel close below the panels. Paste text in the lower-left field and review the resulting notes in the equally sized panel on the right. Its grey empty-state message is a hint, not an editable field. Click **Import** to add the notes.

- Blank lines separate paragraphs. Recognized list entries can contain continuation lines.
- Without blank lines or recognized numbering, each nonempty line becomes a note.
- Markers include `1.`, `2)`, `(3)`, `[4]`, `5:`, `6 —` and dotted forms such as `1.2.` when followed by whitespace and text.
- Bare numbers such as `1 First` and `2 Second` require a consecutive sequence. Isolated numbers, years, dates and decimal values are treated conservatively to avoid removing ordinary text.
- **Remove numbering** is enabled by default; disable it to keep prefixes.

Preview the result before importing. Imported paragraphs become unchecked notes appended to the selected column. One Undo removes the whole import.

## Appearance and language

**Hide completed** hides checked notes and older checkbox blocks without deleting them. Turn it off to show them again.

The **Font** slider controls note text size from 12 to 32 pixels. Interface text uses the default UI font independently. **View** offers Pages, REAPER Grey, Google Docs White and Dark themes. Choose **View → Language → English / Русский** to change the interface language; note contents and user-defined names are unchanged.

Right-click the top toolbar and choose **Dock to docker** to dock or undock. The script remembers its last docker. **Help → About…** shows the version and author link. **Help → Help…** opens the [ReaNotepad repository](https://github.com/patch-34/reanotepad). The About window fits its text and has a Close button on the right. The current project name is shown in the window title.

## Undo and Redo

Use **Edit → Undo / Redo**. Menu entries name the next action, such as typing, pasting, importing or renaming.

| Action | Windows / Linux | macOS |
| --- | --- | --- |
| Undo | Ctrl+Z | Cmd+Z |
| Redo | Ctrl+Shift+Z or Ctrl+Y | Cmd+Shift+Z or Cmd+Y |

Text edits participate in document history. Consecutive typing or deletion in the same field is grouped while edits are less than 0.8 seconds apart. Moving the caret or selection, changing fields, pasting, cutting, replacing a selection or inserting a line break separates edits into steps. Adding, deleting, moving and renaming content, checking notes and choosing dropdown values also enter history.

Dialog drafts use their own text-editing history. Applying a dialog records the resulting document change. Theme, font size, language, the completed-note filter and Edit mode are preferences, outside document Undo/Redo.

History belongs to each project, track or item and lasts for the current script session. Switching objects preserves it, including when an inactive document is unloaded from memory. Restarting the script or loading an external change resets the affected history. Each Undo/Redo stack is limited to 100 entries and approximately 16 MiB, while retaining at least its newest entry.

## Recovery and external edits

Malformed or unsupported structured notes open read-only. The script reloads external note edits when it has no pending local changes; it reports conflicting changes instead of silently overwriting them. Writes validate the target object and check the stored contents.

On errors, the script attempts to save separate recovery files under:

`<REAPER resource directory>/Data/Patch34_Project_Notes_Recovery/`

Copies may include the original notes, the local draft, an attempted write, pending dialog text and a diagnostic report. An error does not trigger an emergency overwrite of native notes. Recovery files may contain an incomplete operation: inspect them before restoring.

Choose **Edit → Open recovery copy…**, select a `.notes` file, review the preview and explicitly restore it into the currently selected note owner. Restoration is undoable. Recovery copies are local files and can contain your note text.

## Limits and validation

- Long lines wrap in Read mode; native Edit fields scroll horizontally.
- Column width proportions are session state, not part of the stored document.
- History is not saved across script restarts. Very large documents and histories can still consume substantial memory.
- Older versions predating 0.4.0 cannot read multiline checkbox-note blocks.
- All 18 automated test suites pass against the 0.5.0 script. They use Lua and simulated REAPER/ReaImGui APIs. Manual REAPER testing was reported successful for 0.4.13; the later session optimization and final UI revisions were checked automatically. No platform/version compatibility matrix has been recorded.

See [CHANGELOG.md](CHANGELOG.md), [release notes](RELEASE_NOTES.md) and the [release checklist](docs/RELEASE_CHECKLIST.md).

## Credits

Author: [Aleksei Vorobev / Patch34](https://github.com/patch-34).

MIT license
