# ReaNotepad v0.5.4

## English

### Changes since 0.5.0

- Column headings provide quick-action icons for text, checkbox notes, dropdowns and import, with localized tooltips.
- Multiple selection supports confirmed bulk deletion and color assignment within a column. All/Clear operates on visible blocks only.
- Six color markers are available for individual or selected blocks. Markers appear as a narrow strip beside the content.
- Bulk deletion and marker changes support single-step Undo/Redo.
- Column controls and selection actions adapt to narrow columns.

### Requirements

REAPER 7 or later; ReaImGui 0.10 or later.

### Format compatibility

Uncolored documents retain their existing storage format. Color markers use optional `@color` directives in v2. Versions through 0.5.3 open documents containing these directives read-only. Remove all markers in 0.5.4 before editing such a document with an earlier version.

[User manual](README.md)

## Русский

### Изменения относительно 0.5.0

- В заголовках колонок добавлены значки быстрого создания текста, заметок с чекбоксами, выпадающих списков и импорта. Подсказки соответствуют выбранному языку.
- Выделение нескольких блоков позволяет удалять их с подтверждением и назначать цвет в пределах колонки. «Все / Снять» действует только на видимые блоки.
- Для отдельных и выделенных блоков доступны шесть цветовых меток. Метка отображается узкой полоской сбоку от содержимого.
- Массовое удаление и изменение меток поддерживают отмену и повтор одной операцией.
- Управление колонками и панель выделения адаптированы к узким колонкам.

### Требования

REAPER 7 или новее; ReaImGui 0.10 или новее.

### Совместимость формата

Документы без меток сохраняют прежний формат хранения. Цветовые метки используют необязательные директивы `@color` формата v2. Версии до 0.5.3 включительно открывают такие документы только для чтения. Для редактирования в более ранней версии необходимо предварительно удалить все метки в 0.5.4.

[Руководство пользователя](README_RU.md)

