# ReaNotepad

**English** · [Русский](README_RU.md)

ReaNotepad is a single-file Lua notes editor for REAPER projects, tracks, and media items. Organize editing lists, production notes, task checklists and status fields into horizontal tabs and collapsible groups. Changes are stored in the REAPER project, not in separate working documents.

<p align="center"><img src="https://raw.githubusercontent.com/patch-34/reanotepad/main/assets/screenshot.png" alt="ReaNotepad in REAPER" width="550"></p>

## Requirements and installation

- **REAPER 7+** and **ReaImGui 0.10+**. Install ReaImGui using [ReaPack](https://reapack.com/). SWS is not required.
- Save `ReaNotepad.lua` to your REAPER `Scripts` directory. Use **Options → Show REAPER resource path** to locate it.
- In **Actions → Show action list**, choose the **Main** section, then **New action → Load ReaScript**, choose `ReaNotepad.lua`, and run the action.
- When updating, **replace the existing `ReaNotepad.lua` without renaming it**. This preserves registered REAPER actions, shortcuts and toolbar assignments.

The [Patch34 ReaPack repository](https://raw.githubusercontent.com/patch-34/patch34-reapack/main/index.xml) is maintained separately and may show a different version until its index is updated.

### Docking and resizing (v0.7.1)

Version 0.7.1 fixes a ReaImGui window-scope crash that could occur when moving ReaNotepad between Docker positions or undocking it. It also guards note layout calculations against negative available width in very narrow dock panels. To upgrade, replace the existing `ReaNotepad.lua` at the same path.

## Documents and storage

| Scope | Owner | Storage |
| --- | --- | --- |
| Project | Current REAPER project | Native project notes (`GetSetProjectNotes`) |
| Track | Exactly one selected track, including master | `P_EXT:PATCH34_PROJECT_NOTES` in the `.rpp` project |
| Item | Exactly one selected media item | Native `P_NOTES` |

Use the scope selector in the toolbar. Each owner has its own document and script-session Undo/Redo. Save your REAPER project to persist edits to disk. Existing plain-text notes are read without rewriting them until you make an edit.

The editor supports up to eight horizontal tabs per document. Each tab contains collapsible, independently named **groups** with text notes, checkbox notes and named dropdown lists. Reorder tabs and notes by dragging. Move notes between groups via drag-and-drop or the actions menu.

## Creating and editing notes

- Use the top toolbar or **Add** menu for text notes, checkbox notes, dropdowns and text import. Click an icon and select a group, or drag it onto a group.
- Use the light **circle-plus** icon at the bottom of an expanded group to create an unchecked checkbox note directly in that group.
- Open a note's frameless **…** menu to edit its actions, set or clear a color marker, add/remove its checkbox when applicable, move it or delete it. Group headings use the same three-dot visual style and alignment.
- Click text to edit in place: **Enter** saves, **Shift+Enter** inserts a newline, **Esc** prompts before discarding changed text. Clicking outside applies the edit.
- Click a checkbox to toggle completion; click a dropdown value to select it. The dropdown's **…** menu provides its editing options.
- The six-dot handle moves a note. Dragging to the top toolbar's trash target removes it. Deletion and bulk changes are covered by Undo/Redo as appropriate.
- Group **…** actions include renaming, group color, moving up/down, inserting another group, multi-selection, and deletion. The final group in a tab cannot be deleted.

## Selection and appearance

Group **… → Select elements…** enables selecting multiple visible notes. The selection toolbar can select all, clear, recolor or delete. It does not change note ownership or completion flags.

**View** settings include hiding completed notes, displaying completed notes last, colored left strips versus whole-note tint, separator spacing (0–24 px, default 5 px), four interface themes (Pages, REAPER Grey, Google Docs White and Dark), and English/Russian language. Note font size is 12–32 px. Font size and separator spacing use native ReaImGui sliders, displaying `px` in both languages. Appearance settings are not part of document Undo history.

## Import and timecodes

Choose **Edit → Import text…**. Paste a text or numbered list, choose its target group and review the preview. Options include **Remove numbering** and **Split at timecodes**. Import is a single Undo operation. Recognized numbering includes `1.`, `2)`, `(3)`, `[4]`, `5:`, `6 —`, and hierarchical numbering.

Leading timecodes in notes are recognized independently of the import splitting option:

| Input | Interpretation |
| --- | --- |
| `01:45` | MM:SS |
| `00:00:12` | HH:MM:SS |
| `00:01:35:04` | HH:MM:SS:FF at the current project frame rate |
| `00:01:35.250` | Time with milliseconds |

**Single-click the timecode badge** to move the REAPER edit cursor and focus the arrange context, so the Space key can start playback. The project start-time offset is respected. Four-field timecodes use the project's FPS and drop-frame setting. The original text remains unchanged.

## Undo, recovery and compatibility

Undo/Redo supports text edits, checkboxes, dropdowns, imports, colors, tab/group changes, note moves and recovery restoration. Each owner has a separate history, limited to 100 entries or approximately 16 MiB per stack. Short consecutive typing can be grouped. History does not persist across script restarts.

If native notes change externally during an edit, automatic writes pause rather than overwrite them. Invalid or unknown structured formats open read-only. Inspect recovery files under `Data/Patch34_Project_Notes_Recovery/` and restore using **Edit → Open recovery copy…**.

**Version 0.7.1 continues to write document format v3** (`# Patch34 Project Notes v3`). Legacy v1/v2 documents and plain project notes remain readable. Track storage keys, preference keys, window identifiers and recovery paths have *not* been renamed. Older scripts may not edit documents saved in v3.

## License and credits

Copyright © 2026 Aleksei Vorobev / [Patch34](https://github.com/patch-34). Licensed under [MIT](LICENSE). Uses [ReaImGui](https://github.com/cfillion/reaimgui) and [Lucide](https://lucide.dev/) icons; see [third-party notices](docs/licenses/LUCIDE_LICENSE.txt).
