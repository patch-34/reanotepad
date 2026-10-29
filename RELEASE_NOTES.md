# ReaNotepad v0.5.0

## English

Organize REAPER project, track and item notes into tabs and resizable columns, with text blocks, checkbox notes and editable dropdowns. Notes stay with the project.

Previously named Patch34 Project Notes, the script is now **ReaNotepad**. Existing notes and settings remain compatible.

Version 0.5.0 brings the UI and reliability changes developed since 0.4.0:

- Podcast Viewer styling, consistent compact controls, clearer Dark-theme tabs and corrected menu/popup sizing.
- English/Russian interface, a compact About window and a Help link to [the repository](https://github.com/patch-34/reanotepad).
- Landscape import with controls at the top left and standard-size hints at the top right; equally aligned source and preview fields below, with muted empty-preview text.
- Stable document UI identifiers on language changes and a short transparent startup layout phase.
- Right-click tab deletion, consistent dialog backgrounds and a fix for the extra scrollbar during tab renaming.
- Named Undo/Redo actions that include text editing, with typing and deletion grouped into steps.
- Recovery copies and previewed restoration, without emergency overwrites of native notes.
- More conservative numbered-list import and lower memory use for inactive documents.
- Fixes for the tab-renaming crash and brief narrow-column frames during UI changes.

Requires **REAPER 7+ and ReaImGui 0.10+**. Extract the archive and load `ReaNotepad_v0.5.0.lua` through **Actions → Show action list → New action → Load ReaScript**. Stop the previous version before updating. Save the REAPER project to keep notes on disk. Storage remains compatible with 0.4.x; no manual conversion is needed.

All 18 automated suites pass on 0.5.0 using Lua and simulated host APIs. Manual REAPER testing was reported successful for 0.4.13; the subsequent session optimization and final UI revisions have automated coverage. Cross-platform host compatibility has not been certified.

See [README.md](README.md) for installation, history behavior and recovery details.

## Русский

Заметки к проектам, дорожкам и айтемам REAPER с вкладками, колонками изменяемой ширины, текстом, заметками с чекбоксами и редактируемыми списками. Заметки сохраняются вместе с проектом.

Теперь скрипт называется **ReaNotepad**; прежнее название — Patch34 Project Notes. Существующие заметки и настройки совместимы с новой версией.

Версия 0.5.0 объединяет изменения интерфейса и надёжности, сделанные после 0.4.0:

- Оформление Podcast Viewer, согласованные компактные кнопки, более заметные активные вкладки в тёмной теме и исправленные размеры меню и диалогов.
- Русский и английский интерфейс, компактное окно информации о программе и переход из справки в [репозиторий](https://github.com/patch-34/reanotepad).
- Горизонтальное окно импорта: настройки сверху слева, подсказки стандартного размера справа, под ними два поля одной высоты. Подсказка в пустом предпросмотре приглушена.
- Сохранение элементов документа при смене языка и короткая скрытая подготовка разметки при открытии.
- Удаление вкладки по правому щелчку, единый фон диалогов и исправление лишней прокрутки при переименовании вкладки.
- Подписанные действия отмены/повтора, включая ввод и удаление текста с объединением последовательных правок.
- Аварийные копии и восстановление с предпросмотром, без аварийной перезаписи стандартных заметок.
- Более осторожное распознавание нумерации при импорте и освобождение памяти неактивных документов.
- Исправления падения при переименовании вкладки и краткого появления узких колонок при изменениях интерфейса.

Нужны **REAPER 7+ и ReaImGui 0.10+**. Распакуй архив и загрузи `ReaNotepad_v0.5.0.lua` через **Actions → Show action list → New action → Load ReaScript**. Перед обновлением останови старую версию. Сохраняй проект REAPER, чтобы записать заметки на диск. Формат совместим с 0.4.x, ручное преобразование не требуется.

Все 18 наборов автоматических тестов проходят на 0.5.0 с Lua и имитацией API хоста. Для 0.4.13 подтверждена успешная ручная проверка в REAPER; последующая оптимизация сессий и финальные правки интерфейса покрыты автоматическими тестами. Совместимость на всех платформах не подтверждалась.

Установка, работа истории и восстановление описаны в [README_RU.md](README_RU.md).
