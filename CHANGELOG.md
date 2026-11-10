# Changelog

## 0.7.0 — 2026-11-10

- Replaced note color shortcut with a common frameless three-dot actions menu, matching group actions. Included color changes and checkbox add/remove actions.
- Added a lighter, smaller Lucide `circle-plus` quick-add control to each expanded group; creates an unchecked checkbox note in that group.
- Unified note and group action geometry using the shared right-alignment guide. Corrected text-edit field width and removed previous-frame menu coordinate coupling.
- Replaced the custom note-font slider with the same native ReaImGui slider type used by note spacing; standardized unit text to `px` in both locales.
- Made a timecode badge click move the edit cursor and focus the arrange context for immediate Space playback.
- Balanced native ImGui Begin/End and BeginChild/EndChild lifecycles, stabilized menu hitboxes and identifiers, and corrected nonadjacent note reordering while preserving unrelated note order.
- Centralized remaining UI geometry settings, removed dead UI paths, retained compatibility with document format v3 and existing owner storage identifiers.

The previously existing v0.6.3 is not overwritten by this source package. v0.7.0 is based on the user-accepted v0.6.2-dev.4 audit build.
