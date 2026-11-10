-- @description ReaNotepad
-- @version 0.7.0
-- @author Aleksei Vorobev / Patch34
-- @link
--   GitHub repository https://github.com/patch-34/reanotepad
-- @changelog
--   Release 0.7.0: shared note/group action alignment and frameless menus.
--   Add group quick-add checkbox note and note checkbox toggle actions.
--   Unify font/spacing sliders, timecode navigation and timeline focus.
--   Stabilize ImGui scope pairing, note ordering and UI state handling.
-- @about
--   Structured notes for REAPER projects, tracks and media items.
--   Horizontal tabs contain independently collapsible vertical groups.
--   Text notes, checkbox notes, editable dropdowns and text import.
--   Mouse reordering of tabs and notes; note drag/drop between groups.
--   Per-note colors, colored group headings, HH:MM:SS:FF timecode navigation.
--   Owner-scoped Undo/Redo, native-note conflict checks and recovery copies.
--   Requires REAPER 7+ and ReaImGui 0.10+; SWS is not required.
--   Install: Actions > Show action list > New action > Load ReaScript.
--
--   STORAGE: Project notes use native GetSetProjectNotes. Item notes use P_NOTES.
--   Track notes use P_EXT:PATCH34_PROJECT_NOTES, stored in the .rpp project.
--   Documents use Patch34 Project Notes v3; legacy v1/v2 and plain notes remain
--   readable. Opening older notes alone does not rewrite them.
--   Old scripts may not support documents saved by this version.
--   Changes update REAPER immediately; save the project to persist to disk.
--   Recovery copies are stored under Data/Patch34_Project_Notes_Recovery.
--   Review recovery files before manually restoring them.
--   Historical storage keys, format headers and window IDs remain unchanged.
--
--   UI is adapted from Podcast HTML/DOCX Script Viewer v3.1.0-beta.1.
--   The source viewer is not modified or needed at runtime.
--   Official references: https://www.reaper.fm/sdk/reascript/reascripthelp.html
--                        https://cfillion.ca/reaper_imgui_doc.html

local M = {}
local VERSION = '0.7.0'
-- ============================================================================
-- UI SETTINGS / НАСТРОЙКИ ИНТЕРФЕЙСА                        EDIT HERE
-- ============================================================================
-- This is the single editable block for visual layout, fonts and theme colors.
-- Numbers below are pixels unless noted; alpha values are ratios (0..1). The settings do NOT change note data.
-- Start with one change at a time; test narrow windows and REAPER Docker.
-- font_size is read from the active ImGui font every frame (do not edit it).
-- Размеры — в пикселях; прозрачность — 0..1. font_size обновляется из ImGui.
-- Note indentation reserves a safe gutter for the marker and drag handle.
-- Отступ заметки учитывает ширину маркера и области перетаскивания.
-- Native ImGui style values not overridden here inherit the REAPER/ImGui style.
-- Непереопределённые параметры нативного ImGui наследуются от REAPER/ImGui.
local UI_METRICS = {
  -- Typography / Типографика: main UI font is independent of note text size slider.
  font_family='sans-serif', font_size=13, -- font_size is runtime-only
  tab_heading_extra_px=0, tab_arrow_extra_px=5,
  note_text_min_size=12, note_text_max_size=32, note_text_default_size=16,

  -- Main window / Основное окно.
  window_initial_width=545, window_initial_height=615,
  startup_layout_warmup_frames=2, startup_layout_warmup_alpha=0.001,
  window_min_width=540, window_min_height=360,
  menu_bar_height=38, menu_bar_pad_x=4,
  menu_trigger_pad_x=8, menu_label_min_inset_x=6, menu_label_min_inset_y=1,
  history_shortcut_gap=12, history_shortcut_min_spaces=2,
  window_pad_x=12, window_pad_y=10,
  frame_pad_x=6, frame_pad_y=3,
  frame_rounding=3, child_rounding=0, frame_border_size=1,

  -- Buttons and Controls / Кнопки и элементы управления: spacing / интервалы.
  item_gap_x=8, item_gap_y=8,
  group_gap=16, inner_gap=8, checkbox_label_gap=6,
  checkbox_pad_y=1, read_line_gap=2,
  note_checkbox_offset_y=0, -- Optical correction relative to the shared first-line center.
  note_checkbox_text_gap=6, -- Space after the native checkbox; independent of item spacing.

  -- Buttons and Controls / Кнопки и элементы управления.
  button_pad_x=8, button_pad_y=3, button_min_height=23,
  compact_button_pad_x=10, button_rounding=3,
  scope_min_width=110,
  dropdown_width=420, dropdown_visible_rows=8, dropdown_popup_extra_height=16,
  button_border_size=1,
  quick_icon_size=16, quick_icon_total_inset=7,
  timecode_icon_size=14, timecode_label_gap=4,

  -- Shared right alignment / Общая правая граница кнопок внутри колонки.
  -- action_to_scroll_gap: distance between action-button edge and scrollbar thumb.
  -- action_right_inset: move ALL column/tab/note action buttons farther left.
  -- Both values are measured in pixels. Do not change each component separately.
  -- action_to_scroll_gap: расстояние от кнопок до ползунка скролла.
  -- action_right_inset: дополнительный сдвиг ВСЕХ правых кнопок влево.
  action_to_scroll_gap=12, action_right_inset=4,
  -- Shared absolute screen anchor: the right edge of the last creation button.
  -- Tabs and group menus align to this anchor, without separate pixel guesses.
  -- Общий экранный якорь: правый край последней кнопки верхней панели.
  -- Верхняя панель определяет линию для кнопок вкладок и меню групп.
  creation_toolbar_right_inset=12,

  -- Horizontal tabs / Горизонтальные вкладки.
  tabs_strip_height=38, tabs_strip_pad_x=8, tabs_strip_pad_y=4,
  tabs_strip_label_pad_x=14, tabs_strip_gap=4, tabs_strip_min_width=56,
  tabs_strip_button_gap=8, tabs_strip_active_line=2,
  pointer_drag_threshold=6, tabs_drop_line_width=2,
  tabs_drag_scroll_edge=24, tabs_drag_scroll_speed=360, -- pixels/second
  -- Minimum safe inset when the shared anchor is unavailable or too far right.
  -- Минимальный защитный отступ; не самостоятельный сдвиг относительно панели.
  tabs_actions_right_inset=8,
  group_header_tint_light=0.25, group_header_tint_dark=0.34,
  -- Extra air between horizontal tab strip and the first group heading.
  -- Воздух сверху: первая группа не прижимается к панели вкладок.
  group_panel_top_padding=12,
  -- Group headings use the same right-action guide as every note.
  group_header_min_height=26,
  -- One centered three-dot icon for both group and note action hitboxes.
  group_menu_dot_radius=1.0, group_menu_dot_spacing=4.6,
  -- Inline quick-add at the bottom of each expanded group.
  -- circle-plus is an embedded Lucide icon, with click area independent of its image.
  group_add_note_size=36, group_add_note_icon_size=25,
  group_add_note_idle_alpha=0.55, group_add_note_hover_alpha=0.72,
  group_add_note_top_gap=12, group_add_note_bottom_gap=8,
  group_add_note_empty_top_gap=16,
  -- Group heading (historically an internal column header).
  tab_heading_menu_gap=4, tab_heading_min_title=18,
  tab_heading_arrow_text_gap=2, tab_heading_hover_alpha=0.85,

  -- Native sliders / Нативные ползунки (font and separator spacing).
  slider_width=180, font_slider_min_width=100,

  -- Scrollbars / Скроллбары: overlay thumb / ползунок поверх содержимого.
  overlay_scroll_width=5, overlay_scroll_inset=3, overlay_scroll_margin=6,
  overlay_scroll_min_thumb_height=24, overlay_scroll_min_track_height=24,
  overlay_scroll_hit_pad_left=2, overlay_scroll_hit_pad_right=1,

  -- Notes / Заметки.
  note_padding_y=4, -- Shared internal top/bottom padding, colored or uncolored.
  note_content_gap_y=4, -- Heading-to-second-row spacing; independent of outer padding.
  note_indent=24, note_row_inset_x=12, note_gutter_end_gap=4, note_actions_min_content_width=48,
  -- Separators are drawn only up to the shared actions edge; inset trims them.
  -- Сепараторы заканчиваются у границы кнопок; inset укорачивает линию.
  note_separator_right_inset=0, note_separator_thickness=1,
  note_separator_height=1, note_separator_raise=5,
  note_spacing_default=5, note_spacing_min=0, note_spacing_max=24, -- each side of a note separator (px)
  note_edit_min_height=66, note_edit_max_height=240,
  note_edit_extra_lines=3, note_edit_extra_height=12,
  completed_note_alpha=0.55,
  marker_fill_rounding=3, marker_fill_min_height=1,
  marker_strip_offset_x=1, marker_strip_width=3, marker_strip_pad_y=2,
  marker_strip_min_bottom_offset=10, marker_strip_rounding=1,
  marker_menu_offset_x=3, marker_menu_side=8, marker_menu_rounding=1,
  marker_menu_label_spaces=3, marker_menu_text_gap=6,
  selection_text_gutter=22, selection_min_height=23, selection_bottom_pad=4,
  selection_rounding=2, selection_check_right_offset=18,
  editor_extra_pad_x=2, editor_extra_pad_y=2, editor_wrap_right_inset=2,
  editor_newline_selection_min_width=4, editor_caret_thickness=1, editor_tab_spaces=4,
  editor_caret_period=1.2, editor_caret_visible_time=0.6, -- seconds / секунды

  -- Drag Handles and Drop Targets / Перетаскивание и области приёма.
  drag_handle_offset_x=6,
  drag_handle_width=14, drag_handle_max_height=18, drag_handle_icon_size=14,
  drag_handle_dot_radius=1, drag_handle_dot_pitch=4, -- Vector grip shape, not position offsets.
  drag_preview_max_chars=48,
  -- Shared outline for a dragged note and new-object placement targets.
  -- Общий стиль рамки перетаскиваемой заметки и области добавления объекта.
  drag_note_highlight_padding_x=4, drag_note_highlight_padding_y=4, drag_note_highlight_rounding=3,
  drag_note_highlight_border_thickness=1.0,
  drag_note_highlight_dash=5, drag_note_highlight_gap=4,
  trash_target_width=23, trash_icon_only=true, -- compact icon in the top toolbar
  trash_icon_size=16, trash_icon_vertical_inset=6, trash_icon_offset_x=8,
  trash_label_offset_x=30, trash_icon_label_gap=6,
  trash_border_size=1, trash_hover_border_size=2,
  drop_line_thickness=2, empty_tab_placement_height=38,
  note_drag_scroll_edge=36, note_drag_scroll_speed=360,

  -- Dialogs and Popups / Диалоги и всплывающие окна.
  confirm_min_width=280, confirm_max_width=520,
  popup_margin=12, popup_footer_gap=8, popup_border_size=1.5,
  import_pane_min_height=56, options_panel_min_height=60,
  option_input_min_width=60, option_actions_reserved_width=110,
  about_pad_x=20, about_pad_y=17, about_rounding=12,
  about_button_rounding=7, about_geometry_extra=2,
  -- Preferred outer sizes / Предпочтительные внешние размеры.
  -- Name height and About use content-measured minima; 0 means automatic.
  -- Высота Name и размеры About: минимум по содержимому; 0 — автоматически.
  popup_sizes={restore={580,460},name={320,0},select={500,460},import={860,440},about={0,0},note_cancel={390,146}},
}

-- Theme colors / Цвета оформления. RGBA component values are 0..255.
-- Leave historical storage keys and format headers elsewhere unchanged.
local function rgba(r,g,b,a) return (r<<24)|(g<<16)|(b<<8)|(a or 255) end
-- Theme color roles / Роли цветов тем. Native tabs/checks
-- use the agreed role mapping below; unused search/document roles are omitted.
local VIEWER_THEMES = {
  paper = {
    label = "Pages",

    C_PAPER = rgba(217, 215, 209),
    C_TEXT = rgba(28, 28, 28),
    C_DIM = rgba(153, 153, 153),

    C_CHROME = rgba(236, 234, 229),
    C_CHROME_DEEP = rgba(208, 206, 201),
    C_CHROME_TITLE = rgba(236, 234, 229),

    C_HEAD = rgba(225, 223, 218),
    C_HEAD_H = rgba(208, 206, 201),
    C_FRAME = rgba(245, 244, 240),

    C_LINE = rgba(208, 206, 201),
    C_MENU_BORDER = rgba(208, 206, 201),
    C_SCROLL = rgba(158, 155, 149),
    C_SCROLL_H = rgba(174, 172, 166),
    C_SCROLL_A = rgba(140, 137, 131),
    C_SCROLL_BG = rgba(217, 215, 209),

    C_VIEW_SLIDER_TRACK = rgba(200, 198, 192),
    C_VIEW_SLIDER_FILL = rgba(74, 124, 199),
    C_VIEW_SLIDER_KNOB_FILL = rgba(245, 244, 240),
    C_VIEW_SLIDER_KNOB_OUTLINE = rgba(74, 124, 199),

    C_VIEW_BUTTON_FILL = rgba(245, 244, 240),
    C_VIEW_BUTTON_HOVER = rgba(236, 234, 229),
    C_VIEW_BUTTON_ACTIVE = rgba(225, 223, 218),
    C_VIEW_BUTTON_BORDER = rgba(208, 206, 201),

  },

  grey = {
    label = "REAPER Grey",

    C_PAPER = rgba(239, 239, 239),
    C_TEXT = rgba(28, 24, 18),
    C_DIM = rgba(112, 112, 112),

    C_CHROME = rgba(218, 218, 218),
    C_CHROME_DEEP = rgba(92, 112, 104),
    C_CHROME_TITLE = rgba(112, 132, 122),

    C_HEAD = rgba(202, 206, 210),
    C_HEAD_H = rgba(188, 193, 198),
    C_FRAME = rgba(250, 250, 250),

    C_LINE = rgba(104, 120, 114),
    C_MENU_BORDER = rgba(104, 120, 114, 60),
    C_SCROLL = rgba(176, 176, 176),
    C_SCROLL_H = rgba(154, 154, 154),
    C_SCROLL_A = rgba(132, 132, 132),
    C_SCROLL_BG = rgba(239, 239, 239),

    C_VIEW_SLIDER_TRACK = rgba(196, 196, 196),
    C_VIEW_SLIDER_FILL = rgba(86, 104, 124),
    C_VIEW_SLIDER_KNOB_FILL = rgba(252, 252, 252),
    C_VIEW_SLIDER_KNOB_OUTLINE = rgba(86, 104, 124),

    C_VIEW_BUTTON_FILL = rgba(238, 238, 238),
    C_VIEW_BUTTON_HOVER = rgba(226, 226, 226),
    C_VIEW_BUTTON_ACTIVE = rgba(214, 214, 214),
    C_VIEW_BUTTON_BORDER = rgba(174, 174, 174),

  },

  white = {
    label = "Google Docs White",

    C_PAPER = rgba(241, 243, 244),
    C_TEXT = rgba(32, 33, 36),
    C_DIM = rgba(95, 99, 104),

    C_CHROME = rgba(248, 250, 253),
    C_CHROME_DEEP = rgba(232, 240, 254),
    C_CHROME_TITLE = rgba(248, 250, 253),

    C_HEAD = rgba(232, 240, 254),
    C_HEAD_H = rgba(210, 227, 252),
    C_FRAME = rgba(255, 255, 255),

    C_LINE = rgba(218, 220, 224),
    C_MENU_BORDER = rgba(218, 220, 224),
    C_SCROLL = rgba(189, 193, 198),
    C_SCROLL_H = rgba(154, 160, 166),
    C_SCROLL_A = rgba(128, 134, 139),
    C_SCROLL_BG = rgba(241, 243, 244),

    C_VIEW_SLIDER_TRACK = rgba(218, 220, 224),
    C_VIEW_SLIDER_FILL = rgba(26, 115, 232),
    C_VIEW_SLIDER_KNOB_FILL = rgba(255, 255, 255),
    C_VIEW_SLIDER_KNOB_OUTLINE = rgba(26, 115, 232),

    C_VIEW_BUTTON_FILL = rgba(255, 255, 255),
    C_VIEW_BUTTON_HOVER = rgba(241, 243, 244),
    C_VIEW_BUTTON_ACTIVE = rgba(232, 240, 254),
    C_VIEW_BUTTON_BORDER = rgba(218, 220, 224),

  },
}
-- Dark is the approved exception to the three supplied Viewer themes.
do
  local bg,paper,chrome=rgba(30,32,36),rgba(37,40,45),rgba(44,47,53)
  local text,dim,line=rgba(231,233,237),rgba(160,166,177),rgba(75,81,92)
  local hover,accent=rgba(61,68,80),rgba(116,170,238)
  VIEWER_THEMES.dark={label='Dark',C_PAPER=bg,C_FRAME=paper,C_TEXT=text,C_DIM=dim,C_CHROME=chrome,
    C_CHROME_DEEP=chrome,C_CHROME_TITLE=chrome,C_HEAD=hover,C_HEAD_H=line,
    C_LINE=line,C_MENU_BORDER=line,C_SCROLL=line,C_SCROLL_H=dim,C_SCROLL_A=dim,C_SCROLL_BG=bg,
    C_VIEW_BUTTON_FILL=chrome,C_VIEW_BUTTON_HOVER=hover,C_VIEW_BUTTON_ACTIVE=line,C_VIEW_BUTTON_BORDER=line,
    C_VIEW_SLIDER_TRACK=line,C_VIEW_SLIDER_FILL=accent,C_VIEW_SLIDER_KNOB_FILL=paper,C_VIEW_SLIDER_KNOB_OUTLINE=accent}
end

-- Shared palettes / Общие палитры (RGBA; alpha multipliers are 0..1).
-- About intentionally keeps the original theme-independent Viewer skin.
local UI_PALETTE = {
  text_selection_alpha=65,
  modal_dim_light=rgba(0,0,0,90), modal_dim_dark=rgba(0,0,0,140),
  about={background=rgba(80,80,80,218),border=rgba(220,220,220,95),
    text=rgba(245,245,245),dim=rgba(210,210,210),
    button=rgba(105,105,105,230),button_hover=rgba(122,122,122,235),
    button_border=rgba(230,230,230,80)},
  trash={text=rgba(146,74,74,255),text_hover=rgba(181,52,52,255),
    fill=rgba(146,74,74,14),fill_hover=rgba(181,52,52,48)},
  drag_note_highlight_fill_alpha=0.06, drag_note_highlight_edge_alpha=120,
  marker_tint_light=0.12, marker_tint_dark=0.18,
}
-- Marker palette / Палитра цветовых маркеров.
local MARKER_PALETTE = {
  light={red=0xc15251ff,orange=0xb5782bff,yellow=0xa29227ff,
    green=0x54816aff,blue=0x527fa1ff,purple=0x8c6ca1ff},
  dark={red=0xe88a85ff,orange=0xe6b767ff,yellow=0xd6c75fff,
    green=0x82b79aff,blue=0x8fb8d6ff,purple=0xbba0cdff},
}

-- Configuration guards / Ограничения настроек.
-- Dimensions are nonnegative; the checkbox optical y correction may be signed.
-- Coupled geometry also clamps to the actual available space at draw time.
do
  for key,value in pairs(UI_METRICS) do
    if type(value)=='number' then
      assert(value==value and math.abs(value)<math.huge,'Invalid UI metric: '..key)
      if key~='note_checkbox_offset_y' then
        UI_METRICS[key]=math.max(0,value)
      end
    end
  end
  for _,key in ipairs({'note_text_min_size','note_text_max_size','note_text_default_size',
      'button_min_height','font_slider_min_width','group_add_note_size',
      'note_edit_min_height','note_edit_max_height','overlay_scroll_width',
      'overlay_scroll_min_thumb_height','editor_caret_period'}) do
    UI_METRICS[key]=math.max(1,UI_METRICS[key])
  end
  UI_METRICS.note_text_min_size=math.max(1,math.floor(UI_METRICS.note_text_min_size))
  UI_METRICS.note_text_max_size=math.max(UI_METRICS.note_text_min_size,math.floor(UI_METRICS.note_text_max_size))
  UI_METRICS.note_text_default_size=math.max(UI_METRICS.note_text_min_size,
    math.min(UI_METRICS.note_text_max_size,math.floor(UI_METRICS.note_text_default_size)))
  UI_METRICS.note_edit_max_height=math.max(UI_METRICS.note_edit_min_height,UI_METRICS.note_edit_max_height)
  UI_METRICS.confirm_max_width=math.max(UI_METRICS.confirm_min_width,UI_METRICS.confirm_max_width)
  UI_METRICS.dropdown_visible_rows=math.max(1,math.floor(UI_METRICS.dropdown_visible_rows))
  UI_METRICS.editor_tab_spaces=math.max(1,math.floor(UI_METRICS.editor_tab_spaces))
  UI_METRICS.marker_menu_label_spaces=math.floor(UI_METRICS.marker_menu_label_spaces)
  UI_METRICS.history_shortcut_min_spaces=math.floor(UI_METRICS.history_shortcut_min_spaces)
  UI_METRICS.drag_preview_max_chars=math.max(1,math.floor(UI_METRICS.drag_preview_max_chars))
  UI_METRICS.completed_note_alpha=math.min(1,UI_METRICS.completed_note_alpha)
  UI_METRICS.startup_layout_warmup_alpha=math.min(1,UI_METRICS.startup_layout_warmup_alpha)
  UI_METRICS.startup_layout_warmup_frames=math.floor(UI_METRICS.startup_layout_warmup_frames)
  UI_METRICS.tab_heading_hover_alpha=math.min(1,UI_METRICS.tab_heading_hover_alpha)
  UI_METRICS.group_header_tint_light=math.min(1,UI_METRICS.group_header_tint_light)
  UI_METRICS.group_header_tint_dark=math.min(1,UI_METRICS.group_header_tint_dark)
  UI_METRICS.group_add_note_idle_alpha=math.min(1,UI_METRICS.group_add_note_idle_alpha)
  UI_METRICS.group_add_note_hover_alpha=math.min(1,UI_METRICS.group_add_note_hover_alpha)
  UI_METRICS.tabs_strip_height=math.max(UI_METRICS.button_min_height,UI_METRICS.tabs_strip_height)
  UI_METRICS.editor_caret_visible_time=math.min(UI_METRICS.editor_caret_period,UI_METRICS.editor_caret_visible_time)
  for _,dimensions in pairs(UI_METRICS.popup_sizes) do
    for i=1,2 do
      assert(type(dimensions[i])=='number' and dimensions[i]==dimensions[i]
        and math.abs(dimensions[i])<math.huge,'Invalid popup dimension')
      dimensions[i]=math.max(0,dimensions[i])
    end
  end
  for _,key in ipairs({'marker_tint_light','marker_tint_dark',
      'drag_note_highlight_fill_alpha'}) do
    UI_PALETTE[key]=math.max(0,math.min(1,UI_PALETTE[key]))
  end
  for _,key in ipairs({'text_selection_alpha',
      'drag_note_highlight_edge_alpha'}) do
    UI_PALETTE[key]=math.floor(math.max(0,math.min(255,UI_PALETTE[key])))
  end
end

-- ============================================================================
-- END UI SETTINGS / КОНЕЦ НАСТРОЕК ИНТЕРФЕЙСА
-- ============================================================================

local HEADER = '# Patch34 Project Notes v3'
local PREVIOUS_HEADER = '# Patch34 Project Notes v2'
local LEGACY_HEADER = '# Patch34 Project Notes v1'
local sequence = 0
local function uid() sequence = sequence + 1; return sequence end
local function norm(s) return (s:gsub('\r\n', '\n'):gsub('\r', '\n')) end
local function lines(s)
  local out = {}
  for l in (s .. '\n'):gmatch('(.-)\n') do out[#out + 1] = l end
  return out
end
local function esc(s)
  return (s:gsub('\\', '\\\\'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t'))
end
local function unesc(s)
  local out, i = {}, 1
  local codes = {n='\n', r='\r', t='\t', ['\\']='\\'}
  while i <= #s do
    local c = s:sub(i,i)
    if c == '\\' then
      i = i + 1
      c = codes[s:sub(i,i)]
      if not c then error('Unknown or incomplete escape sequence.') end
    end
    out[#out+1] = c
    i = i + 1
  end
  return table.concat(out)
end
function M.text(value) return {id=uid(), kind='text', text=value or ''} end
function M.note(value,checked) return {id=uid(),kind='note',text=value or '',checked=checked==true} end
-- Preserve block identity, text, timecode metadata and color when toggling
-- a note's checkbox; storage already supports both @text and @note kinds.
function M.set_note_checkbox(block,enabled)
  if enabled and block.kind=='text' then
    block.kind='note';block.checked=false;return true
  elseif not enabled and block.kind=='note' then
    block.kind='text';block.checked=nil;return true
  end
  return false
end
function M.completed(b) return (b.kind=='check' or b.kind=='note') and b.checked==true end
function M.visible(b,hide) return not (hide and M.completed(b)) end
function M.display_order(column,hide,completed_last)
  local order,completed={},{}
  for i,b in ipairs(column.blocks) do
    if M.visible(b,hide) then
      local group=completed_last and M.completed(b) and completed or order
      group[#group+1]=i
    end
  end
  for _,i in ipairs(completed) do order[#order+1]=i end
  return order
end
function M.block_neighbor(column,index,delta,hide,completed_last)
  local order=M.display_order(column,hide,completed_last)
  for position,i in ipairs(order) do
    if i==index then
      local neighbor=order[position+delta]
      if neighbor and (not completed_last or M.completed(column.blocks[index])==M.completed(column.blocks[neighbor])) then
        return neighbor
      end
      return nil
    end
  end
end
M.marker_keys={'red','orange','yellow','green','blue','purple'}
function M.valid_marker(key)
  if key==nil then return true end
  for _,value in ipairs(M.marker_keys) do if value==key then return true end end
  return false
end
function M.selection_prune(column,selected,hide)
  local available,count,visible={},0,0
  for _,b in ipairs(column.blocks) do
    if M.visible(b,hide) then
      available[b.id]=true;visible=visible+1
      if selected[b.id] then count=count+1 end
    end
  end
  for id in pairs(selected) do if not available[id] then selected[id]=nil end end
  return count,visible
end
function M.selection_all(column,selected,hide,value)
  for id in pairs(selected) do selected[id]=nil end
  if value then
    for _,b in ipairs(column.blocks) do if M.visible(b,hide) then selected[b.id]=true end end
  end
end
function M.selection_delete(column,selected,hide)
  local count=0
  for i=#column.blocks,1,-1 do
    local b=column.blocks[i]
    if selected[b.id] and M.visible(b,hide) then table.remove(column.blocks,i);count=count+1 end
  end
  return count
end
function M.selection_color(column,selected,hide,key)
  assert(M.valid_marker(key),'Invalid color marker.')
  local count=0
  for _,b in ipairs(column.blocks) do
    if selected[b.id] and M.visible(b,hide) and b.color~=key then b.color=key;count=count+1 end
  end
  return count
end
-- Explicit list markers are distinct from numbers in prose. Bare numbers
-- require an adjacent consecutive candidate; a single "2026 year" is not a list.
-- Only a leading timecode is an anchor; numbers inside prose stay ordinary
-- text. Keep its spelling in the note and resolve it again after text edits.
-- Four-field timecodes use the current project's frame rate (including DF mode).
-- The caller supplies these only when a REAPER project is available; never
-- guess an FPS for imported data. Two/three-field codes remain seconds-based.
function M.timecode_prefix(text,frame_rate,drop_frame)
  local value=norm(text:sub(1,512)):gsub('^\239\187\191',''):gsub('\194\160',' ')
  local first,rest=value:match('^([^\n]*)\n?(.*)$')
  first=first:match('^%s*(.-)%s*$')
  if first:match('^%d+[%.%):]$') or first:match('^%(%d+%)$') or first:match('^%[%d+%]$')
      or first:match('^[1-9]%d?%d?$') then
    first=rest:match('^%s*([^\n]*)') or ''
  end
  local body=first:match('^%(%d+%)%s+(.+)$') or first:match('^%[%d+%]%s+(.+)$')
    or first:match('^[%d%.]+[%.%):]%s+(.+)$')
  if not body then
    for _,dash in ipairs({'-','–','—'}) do
      body=first:match('^%d+%s*'..(dash=='-' and '%-' or dash)..'%s+(.+)$')
      if body then break end
    end
  end
  first=body or first:match('^%d+%s+(.+)$') or first
  local bold=first:sub(1,2)=='**'
  if bold then first=first:sub(3) end
  local opener=first:sub(1,1)
  local closer=opener=='[' and ']' or opener=='(' and ')' or nil
  if closer then first=first:sub(2) end
  local negative=first:sub(1,1)=='-'
  if negative then first=first:sub(2) end
  local token,tail=first:match('^([%d:.,]+)(.*)$')
  if not token then return nil end
  if closer then
    if tail:sub(1,1)~=closer then return nil end
    tail=tail:sub(2)
  end
  if bold then
    if tail:sub(1,2)~='**' then return nil end
    tail=tail:sub(3)
  end
  if tail~='' and not tail:match('^%s') then return nil end
  local whole,fraction=token:match('^(.-)[.,](%d+)$')
  if fraction and #fraction>3 then return nil end
  whole=whole or token
  local h,m,s,frames=whole:match('^(%d+):(%d%d):(%d%d):(%d%d)$')
  local seconds
  if frames then
    -- Frame counts have their own precision; don't mix them with milliseconds.
    if fraction or type(frame_rate)~='number' or frame_rate~=frame_rate
        or frame_rate<=0 or frame_rate==math.huge then return nil end
    local nominal=math.floor(frame_rate+0.5)
    local hh,mm,ss,ff=tonumber(h),tonumber(m),tonumber(s),tonumber(frames)
    if nominal<1 or mm>=60 or ss>=60 or ff>=nominal then return nil end
    local frame_number=((hh*3600+mm*60+ss)*nominal+ff)
    if drop_frame and (nominal==30 or nominal==60)
        and math.abs(frame_rate-nominal*1000/1001)<0.01 then
      -- SMPTE DF numbering skips 2 (or 4 at 59.94) frame labels at each
      -- minute except every tenth. Reject labels that would be skipped.
      local dropped=nominal==60 and 4 or 2
      if mm%10~=0 and ss==0 and ff<dropped then return nil end
      local minutes=hh*60+mm
      frame_number=frame_number-dropped*(minutes-math.floor(minutes/10))
    end
    seconds=frame_number/frame_rate
  else
    h,m,s=whole:match('^(%d+):(%d%d):(%d%d)$')
    if not h then m,s=whole:match('^(%d+):(%d%d)$') end
    if not m or tonumber(s)>=60 or (h and tonumber(m)>=60) then return nil end
    seconds=(tonumber(h) or 0)*3600+tonumber(m)*60+tonumber(s)
    if fraction then seconds=seconds+tonumber('0.'..fraction) end
  end
  if seconds~=seconds or seconds>1e12 then return nil end
  return negative and -seconds or seconds,(negative and '-' or '')..token
end
function M.block_time(block,frame_rate,drop_frame)
  -- Detect leading timecodes regardless of historical @timecode flags.
  -- v0.6.0 stored @timecode 0 for imports with splitting disabled;
  -- preserving the flag in storage but ignoring it restores these notes.
  if block.kind=='text' or block.kind=='note' then return M.timecode_prefix(block.text or '',frame_rate,drop_frame) end
  if block.kind=='check' or block.kind=='select' then return M.timecode_prefix(block.label or '',frame_rate,drop_frame) end
end
function M.seek_position(block,offset,frame_rate,drop_frame)
  local time=M.block_time(block,frame_rate,drop_frame)
  if time==nil or type(offset)~='number' or offset~=offset or math.abs(offset)==math.huge then return nil end
  local position=time-offset
  if position~=position or math.abs(position)==math.huge then return nil end
  return position
end
function M.timecode_label(time)
  local sign=time<0 and '-' or ''
  local ms=math.floor(math.abs(time)*1000+0.5)
  local seconds=math.floor(ms/1000)
  local hours=math.floor(seconds/3600)
  local label=hours>0 and ('%02d:%02d:%02d'):format(hours,math.floor(seconds/60)%60,seconds%60)
    or ('%02d:%02d'):format(math.floor(seconds/60),seconds%60)
  if ms%1000>0 then label=label..('.%03d'):format(ms%1000):gsub('0+$','') end
  return sign..label
end
-- Normalized stretch weights. New columns without a saved share receive the
-- mean share of the visible columns.
-- Keep a shared scale when only a subset is visible. Measuring a single
-- expanded column must not increase its saved weight relative to folded ones.
-- Presentation state is deliberately absent from the note format/history.
-- Preserve it across safe cache suspension and match unambiguous names on Undo.
function M.column_view_snapshot(doc)
  local result={}
  if not doc then return result end
  for ti,tab in ipairs(doc.tabs) do
    for ci,column in ipairs(tab.columns) do
      result[#result+1]={tab=tab.name,name=column.name,ti=ti,ci=ci,
        folded=column.folded,width=column.layout_width,board_folded=tab.folded,board_width=tab.layout_width}
    end
  end
  return result
end
function M.restore_column_views(doc,views,exact)
  local names,counts={},{}
  for _,view in ipairs(views or {}) do
    local key=view.tab..'\0'..view.name
    names[key]=view;counts[key]=(counts[key] or 0)+1
  end
  local targets={}
  for _,tab in ipairs(doc.tabs) do
    for _,column in ipairs(tab.columns) do
      local key=tab.name..'\0'..column.name
      targets[key]=(targets[key] or 0)+1
    end
  end
  local used={}
  for ti,tab in ipairs(doc.tabs) do
    for ci,column in ipairs(tab.columns) do
      local key=tab.name..'\0'..column.name
      local view=counts[key]==1 and targets[key]==1 and names[key] or nil
      if exact then
        view=nil
        for _,candidate in ipairs(views or {}) do
          if candidate.ti==ti and candidate.ci==ci and candidate.tab==tab.name and candidate.name==column.name then view=candidate;break end
        end
      end
      if view and (exact or not used[key]) then
        column.folded=view.folded;column.layout_width=view.width
        tab.folded=view.board_folded;tab.layout_width=view.board_width
      end
      used[key]=true
    end
  end
end
function M.import_text(raw,strip,timecodes,frame_rate,drop_frame)
  local source=norm(raw):gsub('^\239\187\191',''):gsub('\194\160',' ')
  local ls=lines(source:match('^%s*(.-)%s*$'))
  local function trim(x)return x:match('^%s*(.-)%s*$')end
  local function candidate(x)
    local prefix,body=x:match('^(%(%d+%))%s+(.+)$')
    if not prefix then prefix,body=x:match('^(%[%d+%])%s+(.+)$') end
    if not prefix then prefix=x:match('^(%(%d+%))$') or x:match('^(%[%d+%])$') end
    if prefix then return {number=tonumber(prefix:match('%d+')),body=body,explicit=true} end

    -- Keep digit runs separately so decimal values and dotted dates cannot
    -- pass merely because they contain a dot. Only a final delimiter counts.
    local digits,punctuation=x:match('^([%d%.]+)([%.%):])%s+')
    if digits then body=x:match('^[%d%.]+[%.%):]%s+(.+)$')
    else digits,punctuation=x:match('^([%d%.]+)([%.%):])$') end
    if not digits then
      for _,dash in ipairs({'-','–','—'}) do
        digits,body=x:match('^(%d+)%s*'..(dash=='-' and '%-' or dash)..'%s+(.+)$')
        if digits then punctuation=dash;break end
      end
    end
    if digits then
      local hierarchy=digits:find('.',1,true)~=nil
      local valid=not digits:find('..',1,true) and not digits:match('^%.') and not digits:match('%.$')
      -- A closing parenthesis explicitly marks a flat list even at large
      -- indices. Ambiguous four-digit dot/colon/dash prefixes remain text.
      if punctuation~=')' or hierarchy then
        for part in digits:gmatch('%d+') do if #part>3 then valid=false end end
      end
      if hierarchy and punctuation~='.' and punctuation~=')' then valid=false end
      if valid then
        return {number=not hierarchy and tonumber(digits) or nil,body=body,explicit=true}
      end
      return nil
    end

    digits,body=x:match('^(%d+)%s+(.+)$')
    if not digits then digits=x:match('^(%d+)$') end
    -- Leading zeros and four-digit values are ambiguous identifiers/years.
    if digits and #digits<=3 and not digits:match('^0') then
      return {number=tonumber(digits),body=body,explicit=false}
    end
  end
  local parsed,sequence,timed={},{},{}
  local has_blank,has_numbers,has_timecodes=false,false,false
  for i,line in ipairs(ls) do
    local value=trim(line)
    ls[i]=value
    if value=='' and i>1 and i<#ls then has_blank=true end
    local mark=candidate(value)
    if mark then
      parsed[i]=mark;sequence[#sequence+1]=mark
      -- Already explicit markers can anchor adjacent bare list numbers.
      mark.accepted=mark.explicit
    end
  end
  for i,mark in ipairs(sequence) do
    local previous,next_mark=sequence[i-1],sequence[i+1]
    if not mark.explicit then
      mark.accepted=(previous and previous.number and mark.number==previous.number+1)
        or (next_mark and next_mark.number and next_mark.number==mark.number+1) or false
    end
    if mark.accepted then has_numbers=true end
  end
  if timecodes then
    for i,value in ipairs(ls) do
      local mark=parsed[i]
      local position=M.timecode_prefix(mark and mark.accepted and mark.body or value,frame_rate,drop_frame)
      if position~=nil then timed[i]=true;has_timecodes=true end
    end
  end
  local result,part,marker,pending_list={},{},nil,false
  local function flush()
    local value=trim(table.concat(part,'\n'));part={}
    if value=='' and marker then value=marker end
    marker=nil;pending_list=false
    if value~='' then result[#result+1]=value end
  end
  for i,line in ipairs(ls) do
    local mark=parsed[i]
    if line=='' then
      if #part>0 then flush() end
    elseif mark and mark.accepted then
      flush()
      if not mark.body and strip~=false then marker=line end
      if strip==false or mark.body then part[#part+1]=(strip~=false and mark.body) or line end
      pending_list=not mark.body
    elseif timed[i] then
      if #part>0 and not pending_list then flush() end
      part[#part+1]=line;pending_list=false
    else
      if not has_blank and not has_numbers and not has_timecodes then flush() end
      part[#part+1]=line;pending_list=false
    end
  end
  flush()
  return result
end
function M.column(name, text)
  return {id=uid(), name=name or 'Column 1', blocks=text ~= nil and {M.text(text)} or {}}
end
function M.tab(name, text)
  return {id=uid(), name=name or 'Notes', columns={M.column('Column 1',text)}}
end
-- The axis marker distinguishes vertical tabs from historical top-level tabs.
-- Historical columns retain their position; each old tab becomes a section.
function M.board_layout(doc)
  if doc.layout=='columns' then return doc end
  local result={layout='columns',tabs={}}
  for _,old_tab in ipairs(doc.tabs) do
    for ci,old_column in ipairs(old_tab.columns) do
      local board=result.tabs[ci]
      if not board then board=M.tab(old_column.name);board.columns={};result.tabs[ci]=board end
      local name=old_tab.name
      if old_column.name~=board.name then name=name..' — '..old_column.name end
      local section=M.column(name);section.blocks=old_column.blocks
      board.columns[#board.columns+1]=section
    end
  end
  return result
end
function M.plain(raw)
  return M.board_layout({tabs={M.tab('Notes',raw~='' and raw or nil)}})
end
function M.serialize(doc)
  local out = {HEADER,'@layout columns'}
  for _,tab in ipairs(doc.tabs) do
    out[#out+1] = '@tab ' .. esc(tab.name)
    for _,column in ipairs(tab.columns) do
      out[#out+1] = '@column ' .. esc(column.name)
      if column.header_color then
        assert(M.valid_marker(column.header_color),'Invalid group header color.')
        out[#out+1]='@groupcolor '..column.header_color
      end
      for _,b in ipairs(column.blocks) do
      assert(M.valid_marker(b.color),'Invalid color marker.')
      if b.color then out[#out+1]='@color '..b.color end
      assert(b.timecode==nil or type(b.timecode)=='boolean','Invalid timecode flag.')
      if b.timecode~=nil then
        assert(b.kind=='text' or b.kind=='note','Timecodes require a text block.')
        out[#out+1]='@timecode '..(b.timecode and '1' or '0')
      end
      if b.kind == 'text' or b.kind == 'note' then
        out[#out+1] = b.kind=='note' and ('@note '..(b.checked and '1' or '0')) or '@text'
        -- The parser normalizes all native EOL forms. Escape after that same
        -- normalization, including directive-looking lines after a lone CR.
        for _,l in ipairs(lines(norm(b.text))) do
          -- Escape directive-looking lines and escape characters, reversibly.
          out[#out+1] = l:match('^[@\\]') and '\\' .. l or l
        end
        out[#out+1] = '@end'
      elseif b.kind == 'check' then
        out[#out+1] = '@check ' .. (b.checked and '1 ' or '0 ') .. esc(b.label)
      elseif b.kind == 'select' then
        out[#out+1] = '@select ' .. tostring(b.selected) .. ' ' .. esc(b.label)
        for _,o in ipairs(b.options) do out[#out+1] = '@option ' .. esc(o) end
        out[#out+1] = '@end'
      else error('Unknown block type.') end
      end
      out[#out+1] = '@endcolumn'
    end
    out[#out+1] = '@endtab'
  end
  return table.concat(out, '\n')
end
function M.parse(raw)
  local normalized = norm(raw)
  local header = normalized:match('^[^\n]*')
  local legacy = header == LEGACY_HEADER
  if header ~= HEADER and header ~= PREVIOUS_HEADER and not legacy then
    if normalized:match('^# Patch34 Project Notes v') then
      return nil, 'Unsupported notes format. Original notes were not changed.'
    end
    return M.plain(raw)
  end
  local ok, result = pcall(function()
    local ls, doc, tab, column, i = lines(normalized), {tabs={}}, nil, nil, 2
    local pending_color,pending_timecode
    while i <= #ls do
      local l = ls[i]
      local before_blocks=column and #column.blocks or 0
      if l=='@layout columns' and i==2 and not legacy then doc.layout='columns'
       elseif l:match('^@groupcolor ') and column and not legacy and header==HEADER then
         local key=l:sub(13)
         assert(not column.header_color and M.valid_marker(key),'Invalid group header color.')
         column.header_color=key
      elseif l:sub(1,5) == '@tab ' and not tab then
        tab = M.tab(unesc(l:sub(6))); doc.tabs[#doc.tabs+1] = tab
        if legacy then column=tab.columns[1] else tab.columns={} end
      elseif l:sub(1,8) == '@column ' and tab and not column and not legacy then
        column=M.column(unesc(l:sub(9))); tab.columns[#tab.columns+1]=column
      elseif l == '@endcolumn' and column and not legacy then
        assert(not pending_color and pending_timecode==nil,'Block metadata has no block.');column=nil
      elseif l == '@endtab' and tab then
        assert(not pending_color and pending_timecode==nil,'Block metadata has no block.')
        assert(legacy or not column, 'Unclosed column.')
        assert(#tab.columns>0, 'Tab has no columns.')
        assert(doc.layout=='columns' or #tab.columns<=8, 'A tab supports up to 8 columns.')
        tab=nil; column=nil
      elseif l:match('^@color ') and column and not legacy then
        local key=l:sub(8)
        assert(not pending_color and M.valid_marker(key),'Invalid or repeated color marker.')
        pending_color=key
      elseif (l=='@timecode' or l:match('^@timecode [01]$')) and column and not legacy then
        assert(pending_timecode==nil,'Repeated timecode flag.')
        pending_timecode=l~='@timecode 0'
      elseif (l == '@text' or l:match('^@note [01]$')) and column then
        local content = {}; i = i + 1
        while i <= #ls and ls[i] ~= '@end' do
          local t = ls[i]
          if t:sub(1,1) == '\\' then
            assert(t:sub(2,2) == '\\' or t:sub(2,2) == '@', 'Invalid text escape.')
            t = t:sub(2)
          else assert(t:sub(1,1) ~= '@', 'Unescaped directive inside text.') end
          content[#content+1] = t; i = i + 1
        end
        assert(ls[i] == '@end', 'Unclosed text block.')
        column.blocks[#column.blocks+1] = l=='@text' and M.text(table.concat(content,'\n')) or M.note(table.concat(content,'\n'),l=='@note 1')
      elseif l:match('^@check [01] ') and column then
        column.blocks[#column.blocks+1] = {id=uid(),kind='check',checked=l:sub(8,8)=='1',label=unesc(l:sub(10))}
      elseif l:match('^@select %d+ ') and column then
        local n, label = l:match('^@select (%d+) (.*)$')
        local b = {id=uid(),kind='select',label=unesc(label),selected=tonumber(n),options={}}
        i = i + 1
        while i <= #ls and ls[i]:sub(1,8) == '@option ' do
          b.options[#b.options+1] = unesc(ls[i]:sub(9)); i = i + 1
        end
        assert(ls[i]=='@end', 'Unclosed dropdown block.')
        assert(#b.options>0 and b.selected>=1 and b.selected<=#b.options, 'Invalid dropdown selection.')
        column.blocks[#column.blocks+1] = b
      elseif l == '' and not tab then -- allow a trailing native-editor newline
      else error('Unexpected line ' .. i .. ': ' .. l:sub(1,70)) end
      if column and #column.blocks>before_blocks then
        local block=column.blocks[#column.blocks]
        assert(pending_timecode==nil or block.kind=='text' or block.kind=='note','Timecodes require a text block.')
        block.color=pending_color;pending_color=nil
        block.timecode=pending_timecode;pending_timecode=nil
      end
      i = i + 1
    end
    assert(not pending_color and pending_timecode==nil,'Block metadata has no block.')
    assert(not tab, 'Unclosed tab.')
    assert(#doc.tabs>0, 'Document has no tabs.')
    assert(doc.layout~='columns' or #doc.tabs<=8,'A document supports up to 8 columns.')
    return M.board_layout(doc)
  end)
  if ok then return result end
  return nil, tostring(result)
end
function M.move(list, index, delta)
  local to = index + delta
  if to < 1 or to > #list then return index end
  list[index], list[to] = list[to], list[index]
  return to
end
-- Unlike swapping, a nonadjacent move preserves the relative order of every
-- other note. This matters when Completed notes last changes display order.
function M.move_to(list,index,to)
  if index < 1 or index > #list or to < 1 or to > #list or index==to then return index end
  table.insert(list,to,table.remove(list,index))
  return to
end
-- "before" is a stable destination identity; nil means the end of the list.
function M.reorder_tab(doc,id,before,active)
  local source,target
  for i,tab in ipairs(doc.tabs) do
    if tab.id==id then source=i end
    if tab.id==before then target=i end
  end
  if not source or (before~=nil and not target) then return active,false end
  target=target or (#doc.tabs+1)
  if source<target then target=target-1 end
  if source==target then return active,false end
  local selected=doc.tabs[active]
  table.insert(doc.tabs,target,table.remove(doc.tabs,source))
  for i,tab in ipairs(doc.tabs) do if tab==selected then return i,true end end
  return math.min(active or 1,#doc.tabs),true
end
function M.note_row_layout(text_h,checkbox_h,checked,metrics,min_height)
  local height=math.max(text_h,checked and checkbox_h or 0,min_height or 0)
  return {height=height,text_y=(height-text_h)*0.5,
    checkbox_y=(height-checkbox_h)*0.5+metrics.note_checkbox_offset_y,
    center=height*0.5}
end
function M.remove_option(b, index)
  if #b.options <= 1 then return end
  table.remove(b.options,index)
  if index < b.selected then b.selected = b.selected - 1
  elseif index == b.selected then b.selected = math.min(index,#b.options) end
end
function M.move_option(b, index, delta)
  local to = M.move(b.options,index,delta)
  if b.selected == index then b.selected = to
  elseif b.selected == to then b.selected = index end
end
-- Compare against the exact last native read, not against re-serialized content.
function M.write_raw(session, api, next_raw)
  -- Record intent without writing again if any host call throws.
  session.write_attempt=next_raw;session.write_stage='checking'
  local owner=session.target or session.proj
  if not api.valid(owner) then return false, 'The note owner was removed or its project was closed.' end
  local current = api.read(owner)
  if current ~= session.raw then
    session.conflict = current
    return false, 'Native notes changed. The local draft has not been written.'
  end
  session.write_stage='writing'
  local written,write_error=api.write(owner,next_raw)
  if written~=true then session.write_stage='rejected';return false,write_error or 'REAPER could not write these notes.' end
  session.write_stage='verifying'
  local actual = api.read(owner)
  -- Native editors may normalize EOLs or add a newline after @endtab.
  -- Trailing text-block newlines remain inside @text/@end and are significant.
  local same = norm(actual) == norm(next_raw)
  if not same and (next_raw:sub(1,#HEADER)==HEADER or next_raw:sub(1,#PREVIOUS_HEADER)==PREVIOUS_HEADER
      or next_raw:sub(1,#LEGACY_HEADER)==LEGACY_HEADER) then
    same = norm(actual):gsub('\n+$','') == norm(next_raw):gsub('\n+$','')
  end
  if not same then
    session.conflict = actual
    return false, 'REAPER did not return the complete saved document.'
  end
  session.raw = actual; session.dirty = false; session.conflict = nil
  session.write_stage='confirmed'
  api.mark(owner)
  return true
end
function M.write(session, api)
  if not session.dirty then return true end
  session.write_stage='validating';session.write_attempt=nil
  local ok,next_raw=pcall(M.serialize,session.doc)
  if not ok then
    session.write_stage='validation_rejected'
    return false,'Could not serialize the local draft: '..tostring(next_raw)
  end
  session.write_attempt=next_raw
  local verified,err=M.parse(next_raw)
  if not verified then
    session.write_stage='validation_rejected'
    return false,'Generated notes failed validation. Native notes were not changed: '..tostring(err)
  end
  -- Exact raw restoration in history_step has its own allow_invalid guard;
  -- only newly generated documents must pass this preflight.
  return M.write_raw(session,api,next_raw)
end
function M.history_new() return {undo={},redo={},key=nil,time=0} end
local function history_push(stack,state)
  stack[#stack+1]=state
  local bytes=0
  for _,item in ipairs(stack) do bytes=bytes+#item.raw end
  while #stack>1 and (#stack>100 or bytes>16*1024*1024) do
    bytes=bytes-#stack[1].raw; table.remove(stack,1)
  end
end
function M.history_record(h,before,after,key,now,action)
  if before.raw==after then return end
  if not (key and h.key==key and now-h.time<0.8 and #h.redo==0) then
    history_push(h.undo,{raw=before.raw,active=before.active,allow_invalid=before.allow_invalid,action=action or 'change'})
  end
  h.redo={}; h.key=key; h.time=now
end
function M.history_step(s,api,direction)
  local h=s.history
  local from=direction<0 and h.undo or h.redo
  local to=direction<0 and h.redo or h.undo
  local target=from[#from]
  if not target then return false end
  local doc,err=M.parse(target.raw)
  if not doc and not target.allow_invalid then return false,err end
  if doc then M.restore_column_views(doc,M.column_view_snapshot(s.doc),false) end
  local before={raw=s.raw,active=s.active,allow_invalid=s.history_readonly,action=target.action}
  local ok,write_err=M.write_raw(s,api,target.raw)
  if not ok then return false,write_err end
  table.remove(from); history_push(to,before)
  h.key=nil;s.input_state=nil;s.doc=doc;s.error=err
  -- Undoing an explicit recovery may restore the exact damaged original.
  -- Show it read-only while preserving Redo; never reinterpret or repair it.
  s.history_readonly=not doc and target.allow_invalid or nil
  s.active=doc and math.min(target.active or 1,#doc.tabs) or 1
  return true
end
-- Determine one contiguous edit without splitting a UTF-8 codepoint.
function M.text_delta(before,after)
  local first=0
  while first<math.min(#before,#after) and before:byte(first+1)==after:byte(first+1) do first=first+1 end
  while first>0 and ((before:byte(first+1) or 0)&0xc0)==0x80 do first=first-1 end
  local tail=0
  while tail<math.min(#before-first,#after-first) and before:byte(#before-tail)==after:byte(#after-tail) do tail=tail+1 end
  while tail>0 and ((before:byte(#before-tail+1) or 0)&0xc0)==0x80 do tail=tail-1 end
  return first,before:sub(first+1,#before-tail),after:sub(first+1,#after-tail)
end
function M.text_edit(h,key,before,after,previous,current,gesture)
  local prior=previous and previous.key==key and previous or nil
  if before==after then
    if not prior or (current and (prior.cursor~=current.cursor or prior.first~=current.first or prior.last~=current.last)) then h.key=nil end
    return nil
  end
  local at,removed,inserted=M.text_delta(before,after)
  -- Repeated letters make a common-prefix diff ambiguous. Prefer the actual
  -- resulting caret when it reconstructs the edit exactly.
  local delta=#after-#before
  if current and delta>0 then
    local pos=current.cursor-delta
    if pos>=0 and pos<=#before and before:sub(1,pos)..after:sub(pos+1,pos+delta)..before:sub(pos+1)==after then
      at,removed,inserted=pos,'',after:sub(pos+1,pos+delta)
    end
  elseif current and delta<0 then
    local pos=current.cursor
    if pos>=0 and pos-delta<=#before and before:sub(1,pos)..before:sub(pos-delta+1)==after then
      at,removed,inserted=pos,before:sub(pos+1,pos-delta),''
    end
  end
  local selected=prior and prior.first~=prior.last
  local action,group
  if gesture=='paste' then action='paste'
  elseif gesture=='cut' then action='cut'
  elseif (selected and #inserted>0) or (#removed>0 and #inserted>0) then action='replace'
  elseif #inserted>0 then
    if inserted=='\n' then action='line_break'
    elseif (utf8.len(inserted) or #inserted)>1 then action='paste'
    else action='typing';group=key..':typing' end
  else
    action='deletion'
    if not selected then
      local backwards=prior and current and prior.cursor>current.cursor
      group=key..(backwards and ':backspace' or ':delete')
    end
  end
  -- Cursor movement and selection replacement cannot merge with earlier typing.
  if not prior or selected then h.key=nil
  elseif group then
    local adjacent=action=='typing' and prior.cursor==at or
      action=='deletion' and (prior.cursor==at or prior.cursor==at+#removed)
    if not adjacent then h.key=nil end
  end
  return group,action
end
-- The storage adapter binds each operation to an explicit, GUID-checked owner.
-- It never resolves the current selection while writing an existing document.
function M.storage(r)
  local A={track_field='P_EXT:PATCH34_PROJECT_NOTES'}
  local function project_valid(p)
    local i=0
    while true do
      local live=r.EnumProjects(i,'')
      if not live then return false end
      if live==p then return true end
      i=i+1
    end
  end
  local function object_guid(kind,obj)
    if kind=='track' then return r.GetTrackGUID(obj) end
    local ok,guid=r.GetSetMediaItemInfo_String(obj,'GUID','',false)
    return ok and guid or nil
  end
  function A.valid(t)
    if not t or not project_valid(t.proj) then return false end
    if t.kind=='project' then return true end
    local typename=t.kind=='track' and 'MediaTrack*' or 'MediaItem*'
    return r.ValidatePtr2(t.proj,t.obj,typename) and object_guid(t.kind,t.obj)==t.guid
  end
  function A.resolve(kind)
    local p=r.EnumProjects(-1,'')
    if not p then return nil,'No project is open.' end
    if kind=='project' then return {kind=kind,proj=p,key=tostring(p)..'/project',undo_flags=8} end
    local count=kind=='track' and r.CountSelectedTracks2(p,true) or r.CountSelectedMediaItems(p)
    if count~=1 then
      local what=kind=='track' and 'track' or 'item'
      return nil,count==0 and ('Select one '..what..' in REAPER to open its notes.')
        or ('Select a single '..what..' to edit its notes ('..count..' selected).')
    end
    local obj=kind=='track' and r.GetSelectedTrack2(p,0,true) or r.GetSelectedMediaItem(p,0)
    local typename=kind=='track' and 'MediaTrack*' or 'MediaItem*'
    if not obj or not r.ValidatePtr2(p,obj,typename) then return nil,'The selected object is no longer available.' end
    local guid=object_guid(kind,obj)
    if not guid or guid=='' then return nil,'Could not identify the selected object.' end
    return {kind=kind,proj=p,obj=obj,guid=guid,key=tostring(p)..'/'..kind..'/'..guid,
      undo_flags=kind=='track' and 1 or 4}
  end
  function A.read(t)
    assert(A.valid(t),'The note owner is no longer available.')
    if t.kind=='project' then return r.GetSetProjectNotes(t.proj,false,'') end
    if t.kind=='item' then
      local ok,value=r.GetSetMediaItemInfo_String(t.obj,'P_NOTES','',false)
      assert(ok,'Could not read item notes.'); return value or ''
    end
    local ok,value=r.GetSetMediaTrackInfo_String(t.obj,A.track_field,'',false)
    -- A valid track may not have our extension field until its first edit.
    if not ok and (value==nil or value=='') then return '' end
    assert(ok,'Could not read track notes.'); return value or ''
  end
  function A.write(t,value)
    if not A.valid(t) then return false,'The note owner is no longer available.' end
    if t.kind=='project' then r.GetSetProjectNotes(t.proj,true,value);return true end
    local ok
    if t.kind=='item' then
      ok=r.GetSetMediaItemInfo_String(t.obj,'P_NOTES',value,true)
    else
      ok=r.GetSetMediaTrackInfo_String(t.obj,A.track_field,value,true)
    end
    return ok,not ok and 'REAPER could not write these notes.' or nil
  end
  function A.mark(t)
    r.MarkProjectDirty(t.proj)
    if t.kind=='item' and A.valid(t) then r.UpdateItemInProject(t.obj) end
  end
  function A.title(t,translate)
    -- Translate only owned labels/defaults, never the assembled user title.
    local tr=translate or function(text) return text end
    if not A.valid(t) then return tr('Object unavailable') end
    if t.kind=='project' then
      local name=r.GetProjectName(t.proj,'')
      return name~='' and name or tr('Untitled project')
    elseif t.kind=='track' then
      local _,name=r.GetTrackName(t.obj)
      local number=math.floor(r.GetMediaTrackInfo_Value(t.obj,'IP_TRACKNUMBER'))
      return number<1 and tr('Master track') or
        (tr('Track')..' '..number..': '..(name~='' and name or tr('Untitled')))
    end
    local take=r.GetActiveTake(t.obj)
    local name=take and r.GetTakeName(take) or tr('Empty item')
    local position=r.GetMediaItemInfo_Value(t.obj,'D_POSITION')
    return ('%s: %s  |  %.3f%s'):format(tr('Item'),name or tr('Untitled'),position,tr(' s'))
  end
  return A
end
-- Plain-text adaptation of Viewer's visual-line layout and UTF-8 token chunks.
-- Soft wraps affect display only: no whitespace or source text is rewritten.
function M.wrap_read(text,width,measure)
  local out={}
  width=math.max(1,width)
  local function char_end(value,pos)
    local b=value:byte(pos)
    local n=b>=0xF0 and 4 or b>=0xE0 and 3 or b>=0xC0 and 2 or 1
    return math.min(#value,pos+n-1)
  end
  for _,raw in ipairs(lines(norm(text))) do
    local current=''
    local pos=1
    while pos<=#raw do
      local a,b=raw:find('%s+',pos)
      if a~=pos then a,b=raw:find('%S+',pos) end
      local token=raw:sub(a,b)
      if measure(current..token)<=width then current=current..token
      else
        if current~='' then out[#out+1]=current;current='' end
        -- Viewer find_link_chunk_fit: advance on UTF-8 boundaries and always
        -- consume at least one character, even in a column narrower than it.
        local start=1
        while start<=#token do
          local best,i=nil,start
          while i<=#token do
            local finish=char_end(token,i)
            if measure(token:sub(start,finish))>width then break end
            best=finish;i=finish+1
          end
          best=best or char_end(token,start)
          local chunk=token:sub(start,best)
          if best<#token then out[#out+1]=chunk else current=chunk end
          start=best+1
        end
      end
      pos=b+1
    end
    out[#out+1]=current
  end
  return out
end

-- Recovery is an export, never a write to a note owner. Keep each source
-- separately: a crash may interrupt serialization, a host write, or readback.
function M.pending_changed(pending)
  if type(pending)~='table' then return false end
  if pending.kind=='select' then
    local original=pending.target
    if not original then return false end
    if pending.label~=original.label or pending.selected~=original.selected
        or #pending.options~=#original.options then return true end
    for i,option in ipairs(pending.options) do
      if option~=original.options[i] then return true end
    end
    return false
  end
  if type(pending.value)~='string' then return false end
  if pending.original~=nil then return pending.value~=pending.original end
  if pending.kind=='import' or pending.kind=='new_tab' then return pending.value~='' end
  -- Rename dialogs and the retained inline-rename path share this baseline.
  if pending.target and type(pending.target.name)=='string' then
    return pending.value~=pending.target.name
  end
  return false
end
function M.recovery_snapshot(s,baseline,pending)
  local data={baseline=baseline or (s and s.raw) or '',
    stage=s and s.write_stage or 'not attempted',
    attempted=s and s.write_attempt or nil}
  if s and s.doc then
    local ok,raw=pcall(M.serialize,s.doc)
    if ok then
      data.draft=raw
      local parsed,err=M.parse(raw)
      data.draft_valid=parsed~=nil;data.draft_error=err
    else data.draft_error=tostring(raw) end
  end
  if pending then
    local ok,text=pcall(function()
      if pending.kind=='select' then
        return 'Field name / Название поля:\n'..pending.label..
          '\n\nOptions / Варианты:\n'..table.concat(pending.options,'\n')..
          '\n\nSelected option / Выбранный вариант:\n'..tostring(pending.selected)
      end
      return pending.value
    end)
    if ok and type(text)=='string' then data.pending=text end
  end
  return data
end
function M.export_recovery(data,write_file,report)
  local result={saved={},errors={}}
  local files={{'baseline.notes',data.baseline},{'draft.notes',data.draft},
    {'attempt.notes',data.attempted},{'pending.txt',data.pending},{'report.txt',report}}
  for _,entry in ipairs(files) do
    if type(entry[2])=='string' then
      local ok,written,err=pcall(write_file,entry[1],entry[2])
      if ok and written then result.saved[#result.saved+1]=entry[1]
      else result.errors[#result.errors+1]=entry[1]..': '..tostring(ok and err or written) end
    end
  end
  return result
end
function M.read_recovery_file(path,open_file)
  -- A plain baseline is legitimate, but diagnostic/pending files are not notes.
  if type(path)~='string' or not path:lower():match('%.notes$') then return nil,'Choose a .notes recovery file.' end
  local f,err=(open_file or io.open)(path,'rb')
  if not f then return nil,tostring(err) end
  local ok,raw=pcall(f.read,f,'*a')
  local close_ok,closed,close_error=pcall(f.close,f)
  if not ok or type(raw)~='string' then return nil,tostring(raw) end
  if not close_ok then return nil,tostring(closed) end
  if not closed then return nil,tostring(close_error) end
  local doc,parse_error=M.parse(raw)
  if not doc then return nil,parse_error end
  return {document=doc,raw=raw,path=path}
end

-- Maintenance is incremental: visiting more owners must not add an unbounded
-- scan to every frame. A cursor key avoids a second cache retaining sessions.
function M.sweep_sessions(sessions,state,active,valid,on_remove,budget)
  if state.cursor and not sessions[state.cursor] then state.cursor=nil end
  local checked=0
  for _=1,budget do
    local key,cached=next(sessions,state.cursor)
    if not key then state.cursor=nil;break end
    if cached~=active then
      checked=checked+1
      if not valid(cached.target) then
        on_remove(cached)
        sessions[key]=nil
      else state.cursor=key end
    else state.cursor=key end
  end
  return checked
end
function M.suspend_session(s)
  if not s or not s.doc or s.dirty or s.error or s.conflict or s.pending or s.restore_pending or s.undo_due then return false end
  -- raw and both history stacks are retained. Dropping the model also releases
  -- its block keys from the weak read-layout cache when Lua collects them.
  s.column_views=M.column_view_snapshot(s.doc)
  s.doc=nil;s.suspended=true;s.input_state=nil
  s.write_attempt=nil;s.write_stage=nil;s.history.key=nil
  return true
end
function M.resume_session(s)
  if not s.suspended then return true end
  local doc,err=M.parse(s.raw)
  if not doc then return false,err end
  M.restore_column_views(doc,s.column_views,true);s.column_views=nil
  s.doc=doc;s.suspended=nil
  s.active=math.min(s.active or 1,#doc.tabs)
  return true
end

-- Import draft editor. Positions are UTF-8 byte boundaries in the original
-- text. Visual wraps live only in rows and never insert source newlines.
function M.editor_next(text,pos)
  if pos>=#text then return #text end
  local lead=text:byte(pos+1)
  local length=lead<0x80 and 1 or lead>=0xC2 and lead<0xE0 and 2
    or lead>=0xE0 and lead<0xF0 and 3 or lead>=0xF0 and lead<0xF5 and 4 or 1
  if pos+length>#text then return pos+1 end
  for i=2,length do
    local byte=text:byte(pos+i)
    if byte<0x80 or byte>=0xC0 then return pos+1 end
  end
  return pos+length
end
function M.editor_prev(text,pos)
  if pos<=0 then return 0 end
  local at=pos-1
  while at>0 do
    local byte=text:byte(at+1)
    if byte<0x80 or byte>=0xC0 then break end
    at=at-1
  end
  return M.editor_next(text,at)==pos and at or pos-1
end
function M.editor_new(text)
  return {text=text,cursor=0,anchor=0,history=M.history_new(),focused=false,focus_pending=false}
end
function M.editor_range(e) return math.min(e.cursor,e.anchor),math.max(e.cursor,e.anchor) end
function M.editor_move(e,pos,extend,upstream)
  e.cursor=math.max(0,math.min(#e.text,pos))
  if not extend then e.anchor=e.cursor end
  e.upstream=upstream;e.history.key=nil;e.preferred_x=nil
end
function M.editor_replace(e,value,now,gesture,range_first,range_last)
  value=norm(value):gsub('%z','')
  local selected_first,selected_last=M.editor_range(e)
  local first,last=range_first or selected_first,range_last or selected_last
  local text=e.text:sub(1,first)..value..e.text:sub(last+1)
  if text==e.text then return false end
  local previous={key='import',cursor=e.cursor,first=selected_first,last=selected_last}
  local cursor=first+#value
  local current={key='import',cursor=cursor,first=cursor,last=cursor}
  local h=e.history
  local group=M.text_edit(h,'import',e.text,text,previous,current,gesture)
  if not (group and h.key==group and now-h.time<0.8 and #h.redo==0) then
    history_push(h.undo,{raw=e.text,cursor=e.cursor,anchor=e.anchor,upstream=e.upstream})
  end
  h.redo={};h.key=group;h.time=now
  e.text=text;e.cursor=cursor;e.anchor=cursor;e.upstream=nil;e.preferred_x=nil;e.rows=nil
  return true
end
function M.editor_history(e,direction)
  local h=e.history
  local from=direction<0 and h.undo or h.redo
  local to=direction<0 and h.redo or h.undo
  local state=from[#from]
  if not state then return false end
  history_push(to,{raw=e.text,cursor=e.cursor,anchor=e.anchor,upstream=e.upstream})
  table.remove(from)
  e.text=state.raw;e.cursor=state.cursor;e.anchor=state.anchor;e.upstream=state.upstream
  e.rows=nil;e.preferred_x=nil;h.key=nil
  return true
end
function M.editor_word(text,pos,direction)
  local function space(at)
    local nextpos=M.editor_next(text,at)
    return text:sub(at+1,nextpos):match('^%s+$')~=nil
  end
  if direction<0 then
    while pos>0 and space(M.editor_prev(text,pos)) do pos=M.editor_prev(text,pos) end
    while pos>0 and not space(M.editor_prev(text,pos)) do pos=M.editor_prev(text,pos) end
  else
    while pos<#text and not space(pos) do pos=M.editor_next(text,pos) end
    while pos<#text and space(pos) do pos=M.editor_next(text,pos) end
  end
  return pos
end
function M.editor_rows(text,width,measure)
  local rows={}
  local first,pos,x,space,space_x=0,0,0,nil,nil
  width=math.max(1,width)
  local function push(last,hard,row_width)
    rows[#rows+1]={first=first,last=last,hard=hard,width=row_width}
    first=last+(hard and 1 or 0);pos=first;x=0;space=nil;space_x=nil
  end
  while pos<#text do
    local nextpos=M.editor_next(text,pos)
    local char=text:sub(pos+1,nextpos)
    if char=='\n' then push(pos,true,x)
    else
      local w=measure(char)
      if x+w>width and pos>first and not char:match('^%s+$') then
        if space and space>first then push(space,false,space_x)
        else push(pos,false,x) end
      else
        x=x+w;pos=nextpos
        if char:match('^%s+$') then space=pos;space_x=x end
      end
    end
  end
  rows[#rows+1]={first=first,last=#text,hard=false,width=x}
  return rows
end
function M.editor_row(e,rows)
  -- Binary search keeps vertical movement fast in long imported documents.
  local lo,hi=1,#rows
  while lo<hi do
    local mid=math.floor((lo+hi+1)/2)
    if rows[mid].first<=e.cursor then lo=mid else hi=mid-1 end
  end
  if e.upstream and lo>1 and rows[lo].first==e.cursor and not rows[lo-1].hard then lo=lo-1 end
  return lo
end
function M.editor_x(text,row,pos,measure)
  local x,at=0,row.first
  while at<math.min(pos,row.last) do
    local after=M.editor_next(text,at)
    x=x+measure(text:sub(at+1,after));at=after
  end
  return x
end
function M.editor_hit(text,row,x,measure)
  local at,previous=row.first,0
  while at<row.last do
    local after=M.editor_next(text,at)
    local advance=measure(text:sub(at+1,after))
    if x<previous+advance*0.5 then return at end
    previous=previous+advance;at=after
  end
  return row.last
end
function M.editor_vertical(e,rows,delta,measure)
  local row=M.editor_row(e,rows)
  local x=e.preferred_x or M.editor_x(e.text,rows[row],e.cursor,measure)
  local target=math.max(1,math.min(#rows,row+delta))
  local pos=M.editor_hit(e.text,rows[target],x,measure)
  return pos,x,pos==rows[target].last and not rows[target].hard
end

-- Model locations are resolved again at delivery time. Payloads never contain
-- serialized note data, and a stale owner/column cannot delete the source.
function M.note_location(doc,block)
  for ti,tab in ipairs(doc.tabs) do
    for _,column in ipairs(tab.columns) do
      for i,candidate in ipairs(column.blocks) do
        if candidate==block then return tab,column,i,ti end
      end
    end
  end
end
function M.note_column(doc,column)
  for ti,tab in ipairs(doc.tabs) do
    for _,candidate in ipairs(tab.columns) do if candidate==column then return tab,ti end end
  end
end
function M.note_drop_plan(doc,block,target,anchor,after,grouped,hide)
  local _,source,from=M.note_location(doc,block)
  local tab,ti=M.note_column(doc,target)
  if not source or not tab or anchor==block then return nil end
  if source==target and not anchor then
    local later=false
    for i=from+1,#target.blocks do
      local candidate=target.blocks[i]
      if M.visible(candidate,hide) and (not grouped or M.completed(candidate)==M.completed(block)) then later=true;break end
    end
    if not later then return nil end
  end
  local at=#target.blocks+1
  if anchor then
    local found
    for i,candidate in ipairs(target.blocks) do if candidate==anchor then found=i;break end end
    if not found or (grouped and M.completed(block)~=M.completed(anchor)) then return nil end
    at=found+(after and 1 or 0)
  end
  if source==target and from<at then at=at-1 end
  if source==target and from==at then return nil end
  return {source=source,from=from,target=target,at=at,tab=tab,tab_index=ti}
end
function M.note_move(doc,block,target,anchor,after,grouped,hide)
  local plan=M.note_drop_plan(doc,block,target,anchor,after,grouped,hide)
  if not plan then return false end
  table.remove(plan.source.blocks,plan.from)
  table.insert(plan.target.blocks,plan.at,block)
  return true,plan.tab,plan.tab_index
end

-- One insertion position for every boundary between visible notes (N+1).
-- Geometry is read from already rendered blocks, not from overlay ImGui items.
-- A single section-level native drag target consumes the selected boundary.
function M.note_insertion_slot(rects,mouse_y)
  if #rects==0 then return nil,false,nil end
  local best_distance,best_anchor,best_after,best_y=math.huge,nil,false,nil
  for i=1,#rects+1 do
    local anchor,after,y
    if i<=#rects then
      anchor=rects[i].block;after=false
      if i==1 then y=rects[1].y
      else y=(rects[i-1].bottom+rects[i].y)*0.5 end
    else
      anchor=rects[#rects].block;after=true
      y=rects[#rects].bottom+2
    end
    local distance=math.abs(mouse_y-y)
    if distance<best_distance then
      best_distance=distance;best_anchor=anchor;best_after=after;best_y=y
    end
  end
  return best_anchor,best_after,best_y
end

if ... == '__test' then return M end

if not reaper.ImGui_GetBuiltinPath then
  reaper.MB('Install ReaImGui 0.10 or newer through ReaPack, then run this script again.', 'ReaNotepad', 0)
  return
end
package.path = reaper.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local loaded, ImGui = pcall(function() return require('imgui')('0.10') end)
if not loaded then
  reaper.MB('ReaImGui 0.10+ is required.\n\n' .. tostring(ImGui), 'ReaNotepad', 0)
  return
end
local TITLE, PREF = 'ReaNotepad', 'Patch34_Project_Notes'
-- Compatibility identifiers: existing notes, preferences and window settings.
local CONTEXT_NAME = 'Patch34 Project Notes'
local startup_layout_frames=0
local STARTUP_LAYOUT_FRAMES=UI_METRICS.startup_layout_warmup_frames
local ctx, font, ui_font, heading_bold_font, input_callback
local sessions, session, modal, open_modal = {}, nil, nil, nil
local session_sweep={cursor=nil}
local SESSION_CHECKS_PER_FRAME=8
local REPOSITORY_URL='https://github.com/patch-34/reanotepad'
local epoch, changed, undo_boundary, force_tab = 0, false, false, nil
local edit_key, edit_action, history_request
local escape_pressed = false
local bulk_selection
local UI
local frame_checkpoint, crashed, recovery_sequence = nil, false, 0
local language=reaper.GetExtState(PREF,'language')=='ru' and 'ru' or 'en'
local pending_language, pending_theme
local RU = {
  ["Select elements..."]="Выделить элементы…",
  ["Selected: %d"]="Выбрано: %d",
  ["All"]="Все", ["Clear selection"]="Снять",
  ["Color..."]="Цвет…", ["Color marker"]="Цветовая метка",
  ["No marker"]="Без метки", ["Red"]="Красная", ["Orange"]="Оранжевая",
  ["Yellow"]="Жёлтая", ["Green"]="Зелёная", ["Blue"]="Синяя", ["Purple"]="Фиолетовая",
  ["Delete selected elements?"]="Удалить выделенные элементы?",
  ["Delete %d selected elements?"]="Удалить выделенные элементы: %d?",

  ["Open recovery copy..."]="Открыть аварийную копию…",
  ["Restore recovery copy"]="Восстановление аварийной копии",
  ["Restore"]="Восстановить",
  ["This replaces all notes of the current owner. Review the copy; it may contain an incomplete operation. Undo is available after restoration."]="Будут заменены все заметки текущего объекта. Проверь копию: операция могла быть прервана. После восстановления доступна отмена.",
  ["Recovery copies: "]="Аварийные копии: ",
  ["Copy recovery path"]="Копировать путь к копиям",
  ["Recovery export failed. See the REAPER console."]="Не удалось сохранить все аварийные копии. Подробности — в консоли REAPER.",
  ["Choose a .notes recovery file."]="Выбери аварийную копию с расширением .notes.",
  ["Could not open recovery copy: "]="Не удалось открыть аварийную копию: ",
  ["Object unavailable"]="Объект недоступен",
  ["Master track"]="Мастер-дорожка",
  ["Untitled"]="Без названия",
  ["Empty item"]="Пустой айтем",
  [" s"]=" с",
  ["Edit"]="Правка",
  ["Tab"]="Вкладка",
  ["Add"]="Добавить",
  ["View"]="Вид",
  ["Help"]="Справка",
  ["Help..."]="Справка…",
  ["About..."]="О программе…",
  ["Language"]="Язык",
  ["Repository not created yet"]="Репозиторий ещё не создан",
  ["Confirm deletion"]="Подтверждение удаления",
  ["Paste text or a numbered list on the left. The notes to be added appear on the right."]="Вставь текст или нумерованный список слева. Справа появятся заметки, которые будут добавлены.",
  ["Separate paragraphs with a blank line. In a numbered list, start each new item on a new line."]="Разделяй абзацы пустой строкой. В нумерованном списке начинай каждый новый пункт с новой строки.",
  ["Source text"]="Исходный текст",
  ["Destination tab"]="Вкладка для импорта",
  ["Paste text to see the resulting notes."]="Вставь текст, чтобы увидеть будущие заметки.",
  ["Undo"]="Отменить",
  ["Redo"]="Повторить",
  ["New tab"]="Новая вкладка", ["Switch to tab"]="Открыть вкладку",
  ["Rename"]="Переименовать",
  ["Move left"]="Сдвинуть влево",
  ["Move right"]="Сдвинуть вправо",
  ["Delete tab..."]="Удалить вкладку…",
  ["Column"]="Колонка", ["Tabs"]="Вкладки", ["New group"]="Новая группа",
  ["Groups"]="Группы", ["Group"]="Группа", ["New group below"]="Новая группа ниже",
  ["Rename group"]="Переименовать группу", ["Delete group..."]="Удалить группу…",
  ["Delete group?"]="Удалить группу?", ["Delete this group and its contents?"]="Удалить эту группу вместе с содержимым?",
  ["Move to group"]="В другую группу", ["Group header color"]="Цвет заголовка группы",
  ["No color"]="Без цвета",
  ["Add checkbox"]="Добавить чекбокс",
  ["Remove checkbox"]="Убрать чекбокс",
  ["Add checkbox note"]="Добавить заметку с чекбоксом",
  ["Note with checkbox"]="Заметка с чекбоксом",
  ["Import text..."]="Импорт текста…",
  ["Text"]="Текст",
  ["Checkbox"]="Чекбокс",
  ["Dropdown"]="Выпадающий список",
  ["Move up"]="Выше",
  ["Move down"]="Ниже",
  ["Move to column"]="В другую колонку",
  ["Edit field..."]="Изменить поле…",
  ["Delete..."]="Удалить…",
  ["Edit..."]="Изменить…",
  ["Rename column..."]="Переименовать колонку…",
  ["Move column left"]="Колонку влево",
  ["Move column right"]="Колонку вправо",
  ["Delete column..."]="Удалить колонку…",
  ["Hide completed"]="Скрыть выполненные",
  ["Completed notes last"]="Выполненные в конце",
  ["Color marker style"]="Оформление цветовых меток",
  ["Note spacing"]="Интервал между заметками",
  ["Gap above and below the separator"]="Отступ над и под сепаратором",
  ["Reset spacing"]="Сбросить интервал",
  ["Left strip"]="Полоска слева",
  ["Whole note"]="Фон всей заметки",
  ["Font"]="Шрифт",
  [" px"]=" px",
  ["Dock to docker"]="Закрепить в докере",
  ["Project"]="Проект",
  ["Track"]="Дорожка",
  ["Item"]="Айтем",
  ["Dark"]="Тёмная",
  ["Untitled project"]="Проект без названия",
  ["Apply"]="Применить",
  ["Cancel"]="Отмена",
  ["Close"]="Закрыть",
  ["Delete"]="Удалить",
  ["Import"]="Импорт",
  ["+ Option"]="+ Вариант",
  ["Remove numbering"]="Удалять нумерацию",
  ["Split at timecodes"]="Разделять по таймкодам",
  ["No notes yet"]="Заметок пока нет",
  ["Drag to move note"]="Перетащи, чтобы переместить заметку",
  ["Expand column"]="Развернуть колонку",
  ["Minimize column"]="Свернуть колонку",
  ["Columns"]="Колонки",
  ["New column"]="Новая колонка",
  ["Notes"]="Заметки",
  ["New tab below"]="Добавить вкладку ниже",
  ["Delete note by dropping here"]="Перетащи сюда заметку, чтобы удалить",
  ["Drop to delete"]="Удалить",
  ["Rename tab"]="Переименовать вкладку",
  ["Move to tab"]="Переместить во вкладку",
  ["Drag or click an icon, then choose a tab."]="Перетащи значок или нажми его и выбери вкладку.",
  ["Choose a tab. Esc cancels."]="Выбери вкладку. Esc — отмена.",
  ["Choose a group. Esc cancels."]="Выбери группу. Esc — отмена.",
  ["Drag or click an icon, then choose a group."]="Перетащи значок или нажми его и выбери группу.",
  ["Click a highlighted tab heading to add here."]="Нажми на подсвеченный заголовок вкладки, чтобы добавить сюда.",
  ["Click or drop into this tab to add here."]="Нажми или перетащи элемент в эту вкладку, чтобы добавить его.",
  ["Discard note changes?"]="Отменить изменения заметки?",
  ["The note has unsaved changes. Discard them?"]="В заметке есть несохранённые изменения. Отменить их?",
  ["Discard changes"]="Отменить изменения",
  ["Continue editing"]="Продолжить правку",
  ["Click to go to timecode"]="Нажми, чтобы перейти к таймкоду",
  ["Timeline position"]="Позиция на таймлайне",
  ["Timecodes: MM:SS, HH:MM:SS or HH:MM:SS:FF (project FPS); optional milliseconds without frames. Click the clock/time indicator to jump and focus arrange."]="Таймкоды: ММ:СС, ЧЧ:ММ:СС или ЧЧ:ММ:СС:КК (кадры по FPS проекта); миллисекунды — без кадров. Нажми на значок часов или время для перехода и возврата фокуса на таймлайн.",
  ["Preview: %d notes"]="Предпросмотр: заметок — %d",
  ["Field name"]="Название поля",
  ["Options (select a circle to set the current value)"]="Варианты (отметь кружком текущее значение)",
  ["Edit dropdown"]="Редактирование списка",
  ["Rename column"]="Название колонки",
  ["Delete item?"]="Удалить элемент?",
  ["Delete note?"]="Удалить заметку?",
  ["Delete this note and its contents?"]="Удалить эту заметку?",
  ["Delete tab?"]="Удалить вкладку?",
  ["Delete column?"]="Удалить колонку?",
  ["Delete this tab and its contents?"]="Удалить эту вкладку вместе с содержимым?",
  ["Delete this column and its contents?"]="Удалить эту колонку вместе с содержимым?",
  ["Import text"]="Импорт текста",
  ["Delete this item and its contents?"]="Удалить этот элемент вместе с содержимым?",
  ["Empty column"]="Пустая колонка",
  ["Completed items hidden"]="Выполненные пункты скрыты",
  ["(Empty text block)"]="(Пустой текстовый блок)",
  ["Switching note owner..."]="Переключение заметок…",
  ["Select an object in REAPER."]="Выбери объект в REAPER.",
  ["No project is open."]="Нет открытого проекта.",
  ["The selected object is no longer available."]="Выбранный объект больше недоступен.",
  ["Could not identify the selected object."]="Не удалось определить выбранный объект.",
  ["Copy local draft"]="Копировать черновик",
  ["Copy original notes"]="Копировать исходные заметки",
  ["Reload native notes..."]="Перечитать сохранённые заметки…",
  ["Open original as plain text..."]="Открыть исходный текст…",
  ["Native notes changed while this draft was being edited. Automatic writing is paused."]="Сохранённые заметки изменились во время редактирования. Автоматическая запись приостановлена.",
  ["Native notes changed. The local draft has not been written."]="Сохранённые заметки изменились. Локальный черновик не записан.",
  ["The note owner was removed or its project was closed."]="Объект удалён или его проект закрыт.",
  ["REAPER could not write these notes."]="REAPER не смог записать заметки.",
  ["REAPER did not return the complete saved document."]="REAPER вернул неполный сохранённый документ.",
  ["Unsupported notes format. Original notes were not changed."]="Формат заметок не поддерживается. Исходные заметки не изменены.",
  ["New task"]="Новая задача",
  ["Status"]="Статус",
  ["Not started"]="Не начато",
  ["In progress"]="В работе",
  ["Done"]="Готово",
  ["New note"]="Новая заметка",
  ["New option"]="Новый вариант",
  ["Version: "]="Версия: ",
  ["Notes for projects, tracks and items."]="Заметки проектов, дорожек и айтемов.",
}
local function tr(text) return language=='ru' and (RU[text] or text) or text end
local function ui_label(text) return tr(text)..'###'..text end
local theme = reaper.GetExtState(PREF,'theme')
local size = math.max(UI_METRICS.note_text_min_size,math.min(UI_METRICS.note_text_max_size,
  tonumber(reaper.GetExtState(PREF,'size')) or UI_METRICS.note_text_default_size))
local hide_completed=reaper.GetExtState(PREF,'hide_completed')=='1'
local completed_last=reaper.GetExtState(PREF,'completed_last')=='1'
local marker_style=reaper.GetExtState(PREF,'marker_style')=='fill' and 'fill' or 'strip'
local note_spacing=tonumber(reaper.GetExtState(PREF,'note_spacing')) or UI_METRICS.note_spacing_default
note_spacing=math.floor(math.max(UI_METRICS.note_spacing_min,math.min(UI_METRICS.note_spacing_max,note_spacing)))
local dock_request
local last_docker=tonumber(reaper.GetExtState(PREF,'last_docker')) or -1
if last_docker>-1 or last_docker< -16 then last_docker=-1 end
local scope=reaper.GetExtState(PREF,'scope')
if scope~='track' and scope~='item' then scope='project' end
local scope_labels={project='Project',track='Track',item='Item'}
local selection_message
local api=M.storage(reaper)
-- Read FPS from the actual note owner's project, not the currently active tab.
-- A second return value tells whether its SMPTE timecode is drop-frame.
local function project_timecode_settings()
  if not session or not session.proj then return nil,false end
  return reaper.TimeMap_curFrameRate(session.proj)
end
-- Short component aliases are derived once, never redefined or overwritten.
local themes={}
for key,v in pairs(VIEWER_THEMES) do
  themes[key]={name=v.label,bg=v.C_PAPER,paper=v.C_FRAME,chrome=v.C_CHROME,
    text=v.C_TEXT,dim=v.C_DIM,line=v.C_LINE,hover=v.C_HEAD,
    accent=v.C_VIEW_SLIDER_FILL,viewer=v}
end
if not themes[theme] then theme='paper' end
local function pref(key,value) reaper.SetExtState(PREF,key,tostring(value),true) end
local function label(s) return (s:gsub('##','#\226\128\139#')) end
local function touch(key,action)
  if not changed then edit_key=key elseif edit_key~=key then edit_key=nil end
  if not changed then edit_action=action or 'change' elseif edit_action~=action then edit_action='change' end
  changed=true
end
local function recovery_root()
  return reaper.GetResourcePath()..'/Data/Patch34_Project_Notes_Recovery'
end
local function save_recovery(s,reason,baseline,pending)
  -- Uncommitted note text lives outside s.doc. Every recovery path must
  -- include the current owner's draft, not only modal/rename text.
  if pending==nil and UI and UI.recovery_pending then pending=UI.recovery_pending(s) end
  local data=M.recovery_snapshot(s,baseline,pending)
  local ok,result=pcall(function()
    recovery_sequence=recovery_sequence+1
    local stamp=os.date('%Y%m%d-%H%M%S')..'-'..math.floor(reaper.time_precise()*1000000)..'-'..recovery_sequence
    local folder=recovery_root()..'/'..stamp
    -- Never reuse a directory that already contains recovery files.
    local suffix=0
    while reaper.EnumerateFiles(folder,0)~=nil do
      suffix=suffix+1;folder=recovery_root()..'/'..stamp..'-'..suffix
    end
    assert(reaper.RecursiveCreateDirectory(folder,0)>0,'Could not create recovery directory')
    local function write_file(name,bytes)
      local path=folder..'/'..name
      local f,err=io.open(path..'.partial','wb')
      if not f then return nil,err end
      local written,write_error=f:write(bytes)
      local closed,close_error=f:close()
      if not written or not closed then return nil,write_error or close_error end
      local verify,read_error=io.open(path..'.partial','rb')
      if not verify then return nil,read_error end
      local actual=verify:read('*a');verify:close()
      if actual~=bytes then return nil,'Incomplete recovery file' end
      return os.rename(path..'.partial',path)
    end
    local target=s and s.target or {}
    local title_ok,title=pcall(api.title,target)
    local report=table.concat({
      'ReaNotepad '..VERSION..' — recovery / аварийная копия',
      'Owner / Объект: '..(title_ok and title or tostring(target.key)),
      'Kind / Тип: '..tostring(target.kind),'GUID: '..tostring(target.guid),
      'Session key / Ключ сеанса: '..tostring(target.key),
      'Write stage / Этап записи: '..tostring(data.stage),
      'Draft parses / Черновик читается: '..tostring(data.draft_valid),
      'Draft error / Ошибка черновика: '..tostring(data.draft_error or ''),
      '',
      'baseline.notes: last known notes before this operation / заметки до операции.',
      'draft.notes: in-memory document, possibly partial / черновик, операция могла быть прервана.',
      'attempt.notes: exact attempted write, if any / содержимое попытки записи, если она была.',
      'pending.txt: unapplied note, popup or rename text / неприменённый текст заметки, окна или переименования.',
      'Restore: select the intended Project/Track/Item, then Edit > Open recovery copy.',
      'Review the .notes file in the preview before Restore. No automatic restoration.',
      'Восстановление: выбери нужный проект/дорожку/айтем → Правка → Открыть аварийную копию.',
      'Проверь файл .notes в предпросмотре перед восстановлением. Автоматической подмены нет.',
      '',
      'The error handler does not retry or roll back host writes.',
      'Обработчик ошибки не повторяет и не откатывает запись в REAPER.',
      'If the host write failed mid-call, inspect the actual native notes.',
      'Если сбой произошёл внутри записи, проверь фактическое содержимое заметок.',
      '',tostring(reason)},'\n')
    local exported=M.export_recovery(data,write_file,report)
    exported.folder=folder
    return exported
  end)
  if not ok then result={saved={},errors={tostring(result)}} end
  if s then s.recovery=result end
  local message=result.folder and ('Recovery / Аварийные копии: '..result.folder..'\n') or ''
  if #result.errors>0 then
    message=message..table.concat(result.errors,'\n')..'\n'
    -- Last-resort copy surface when the recovery disk is unavailable.
    message=message..'\nUnsaved recovery draft / Несохранённый черновик:\n'..(data.draft or data.attempted or data.baseline)..'\n'
    if data.pending then message=message..'\nPending text / Неприменённый текст:\n'..data.pending..'\n' end
  end
  pcall(reaper.ShowConsoleMsg,message)
  return result
end

local function save_pending_recovery(s,reason)
  local pending=UI and UI.recovery_pending and UI.recovery_pending(s,true)
  if pending then return save_recovery(s,reason,s.raw,pending) end
end
local function load_notes(s,raw)
  s.raw=raw; s.doc,s.error=M.parse(raw); s.dirty=false; s.conflict=nil; s.undo_due=nil
  s.active=math.min(s.active or 1,s.doc and #s.doc.tabs or 1)
  s.history=M.history_new(); s.pending=nil;s.input_state=nil;s.suspended=nil;s.column_views=nil
  s.recovery=nil;s.write_attempt=nil;s.write_stage=nil
  s.history_readonly=nil;s.restore_pending=nil
  epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil
end
local function flush_undo(s)
  if s and s.undo_due then
    if api.valid(s.target) and not s.conflict then
      reaper.Undo_OnStateChangeEx2(s.proj,'Edit '..s.target.kind..' notes',s.target.undo_flags,-1)
    end
    s.undo_due=nil
  end
end
local function discard_removed_session(cached)
  if cached.dirty and not cached.recovery then save_recovery(cached,'Owner removed / Объект удалён') end
end
local function sync_project()
  local target,message=api.resolve(scope)
  selection_message=message
  local edit=UI and UI.note_edit
  if edit and edit.owner==session and session and session.target
      and (not target or target.key~=session.target.key) then
    if api.valid(session.target) then
      local native=api.read(session.target)
      if native==session.raw and not session.conflict and not session.error then
        local before={raw=session.raw,active=session.active,allow_invalid=session.history_readonly}
        UI.end_note_edit()
        if changed then
          session.dirty=true
          local ok,err=M.write(session,api)
          if ok then
            M.history_record(session.history,before,session.raw,nil,reaper.time_precise(),'edit_note')
            session.undo_due=reaper.time_precise()+0.8
          else
            session.error=err;save_recovery(session,err,before.raw)
          end
          changed=false;edit_key=nil;edit_action=nil
        end
      else
        save_recovery(session,'Notes changed during an active edit / Заметки изменились во время правки',
          session.raw,{value=edit.value})
        UI.end_note_edit(true)
      end
    else
      save_recovery(session,'Note owner removed during active edit / Объект заметки удалён во время правки',
        session.raw,{value=edit.value})
      UI.end_note_edit(true)
    end
  end
  if session and (not target or target.key~=session.target.key) then
    save_pending_recovery(session,'Note owner changed during an active draft / Объект изменён во время редактирования черновика')
  end
  -- The selected/previous owner never waits for the background sweep.
  if session and not api.valid(session.target) then
    discard_removed_session(session);sessions[session.target.key]=nil;session=nil
    epoch=epoch+1; bulk_selection=nil;modal=nil;open_modal=nil;force_tab=nil
  end
  local chosen=target and sessions[target.key]
  if chosen and chosen~=session and not api.valid(chosen.target) then
    discard_removed_session(chosen);sessions[target.key]=nil
  end
  M.sweep_sessions(sessions,session_sweep,session,api.valid,discard_removed_session,SESSION_CHECKS_PER_FRAME)
  if not target then
    if session then
      flush_undo(session);M.suspend_session(session);session=nil
      epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; force_tab=nil
    end
    return true
  end
  if not session or session.target.key~=target.key then
    flush_undo(session)
    if session then
      session.history.key=nil;session.input_state=nil
      M.suspend_session(session)
    end
    session=sessions[target.key]
    if not session then
      session={proj=target.proj,target=target};sessions[target.key]=session
      load_notes(session,api.read(target))
    end
    session.history.key=nil;session.input_state=nil
    epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; force_tab=nil
  end
  local native=api.read(session.target)
  -- An unresolved external conflict must remain read-only until the user
  -- explicitly reloads, even if the draft itself had not been written yet.
  if session.conflict and native~=session.raw then return true end
  if session.conflict and native==session.raw then session.conflict=nil end
  if not session.dirty and native~=session.raw then
    local pending=UI and UI.recovery_pending(session,true)
    if pending then
      save_pending_recovery(session,'External edit during an active draft / Внешняя правка во время редактирования черновика')
      if UI.note_edit and UI.note_edit.owner==session then UI.end_note_edit(true) end
      -- Preserve the local model and exported draft until explicit reload.
      -- draw_modal closes its stale native popup from the stable root scope.
      modal=nil;open_modal=nil
      session.conflict=native
    else
      if UI and UI.note_edit and UI.note_edit.owner==session then UI.end_note_edit(true) end
      load_notes(session,native)
    end
  elseif session.dirty and native~=session.raw then session.conflict=native
  elseif session.suspended then
    local ok,err=M.resume_session(session)
    if not ok then session.error=err end
  end
  return true
end
local function request_modal(m)
  if UI then UI.end_note_edit() end
  if session then session.history.key=nil;session.input_state=nil end
  m.focus=true; modal=m; open_modal=m.title
end
local function begin_action_popup(id)
  -- Action menus size to content, like the Viewer menus. Editors stay fixed-size.
  ImGui.SetNextWindowSize(ctx,0,0,ImGui.Cond_Always)
  if not ImGui.BeginPopup(ctx,id,ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings) then return false end
  if escape_pressed then
    ImGui.CloseCurrentPopup(ctx); ImGui.EndPopup(ctx); return false
  end
  return true
end
local function confirm_delete(action,object)
  object=object or 'item'
  request_modal({kind='delete',title='Delete '..object..'?',
    message='Delete this '..object..' and its contents?',action=action,history_action='delete_'..object})
end
local function confirm_tab_delete(target)
  if #session.doc.tabs<=1 then return end
  confirm_delete(function()
    local tabs=session.doc.tabs
    local selected=tabs[session.active]
    for index,tab in ipairs(tabs) do
      if tab==target and #tabs>1 then
        table.remove(tabs,index)
        if selected==target then selected=tabs[math.min(index,#tabs)] end
        for i,t in ipairs(tabs) do if t==selected then session.active=i;break end end
        force_tab=selected.id
        touch(nil,'delete_tab')
        break
      end
    end
  end,'tab')
end
local function clone_select(b)
  local opts={}; for i,v in ipairs(b.options) do opts[i]=v end
  return {kind='select',title='Edit dropdown',target=b,label=b.label,options=opts,selected=b.selected}
end
local function styles()
  local t=themes[theme]
  local v=t.viewer
  local colors={Text=t.text,InputTextCursor=t.text,TextDisabled=t.dim,WindowBg=t.bg,ChildBg=t.paper,PopupBg=t.chrome,
    MenuBarBg=t.chrome,Border=v.C_MENU_BORDER,BorderShadow=0,FrameBg=t.paper,FrameBgHovered=t.paper,
    FrameBgActive=t.paper,Button=v.C_VIEW_BUTTON_FILL,ButtonHovered=v.C_VIEW_BUTTON_HOVER,ButtonActive=v.C_VIEW_BUTTON_ACTIVE,
    Header=v.C_HEAD,HeaderHovered=v.C_HEAD_H,HeaderActive=v.C_HEAD_H,CheckMark=t.accent,
    TitleBg=v.C_CHROME_TITLE,TitleBgActive=v.C_CHROME_DEEP,TitleBgCollapsed=t.chrome,
    Separator=t.line,ScrollbarBg=v.C_SCROLL_BG,ScrollbarGrab=v.C_SCROLL,ScrollbarGrabHovered=v.C_SCROLL_H,
    ScrollbarGrabActive=v.C_SCROLL_A,Tab=t.chrome,TabHovered=t.hover,TabSelected=theme=='dark' and t.hover or t.paper,
    TabDimmed=t.chrome,TabDimmedSelected=theme=='dark' and t.hover or t.paper,
    TabSelectedOverline=t.accent,TextSelectedBg=(t.accent & 0xffffff00)|UI_PALETTE.text_selection_alpha,
    SliderGrab=t.accent,SliderGrabActive=t.accent,
    ModalWindowDimBg=theme=='dark' and UI_PALETTE.modal_dim_dark or UI_PALETTE.modal_dim_light}
  local count,var_count=0,0
  for k,v in pairs(colors) do ImGui.PushStyleColor(ctx,ImGui['Col_'..k],v); count=count+1 end
  local function push_var(...)
    ImGui.PushStyleVar(ctx,...);var_count=var_count+1
  end
  push_var(ImGui.StyleVar_WindowPadding,UI_METRICS.window_pad_x,UI_METRICS.window_pad_y)
  push_var(ImGui.StyleVar_FramePadding,UI_METRICS.frame_pad_x,UI_METRICS.frame_pad_y)
  push_var(ImGui.StyleVar_ItemSpacing,UI_METRICS.item_gap_x,UI_METRICS.item_gap_y)
  push_var(ImGui.StyleVar_ItemInnerSpacing,UI_METRICS.checkbox_label_gap,UI_METRICS.item_gap_y)
  push_var(ImGui.StyleVar_FrameRounding,UI_METRICS.frame_rounding)
  push_var(ImGui.StyleVar_ChildRounding,UI_METRICS.child_rounding)
  push_var(ImGui.StyleVar_FrameBorderSize,UI_METRICS.frame_border_size)
  return count,var_count
end
UI={menu_open=nil,info=nil,open_info=nil,read_cache=setmetatable({},{__mode="k"})}
function UI.recovery_pending(owner,changed_only)
  local pending
  if owner==session and modal then pending=modal
  elseif UI.note_edit and UI.note_edit.owner==owner then pending=UI.note_edit end
  if pending and (not changed_only or M.pending_changed(pending)) then return pending end
end
function UI.source_button(id, label, width, height, selected)
  width,height=math.max(1,width),math.max(1,height)
  local sx, sy = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  local clicked = ImGui.InvisibleButton(
    ctx,
    "##view_button_" .. id,
    width,
    height,
    ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav
  )

  local hovered = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_None)
  local active = ImGui.IsItemActive(ctx)

  local fill_col = themes[theme].viewer.C_VIEW_BUTTON_FILL
  if active or selected then
    fill_col = themes[theme].viewer.C_VIEW_BUTTON_ACTIVE
  elseif hovered then
    fill_col = themes[theme].viewer.C_VIEW_BUTTON_HOVER
  end

  ImGui.DrawList_AddRectFilled(
    dl,
    sx,
    sy,
    sx + width,
    sy + height,
    ImGui.GetColorEx(ctx,fill_col),
    UI_METRICS.button_rounding
  )
  ImGui.DrawList_AddRect(
    dl,
    sx,
    sy,
    sx + width,
    sy + height,
    ImGui.GetColorEx(ctx,themes[theme].viewer.C_VIEW_BUTTON_BORDER),
    UI_METRICS.button_rounding,
    ImGui.DrawFlags_None,
    UI_METRICS.button_border_size
  )

  local text_w, text_h = ImGui.CalcTextSize(ctx, label)
  ImGui.DrawList_AddText(
    dl,
    sx + (width - text_w) * 0.5,
    sy + (height - text_h) * 0.5,
    ImGui.GetColor(ctx,ImGui.Col_Text),
    label
  )

  return clicked
end

function UI.button_size(caption,compact)
  local shown=caption:match('^(.-)##') or caption
  -- Match the original note-action button: narrower than the column control.
  if shown=='...' then compact=false end
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  local w,h=ImGui.CalcTextSize(ctx,shown)
  ImGui.PopFont(ctx)
  local pad_x=compact and UI_METRICS.compact_button_pad_x or UI_METRICS.button_pad_x
  return w+2*pad_x,math.max(UI_METRICS.button_min_height,h+2*UI_METRICS.button_pad_y)
end
function UI.button(_,caption,compact)
  local shown=caption:match('^(.-)##') or caption
  local w,h=UI.button_size(caption,compact)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  local clicked=UI.source_button(caption,shown,w,h)
  ImGui.PopFont(ctx)
  return clicked
end
-- Native checkbox geometry follows the UI font, independently of note text.
function UI.checkbox(caption,value)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,UI_METRICS.frame_pad_x,UI_METRICS.checkbox_pad_y)
  local changed,result=ImGui.Checkbox(ctx,caption,value)
  ImGui.PopStyleVar(ctx)
  ImGui.PopFont(ctx)
  return changed,result
end
-- The text cell is submitted first: native tables carry the previous cell's
-- text baseline forward. Drawing the checkbox last keeps its padding baseline
-- out of the first text line; geometry still places it in the leading column.
function UI.note_checkbox(value,row)
  local x=ImGui.GetCursorScreenPos(ctx)
  ImGui.SetCursorScreenPos(ctx,x,row.top+row.checkbox_y)
  return UI.checkbox('##checked',value)
end
function UI.quick_access_next(row,width)
  if row.used>0 and row.used+UI_METRICS.item_gap_x+width<=row.width then
    ImGui.SameLine(ctx,0,UI_METRICS.item_gap_x)
    row.used=row.used+UI_METRICS.item_gap_x+width
  else row.used=width end
end
--[[
Lucide icons: https://github.com/lucide-icons/lucide
Original paths: type, square-check, list-chevrons-down-up, file-input, palette, trash, x, pencil, check, clock, grip-vertical, circle-plus.
Rendered with a 1.5 px stroke at 24 px; white alpha masks are tinted by the UI.
ISC License

Copyright (c) 2026 Lucide Icons and Contributors

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.

---

The following Lucide icons are derived from the Feather project:

airplay, alert-circle, alert-octagon, alert-triangle, aperture, arrow-down-circle, arrow-down-left, arrow-down-right, arrow-down, arrow-left-circle, arrow-left, arrow-right-circle, arrow-right, arrow-up-circle, arrow-up-left, arrow-up-right, arrow-up, at-sign, calendar, cast, check, chevron-down, chevron-left, chevron-right, chevron-up, chevrons-down, chevrons-left, chevrons-right, chevrons-up, circle, clipboard, clock, code, columns, command, compass, corner-down-left, corner-down-right, corner-left-down, corner-left-up, corner-right-down, corner-right-up, corner-up-left, corner-up-right, crosshair, database, divide-circle, divide-square, dollar-sign, download, external-link, feather, frown, hash, headphones, help-circle, info, italic, key, layout, life-buoy, link-2, link, loader, lock, log-in, log-out, maximize, meh, minimize, minimize-2, minus-circle, minus-square, minus, monitor, moon, more-horizontal, more-vertical, move, music, navigation-2, navigation, octagon, pause-circle, percent, plus-circle, plus-square, plus, power, radio, rss, search, server, share, shopping-bag, sidebar, smartphone, smile, square, table-2, tablet, target, terminal, trash-2, trash, triangle, tv, type, upload, x-circle, x-octagon, x-square, x, zoom-in, zoom-out

The MIT License (MIT) (for the icons listed above)

Copyright (c) 2013-present Cole Bemis

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

]]
UI.quick_icon_png={
  ['circle_plus']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096'..
    '\008\006\000\000\000\226\152\119\056\000\000\000\006\098\075\071\068\000\255\000\255\000\255\160'..
    '\189\167\147\000\000\008\053\073\068\065\084\120\156\237\157\093\172\093\069\025\134\223\049\241'..
    '\028\108\139\253\017\193\043\172\088\090\176\049\072\211\090\162\006\123\218\162\024\069\008\033'..
    '\196\011\245\074\172\198\064\168\033\233\133\222\042\137\063\020\068\068\226\029\023\068\188\128'..
    '\004\244\078\139\023\208\148\150\196\024\210\002\165\085\060\032\109\061\253\057\080\176\231\180'..
    '\061\231\241\098\086\061\063\157\111\246\094\123\207\094\179\246\062\235\073\118\118\050\123\175'..
    '\153\119\190\089\107\230\091\107\102\190\037\053\052\052\052\052\052\052\100\193\229\022\096\001'..
    '\056\073\171\036\125\074\210\026\073\171\139\207\050\073\139\037\045\047\190\037\233\125\073\167'..
    '\138\239\113\073\007\037\189\086\124\094\113\206\189\094\169\248\018\212\170\001\128\085\146\182'..
    '\072\026\041\062\151\039\202\250\152\164\231\138\207\095\156\115\135\019\229\219\255\000\043\128'..
    '\239\002\207\083\029\251\129\029\192\199\114\215\063\027\192\102\224\143\192\185\010\013\063\159'..
    '\115\133\134\145\220\246\168\012\096\043\176\059\163\209\045\094\000\110\193\143\061\131\007\176'..
    '\017\120\041\175\141\219\098\047\176\161\042\187\244\188\181\129\021\146\238\151\244\029\073\031'..
    '\040\121\248\164\164\125\146\014\200\123\054\175\074\026\213\092\175\071\154\235\021\093\041\233'..
    '\026\121\143\105\173\164\013\146\134\074\150\059\045\233\049\073\063\114\206\157\042\121\108\125'..
    '\000\110\007\198\074\158\129\251\129\159\226\187\170\069\009\052\044\002\110\002\238\007\014\148'..
    '\212\114\012\184\053\133\045\042\005\024\006\126\085\162\162\099\192\067\192\250\010\180\109\040'..
    '\180\029\111\083\219\052\176\019\040\123\021\229\001\184\138\246\251\250\081\224\110\224\067\025'..
    '\116\046\002\238\001\222\108\083\235\094\096\101\213\058\075\001\172\195\095\182\173\056\006\220'..
    '\085\135\179\010\024\002\182\001\255\105\067\247\017\224\250\220\154\131\000\155\128\119\090\084'..
    '\096\010\120\028\184\044\183\222\249\000\203\240\221\224\249\022\117\056\013\124\041\183\222\057'..
    '\000\183\001\019\045\132\191\014\124\054\183\214\086\000\055\000\135\091\212\101\130\186\012\206'..
    '\192\072\027\198\127\010\088\150\091\107\187\000\031\006\126\223\162\078\147\192\077\185\133\174'..
    '\035\222\237\156\007\238\201\042\178\011\128\237\248\110\211\226\029\114\141\009\120\111\039\054'..
    '\224\078\000\119\100\017\151\016\224\078\226\087\248\017\170\246\142\240\126\126\204\213\124\023'..
    '\216\092\169\168\030\002\108\041\234\100\177\151\042\061\058\224\225\136\152\073\234\230\037\036'..
    '\128\214\099\221\206\170\132\220\030\017\113\158\001\232\118\044\240\221\145\053\038\076\003\183'..
    '\245\090\192\010\226\055\044\125\059\224\182\011\112\111\164\254\199\128\229\189\044\252\177\072'..
    '\225\127\232\089\193\053\003\120\034\098\135\223\244\170\208\013\216\151\223\033\096\105\079\010'..
    '\174\033\192\082\236\155\181\041\096\099\234\002\029\176\047\082\096\237\239\112\083\131\191\099'..
    '\182\078\200\061\169\011\251\090\228\146\123\036\105\097\125\004\241\046\249\230\148\005\089\043'..
    '\022\122\059\232\216\122\134\128\007\128\147\197\231\001\050\060\089\037\238\148\236\078\085\200'..
    '\230\072\043\223\149\164\144\242\154\118\006\180\084\227\135\095\172\229\123\017\251\108\074\081'..
    '\192\159\140\204\071\115\156\117\133\166\019\001\061\039\050\105\025\006\222\050\108\244\108\183'..
    '\153\095\129\189\110\231\238\068\117\232\068\087\144\140\122\172\123\131\115\192\021\221\100\252'..
    '\067\035\227\049\050\076\035\206\210\085\183\006\088\132\061\199\028\189\057\109\181\076\228\219'..
    '\070\250\019\206\185\051\157\201\029\060\156\115\255\149\244\164\241\243\183\058\202\020\184\218'..
    '\058\211\168\096\245\066\011\109\181\186\002\010\077\027\035\246\250\132\117\092\236\010\176\030'..
    '\039\191\226\156\123\169\059\185\131\135\115\238\069\249\133\099\033\204\071\243\177\006\176\022'..
    '\172\062\221\174\168\005\136\229\245\152\139\127\131\013\128\095\160\186\201\056\230\185\114\154'..
    '\022\020\187\140\244\173\148\089\244\011\172\054\250\178\009\018\044\023\236\150\058\142\001\133'..
    '\174\197\248\009\169\016\171\066\199\088\093\208\053\070\250\190\098\196\111\008\224\156\123\095'..
    '\146\053\062\094\027\074\044\219\000\251\203\138\090\128\028\048\210\087\135\018\173\006\088\099'..
    '\164\031\044\045\103\225\097\217\040\104\083\171\001\130\253\149\252\174\195\134\056\150\043\122'..
    '\117\040\209\106\128\021\070\250\104\105\057\011\015\203\070\065\155\090\013\112\169\145\254\110'..
    '\105\057\001\152\251\060\191\052\145\124\059\033\245\124\130\101\035\203\166\023\067\248\113\047'..
    '\248\237\070\093\067\248\121\126\110\146\204\039\000\151\025\249\143\133\254\031\188\057\000\038'..
    '\021\222\087\053\236\156\059\155\064\228\009\217\221\092\046\078\058\231\062\210\109\038\192\176'..
    '\164\137\192\079\147\206\185\075\230\039\150\221\052\215\144\024\171\001\222\051\210\151\036\042'..
    '\247\241\068\249\164\036\149\038\171\175\063\029\074\180\026\032\248\231\072\230\101\217\033\105'..
    '\167\252\086\211\220\156\146\215\178\035\081\126\165\026\032\008\240\178\049\144\124\058\141\198'..
    '\238\176\070\209\220\186\036\009\184\206\144\247\247\208\255\173\043\224\164\145\254\241\052\050'..
    '\007\026\203\070\065\155\090\013\096\197\215\009\062\207\104\152\131\245\024\039\104\083\171\001'..
    '\172\071\014\086\230\013\051\088\054\010\218\180\108\003\172\045\045\103\225\097\217\168\253\231'..
    '\104\216\019\242\147\052\019\050\049\093\075\128\179\134\188\082\019\050\135\036\029\013\164\015'..
    '\073\250\124\042\193\003\200\141\146\062\024\072\063\034\041\024\038\045\216\000\206\057\036\253'..
    '\213\040\100\225\068\151\042\143\101\155\093\133\077\047\034\246\040\194\154\124\239\237\062\168'..
    '\254\230\022\035\221\154\172\183\001\062\105\245\181\084\024\081\202\208\086\187\049\000\191\097'..
    '\195\098\165\117\156\121\005\020\161\029\255\102\252\252\205\046\245\014\034\214\050\206\125\206'..
    '\185\055\058\202\017\123\213\239\024\025\189\161\186\093\001\248\229\040\214\028\074\231\171\200'..
    '\129\203\177\221\170\108\091\082\107\216\000\214\042\242\238\150\167\023\153\063\107\100\254\038'..
    '\205\006\013\001\151\000\255\054\108\244\076\138\002\070\172\051\014\216\150\160\014\157\104\170'..
    '\211\022\165\031\068\236\115\099\170\066\172\077\122\199\201\016\253\138\122\109\210\179\162\066'..
    '\166\217\164\087\020\244\213\072\043\063\154\172\160\062\003\248\093\196\046\095\078\089\144\195'..
    '\135\100\009\049\005\220\144\172\176\062\001\248\028\246\070\237\116\103\255\172\002\215\099\007'..
    '\180\251\023\137\150\172\244\003\248\000\127\255\136\156\144\189\137\028\000\060\026\185\228\158'..
    '\097\080\003\095\207\162\232\013\158\138\216\225\225\094\022\190\156\120\152\178\237\061\043\188'..
    '\038\000\247\069\234\127\148\094\007\039\004\110\197\007\039\010\049\005\220\217\083\001\025\001'..
    '\190\065\060\096\147\245\048\046\185\144\007\035\103\193\036\041\061\128\154\064\235\144\101\191'..
    '\168\082\204\016\182\087\004\062\192\221\150\202\004\245\024\124\036\247\211\145\250\238\001\066'..
    '\019\049\061\021\181\018\031\178\209\098\130\001\232\142\240\221\142\181\239\011\224\109\032\207'..
    '\114\029\224\051\196\003\183\078\001\247\102\017\215\037\120\111\231\062\226\129\091\199\129\235'..
    '\114\011\221\004\156\137\136\004\120\154\012\113\133\058\005\031\186\248\201\022\117\154\004\182'..
    '\230\214\042\233\255\158\081\171\248\209\135\233\131\059\102\252\029\238\063\091\212\229\012\240'..
    '\245\220\090\231\128\191\018\198\091\008\159\198\135\175\255\104\110\189\243\193\223\227\060\068'..
    '\188\203\001\063\024\231\013\218\109\001\092\079\124\096\190\192\024\240\125\252\102\134\220\154'..
    '\135\241\143\148\219\121\165\201\219\228\238\243\091\129\247\142\098\046\234\108\222\194\079\123'..
    '\086\062\189\137\159\070\220\142\061\153\050\159\061\192\149\085\235\236\008\252\125\194\131\216'..
    '\119\204\243\057\014\252\154\010\198\008\252\234\133\071\176\231\112\231\051\013\252\146\170\253'..
    '\252\020\224\223\172\209\206\059\101\102\243\026\240\051\224\102\096\113\235\082\090\106\088\002'..
    '\124\005\248\057\112\176\164\150\163\244\120\176\173\226\069\110\203\037\253\068\210\054\149\223'..
    '\147\118\078\062\246\194\126\205\188\158\118\084\126\183\201\184\102\182\082\045\145\127\205\237'..
    '\165\242\235\243\047\188\254\118\173\164\245\010\047\023\140\049\037\233\183\146\126\236\156\027'..
    '\047\121\108\061\193\207\039\188\088\242\012\204\193\110\096\093\110\123\245\012\224\011\192\159'..
    '\051\027\057\196\243\012\242\203\060\231\003\124\017\063\137\099\173\059\170\130\179\133\134\052'..
    '\171\023\250\017\242\190\208\185\187\069\083\009\168\213\229\006\092\037\031\224\110\164\248\078'..
    '\245\198\235\035\242\043\148\119\201\047\021\127\035\081\190\093\083\171\006\152\015\126\087\201'..
    '\181\154\241\106\214\072\090\042\239\237\044\211\204\198\241\247\228\189\162\011\222\209\065\205'..
    '\188\254\246\085\231\220\161\106\149\055\052\052\052\052\052\052\212\158\255\001\026\109\110\186'..
    '\253\239\204\074\000\000\000\000\073\069\078\068\174\066\096\130',
  grip=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\000\009\112\072\089\115\000\000\059\014\000\000\059'..
    '\014\001\204\182\161\131\000\000\000\025\116\069\088\116\083\111\102\116\119\097\114\101\000\119\119\119\046\105\110\107\115\099\097\112\101\046\111\114\103\155\238\060\026\000\000\002\092\073'..
    '\068\065\084\120\156\237\154\177\078\219\080\024\133\079\016\035\202\152\009\049\118\067\093\059\116\067\221\040\083\223\160\079\128\016\079\208\185\015\083\117\172\058\179\181\067\199\128\010'..
    '\018\083\167\086\048\243\051\216\072\030\066\073\110\254\112\126\228\239\147\238\098\217\039\145\191\027\251\218\057\147\136\016\248\216\114\127\129\177\131\000\051\008\048\131\000\051\008\048'..
    '\131\000\051\008\048\131\000\051\008\048\131\000\051\008\048\131\000\051\021\004\076\037\125\146\244\083\210\109\063\126\244\219\102\047\032\127\061\034\194\057\014\034\226\042\030\231\095\068'..
    '\124\040\156\191\246\152\132\239\117\244\129\164\111\146\038\079\236\023\146\222\073\250\094\044\063\005\151\128\169\164\095\146\246\150\220\255\090\210\190\164\191\069\242\211\112\221\003\078'..
    '\181\252\201\145\164\093\073\199\133\242\211\112\009\120\223\112\204\081\161\252\052\092\151\160\027\073\059\011\182\191\081\119\205\062\123\228\152\105\145\252\052\042\044\067\135\076\180\217'..
    '\239\180\233\252\149\217\054\125\238\133\164\215\011\182\047\154\153\015\156\023\202\079\195\053\027\190\054\028\243\165\080\126\026\174\123\192\076\210\092\203\095\115\127\171\155\209\055\069'..
    '\242\211\112\253\002\254\072\250\168\238\033\232\041\238\250\125\087\057\057\155\206\207\195\249\024\030\017\111\035\098\254\159\087\005\151\253\235\132\170\249\047\250\085\196\003\083\073\039'..
    '\146\014\037\189\082\055\107\231\234\174\227\159\181\254\204\220\116\254\090\084\016\048\106\074\173\137\199\008\002\204\032\192\012\002\204\032\192\012\002\204\032\192\012\002\204\032\192\012'..
    '\002\204\032\192\012\002\204\032\192\076\005\001\116\067\141\131\110\104\248\254\015\160\027\042\186\161\173\249\105\208\013\109\203\079\131\110\104\091\126\026\116\067\219\242\211\168\176\012'..
    '\029\066\055\244\153\160\027\218\067\055\180\045\063\013\186\161\109\249\105\208\013\165\027\074\055\212\034\126\000\221\080\240\081\106\077\060\070\016\096\006\001\102\016\096\006\001\102\016'..
    '\096\006\001\102\016\096\006\001\102\016\096\006\001\102\016\096\006\001\102\042\008\160\027\106\028\116\067\195\247\127\000\221\080\209\013\109\205\079\131\110\104\091\126\026\116\067\219\242'..
    '\211\160\027\218\150\159\070\133\101\232\016\186\161\207\004\221\208\030\186\161\109\249\105\208\013\109\203\079\131\110\040\221\080\186\161\022\241\003\232\134\130\143\082\107\226\049\130\000'..
    '\051\008\048\131\000\051\008\048\131\000\051\008\048\131\000\051\008\048\131\000\051\008\048\131\000\051\247\086\104\023\113\117\036\238\203\000\000\000\000\073\069\078\068\174\066\096\130',

  ['clock']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\008\165\073\068\065\084\120\218\237\157\127\140\093\069\021\199\063\187\210\093\236'..
    '\047\187\107\065\162\166\148\166\116\091\250\007\041\182\216\214\160\108\045\165\066\160\072\072\037\128\077\012\066\099\080\041\138\241\015\137\137\026\131\196\194\150\106\137\086\099\112\013\008\104\036\042\070\253\195\098'..
    '\068\237\150\054\248\023\237\118\219\141\117\081\251\195\254\090\022\104\183\063\246\248\199\156\117\215\229\158\123\239\188\247\238\125\243\222\187\223\100\242\146\153\247\222\204\156\239\189\051\103\206\156\057\211\036\034'..
    '\020\168\030\154\011\017\020\004\020\004\020\040\008\104\088\092\016\112\219\154\128\185\192\021\064\007\048\079\211\012\096\010\208\166\159\000\111\002\039\244\243\036\208\007\236\213\180\007\216\023\108\039\003\211\130\230'..
    '\002\031\005\058\053\093\092\161\255\061\012\188\168\233\015\064\127\065\192\024\218\129\219\128\117\192\135\114\170\115\055\208\013\252\024\056\212\168\004\172\000\190\000\092\095\197\161\240\028\240\123\224\081\125\059\026'..
    '\130\128\149\192\215\129\101\129\013\199\127\005\190\005\188\000\072\061\018\240\065\096\011\240\129\192\021\147\157\192\125\250\089\023\004\180\003\015\003\159\046\065\237\029\086\065\236\086\205\166\023\024\152\160\245\048'..
    '\065\043\154\005\204\087\141\105\033\176\004\104\241\172\119\004\248\062\240\021\173\167\102\009\184\085\059\050\211\115\130\252\037\176\077\135\133\183\202\108\195\100\157\220\087\000\107\128\005\030\191\061\002\220\171\237'..
    '\201\006\034\146\069\106\021\145\205\146\030\255\017\145\199\069\100\113\070\237\025\159\150\104\219\142\166\108\219\136\136\116\137\072\075\022\237\201\162\131\115\068\100\087\202\206\013\136\200\231\068\228\157\057\008\126'..
    '\098\154\044\034\159\023\145\215\082\182\245\101\017\153\029\058\001\087\137\200\225\020\157\057\044\034\247\100\245\084\121\166\022\017\089\047\034\071\082\180\251\160\136\044\010\149\128\107\069\100\048\161\003\231\069\164'..
    '\091\068\102\006\032\248\137\105\134\014\131\231\018\250\048\036\034\171\066\035\224\022\017\057\157\208\240\125\034\114\117\128\130\159\152\150\138\072\127\066\095\078\139\200\154\080\008\232\076\033\252\095\232\019\070\141'..
    '\164\233\034\242\076\066\159\134\069\228\186\106\019\112\085\194\176\115\078\039\058\106\052\061\160\195\166\133\193\114\231\132\114\214\001\115\128\237\049\022\203\097\224\046\224\231\053\110\178\095\171\134\187\086\163\252'..
    '\144\154\085\014\228\185\033\211\010\060\023\035\252\033\224\134\012\133\223\002\060\006\028\215\244\088\009\171\221\180\120\014\184\081\251\020\133\075\244\059\045\121\046\196\190\147\048\054\174\202\120\104\232\138\168\183'..
    '\043\227\058\147\230\186\174\188\230\128\091\019\198\252\219\114\024\155\143\069\212\125\044\135\122\215\198\204\009\035\170\013\102\074\064\123\194\130\037\175\009\215\066\030\117\111\072\088\096\182\249\252\159\239\028\240'..
    '\048\112\145\081\246\051\096\115\003\236\163\111\002\126\106\148\093\012\124\051\043\107\232\018\160\199\152\184\251\213\206\063\152\147\016\036\102\035\063\015\188\011\120\069\053\193\040\083\246\114\096\071\037\181\160\038'..
    '\224\009\227\251\035\192\029\057\010\063\004\012\002\119\106\223\163\100\250\120\165\213\208\027\129\197\070\217\247\128\151\105\060\244\000\063\140\217\253\091\093\201\033\232\207\134\199\194\017\221\125\058\145\115\231\171'..
    '\061\004\141\223\237\235\053\230\197\237\058\020\149\253\006\172\192\118\023\121\168\010\194\015\009\199\129\175\026\101\203\128\107\043\241\006\252\070\087\181\019\241\026\206\145\234\076\021\058\030\202\027\048\106\021\232'..
    '\007\222\023\081\246\002\112\083\057\111\192\123\128\085\070\217\183\171\036\252\208\048\012\108\052\202\086\171\012\075\038\224\078\162\157\166\142\198\076\064\141\136\173\192\177\136\252\011\128\079\148\067\192\058\035\255'..
    '\105\224\084\033\247\255\225\045\224\089\163\236\147\165\018\112\057\112\165\081\246\147\066\230\111\067\183\145\191\024\184\172\020\002\086\024\249\123\128\093\133\188\223\134\029\170\146\250\200\050\150\128\078\035\255\249'..
    '\066\214\038\126\237\041\075\147\128\166\024\029\246\197\066\206\038\182\025\249\043\045\021\217\090\007\204\195\157\046\137\082\185\218\041\223\093\176\158\214\001\227\049\069\023\103\045\198\156\186\063\237\027\048\223\200'..
    '\223\025\128\240\067\198\155\049\243\227\002\159\033\200\034\224\213\066\198\137\216\109\228\207\243\033\160\195\200\239\043\228\155\136\062\031\153\090\004\204\053\242\247\022\242\077\068\111\204\186\042\053\001\237\070\254'..
    '\064\033\223\068\012\248\200\212\034\096\154\145\255\122\033\223\068\188\238\035\083\095\002\134\002\239\252\086\096\118\149\219\048\228\035\083\107\029\048\108\232\178\173\132\097\130\142\219\196\056\011\060\131\059\137\185'..
    '\191\010\109\107\005\078\027\050\189\208\199\020\017\050\142\199\148\077\194\089\032\119\007\242\070\196\194\034\224\013\035\127\106\032\237\238\078\241\157\073\192\061\170\022\230\073\132\215\240\221\092\137\113\172\010\248'..
    '\050\206\245\227\108\128\068\100\074\192\244\064\008\056\003\108\208\245\202\102\029\095\125\136\232\142\089\235\148\139\233\149\032\192\026\099\047\013\080\231\190\095\151\249\062\068\140\206\017\089\016\113\169\143\076\045'..
    '\002\246\249\216\051\002\034\098\062\240\003\143\161\105\148\136\077\084\238\124\065\135\143\076\155\061\077\014\029\129\107\071\007\112\039\219\231\121\018\113\063\240\072\198\004\236\173\004\001\011\107\068\077\045\133\136'..
    '\117\021\170\123\097\037\008\216\099\228\047\193\197\094\160\142\137\040\007\083\177\163\193\244\250\016\176\159\232\072\082\045\228\023\213\042\111\034\186\043\080\207\135\117\072\155\136\131\024\097\210\154\099\150\250\127'..
    '\052\202\058\169\093\140\039\098\043\206\175\245\004\208\165\107\139\114\097\201\102\155\101\062\137\243\013\189\023\023\106\038\106\120\186\130\002\214\048\019\053\009\223\013\252\200\231\013\000\023\093\048\010\011\116\046'..
    '\040\240\255\088\026\163\001\089\222\018\177\004\244\003\127\051\202\238\042\228\157\090\139\218\073\204\033\238\036\107\168\053\049\221\081\099\218\080\214\152\130\237\132\027\235\198\153\068\192\211\134\198\048\019\023\003'..
    '\174\128\195\122\162\183\028\207\225\078\209\151\076\192\017\092\092\205\040\124\137\236\194\003\212\018\046\004\190\104\148\253\022\023\181\183\100\002\192\197\097\136\194\251\129\079\021\242\231\110\224\189\070\217\198\164'..
    '\031\151\123\072\239\024\206\000\118\180\065\133\223\174\038\134\168\168\144\021\059\164\007\238\132\124\020\222\013\124\163\129\159\254\071\176\067\114\126\045\205\031\164\125\003\154\112\254\239\081\250\255\136\190\029\061'..
    '\013\038\252\229\192\075\198\067\156\234\233\247\033\000\220\073\143\030\224\029\017\101\003\192\034\226\055\203\235\009\051\112\161\010\046\051\030\200\101\164\060\188\238\227\021\177\011\103\200\138\194\044\224\073\170\239'..
    '\030\158\007\154\212\172\096\029\059\122\002\159\200\001\158\161\090\218\018\226\130\062\080\195\241\225\210\166\007\099\250\127\200\055\056\097\041\013\088\163\193\137\172\184\160\107\235\088\248\183\039\004\108\186\041\175'..
    '\168\137\155\018\066\150\093\095\135\194\079\010\089\182\049\207\168\137\045\186\054\176\172\162\067\192\199\099\044\170\181\134\149\184\195\137\150\099\218\014\224\026\074\216\113\043\213\053\241\012\046\156\163\117\255\202'..
    '\052\092\140\137\181\117\032\252\219\181\047\150\240\015\170\033\174\164\237\206\114\124\067\015\000\031\195\118\199\110\197\133\246\218\080\195\218\206\131\192\083\049\054\175\065\149\193\063\074\174\165\066\065\187\079\037'..
    '\132\249\125\222\055\152\093\000\161\139\159\077\017\186\120\101\040\193\187\215\164\136\031\221\175\129\177\067\023\254\114\017\249\123\066\095\078\137\200\205\033\134\175\063\153\226\054\138\110\017\185\040\064\193\183\105'..
    '\248\250\243\041\194\215\095\039\018\230\005\014\139\244\146\131\052\087\150\124\070\175\058\169\182\224\091\069\228\190\148\087\154\252\091\068\174\012\253\010\147\217\122\221\071\026\252\083\003\161\078\174\130\224\167\232'..
    '\202\253\095\041\219\218\035\034\179\106\225\014\153\209\107\065\054\197\172\152\039\226\168\136\124\055\167\057\098\169\136\108\049\194\031\091\195\230\163\034\050\041\139\246\100\125\141\213\045\056\223\034\159\075\057\251'..
    '\024\187\198\234\037\198\238\010\043\021\083\117\145\052\122\141\213\229\030\191\061\140\243\143\250\085\102\186\110\014\023\185\181\225\194\249\174\047\097\221\113\086\173\176\175\050\118\061\237\128\174\180\079\050\118\148'..
    '\106\170\154\136\167\225\252\243\071\175\191\093\168\102\244\073\158\245\158\199\197\067\125\072\235\161\150\009\024\191\159\176\005\184\058\240\005\216\118\224\179\106\239\207\028\121\158\146\220\133\139\040\123\077\160\054'..
    '\162\191\000\055\235\238\222\043\121\085\090\205\235\108\063\130\115\231\088\093\194\016\081\041\156\005\126\135\243\094\248\083\085\236\029\013\126\161\243\147\036\248\237\052\002\001\227\049\071\181\149\078\253\188\164\066'..
    '\255\123\080\181\170\209\116\032\024\139\095\096\004\076\196\092\156\055\246\168\086\211\129\139\221\063\077\181\158\081\019\241\027\170\173\140\106\071\125\140\093\127\219\075\117\066\022\212\005\001\117\143\230\066\004\005'..
    '\001\005\001\005\010\002\026\022\255\005\131\144\096\142\137\240\174\054\000\000\000\000\073\069\078\068\174\066\096\130',
  ['pencil']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\005\100\073\068\065\084\120\218\237\157\079\104\092\069\028\199\063\073\214\054\100'..
    '\163\181\085\170\061\040\021\172\069\188\024\084\154\162\162\086\252\147\054\181\010\166\152\158\237\193\155\007\079\090\090\068\015\034\122\241\040\158\004\173\154\182\098\018\171\081\219\154\038\022\069\072\015\074\043\020'..
    '\172\136\136\165\216\250\047\168\052\230\231\225\077\096\009\059\243\254\239\236\190\249\125\097\097\153\125\111\230\237\247\243\123\191\153\055\251\118\094\151\136\160\242\167\110\181\064\001\040\000\149\002\008\086\053\181'..
    '\192\169\062\224\126\096\024\024\000\214\001\107\129\191\128\095\128\031\128\041\096\018\248\062\075\003\093\058\010\106\170\085\192\051\192\211\064\127\194\125\142\001\207\002\095\042\128\124\218\005\188\006\092\149\113\255'..
    '\049\096\055\240\187\002\072\153\013\128\125\192\094\243\062\143\206\000\059\128\211\010\032\121\095\248\054\048\082\096\157\023\128\065\003\067\071\065\014\245\000\111\022\108\062\192\026\096\194\244\039\010\192\017\249\239'..
    '\000\163\142\109\022\129\131\192\078\224\058\096\165\233\031\054\001\207\155\209\144\077\027\129\215\157\071\032\034\161\190\106\034\050\038\110\157\022\145\091\099\234\169\139\200\043\142\058\022\069\100\147\109\127\053\223'..
    '\174\207\069\228\202\020\117\238\118\212\117\068\001\164\055\191\158\161\238\087\029\117\222\208\108\159\238\064\059\220\199\029\219\204\154\043\223\249\012\245\239\117\244\009\195\161\119\194\073\058\220\105\224\097\051\213'..
    '\144\069\243\142\078\247\193\144\001\244\001\167\098\034\127\026\216\150\049\242\027\245\145\165\124\125\168\000\122\128\057\096\067\073\105\167\217\085\112\051\173\011\017\192\082\218\217\232\216\102\038\103\218\105\150\134'..
    '\154\169\030\026\128\026\176\063\038\237\000\252\013\044\020\216\238\053\150\242\115\033\001\072\050\218\105\236\028\223\055\087\184\069\232\078\075\249\207\161\000\088\138\252\209\020\251\012\021\008\097\167\165\124\046\004'..
    '\000\121\102\053\135\128\015\128\222\028\237\223\014\060\098\249\236\112\179\194\042\077\071\039\049\255\184\233\108\183\058\182\153\002\030\005\254\073\217\254\106\224\043\203\104\235\015\224\090\211\223\084\114\050\174\038'..
    '\034\239\037\156\094\088\033\034\227\049\219\126\044\034\189\041\218\175\139\200\180\163\190\125\085\158\011\234\017\145\183\098\012\157\017\145\254\134\125\138\132\208\039\034\071\029\245\156\023\145\043\170\010\032\077\228'..
    '\047\223\183\008\008\113\145\191\040\034\035\174\239\016\066\228\095\238\168\035\015\132\184\200\023\017\121\049\238\123\084\057\242\167\019\078\041\103\129\016\023\249\034\034\239\138\072\119\021\001\020\017\249\121\032\036'..
    '\137\252\049\017\185\044\073\219\106\126\058\008\159\154\062\165\016\243\059\013\064\153\230\167\129\080\152\249\157\004\160\021\230\047\189\086\138\200\225\086\152\223\041\000\090\105\126\086\008\153\204\239\004\000\062\204'..
    '\111\132\048\085\166\249\237\254\163\252\210\148\242\174\152\095\178\182\002\127\150\212\126\220\236\232\001\115\124\151\178\054\210\174\147\113\190\205\239\035\186\231\255\190\152\159\030\111\201\099\126\187\078\071\119\138'..
    '\249\003\121\205\111\071\000\157\096\254\065\019\249\243\133\180\168\029\110\170\185\157\003\121\058\220\118\030\005\005\105\126\187\000\008\214\252\118\000\016\180\249\190\001\004\111\190\079\000\106\190\071\000\106\190\071'..
    '\000\106\190\071\000\106\190\071\000\106\190\071\000\106\190\071\000\106\190\071\000\237\096\254\145\118\054\191\076\000\073\204\159\013\221\252\178\000\168\249\030\001\168\249\030\001\168\249\030\001\168\249\030\001\168\249'..
    '\030\001\168\249\030\001\168\249\030\001\168\249\030\001\116\137\200\254\004\127\142\232\047\233\160\235\034\114\172\010\230\103\005\176\071\035\223\031\128\045\034\178\224\248\242\199\053\242\211\189\210\222\027\122\002\216'..
    '\108\249\236\011\243\111\243\178\238\088\155\000\182\196\220\177\054\090\196\237\130\173\084\154\091\019\007\029\230\047\045\249\082\134\249\117\224\195\042\154\159\022\192\147\150\242\031\129\199\010\092\111\103\185\249\147'..
    '\192\189\085\052\063\013\128\110\162\229\188\154\233\037\224\087\053\191\220\255\007\108\054\249\127\185\022\136\214\211\191\168\057\191\220\051\096\187\035\247\171\249\030\001\076\168\249\229\167\160\245\192\089\203\103\055'..
    '\017\179\060\187\154\159\255\012\216\097\041\063\213\098\243\015\085\205\252\164\000\108\233\103\188\197\230\063\081\053\243\147\000\088\005\220\093\098\254\015\218\252\036\000\134\128\021\077\202\207\019\173\143\166\230\151'..
    '\012\192\150\126\038\129\255\212\252\114\001\212\204\025\096\003\144\085\107\136\150\112\140\027\237\084\222\252\056\000\119\017\045\197\184\092\255\002\159\100\104\107\053\240\020\112\018\184\039\164\161\038\049\081\110\147'..
    '\109\001\210\163\036\159\120\187\209\212\051\108\058\243\184\071\039\006\101\126\028\128\225\012\195\207\110\162\191\240\111\055\251\223\150\226\088\014\133\102\190\235\074\248\102\115\161\181\092\002\092\015\252\212\080\214'..
    '\015\060\100\076\223\006\092\157\225\056\114\175\058\082\181\051\192\118\245\059\103\204\095\075\244\003\204\008\240\000\217\023\189\022\224\101\162\135\096\046\018\160\106\142\241\127\051\245\026\008\003\005\180\125\002\216'..
    '\067\244\020\210\096\101\075\065\023\044\035\160\188\058\103\134\176\111\144\242\177\175\161\157\001\093\005\182\241\141\185\232\026\007\190\014\053\213\164\005\048\227\184\010\142\211\037\162\039\018\077\152\215\089\181\057'..
    '\125\010\218\096\034\055\105\231\122\017\248\204\164\151\113\224\055\181\054\031\000\128\231\128\023\028\233\232\076\067\148\207\082\236\131\112\020\128\209\029\068\079\153\030\052\067\198\111\137\030\084\054\014\124\167\246'..
    '\149\015\064\085\178\244\137\218\010\064\001\168\020\064\184\250\031\115\074\151\179\190\215\141\219\000\000\000\000\073\069\078\068\174\066\096\130',
  ['check']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\002\060\073\068\065\084\120\218\237\155\203\074\195\064\024\070\191\138\052\174\245'..
    '\169\092\136\023\244\065\124\017\245\025\220\042\040\010\094\030\202\186\181\221\252\110\034\084\165\198\076\102\050\127\102\206\129\080\040\180\164\231\076\038\165\051\157\153\153\032\031\091\040\032\000\001\128\000\004\000'..
    '\002\016\000\008\064\000\032\000\001\128\000\004\000\002\016\000\008\064\000\032\000\001\128\000\004\128\111\204\037\093\072\090\180\199\069\251\092\111\182\113\217\155\070\210\157\164\253\181\231\206\037\205\218\199\094\204'..
    '\216\150\050\088\254\023\011\073\123\076\065\121\228\115\015\112\032\255\058\228\141\153\130\226\200\127\150\116\044\105\201\021\016\255\219\206\077\135\252\087\073\039\033\242\009\208\045\255\086\210\065\135\252\035\073\031'..
    '\220\003\038\040\159\000\153\229\019\032\179\124\002\100\150\079\128\204\242\009\144\089\062\001\050\203\175\061\064\118\249\053\007\112\033\191\214\000\110\228\215\024\192\149\252\218\002\184\147\095\083\000\151\242\107\009'..
    '\224\086\126\013\001\092\203\047\061\128\123\249\067\002\068\219\023\147\136\070\210\125\135\252\103\073\135\057\229\075\146\204\044\228\184\180\223\060\153\089\019\248\126\049\143\166\061\151\191\240\114\174\193\139\242\111'..
    '\146\118\055\140\170\160\197\233\136\035\063\217\002\250\020\238\001\251\173\128\006\249\105\003\092\059\139\048\073\249\067\238\001\158\230\217\073\205\249\063\143\033\047\158\155\217\067\199\007\127\049\179\157\132\031\192'..
    '\195\057\100\011\144\091\192\228\229\199\008\144\075\068\017\242\099\005\024\091\072\049\242\099\006\024\075\076\081\242\099\007\072\045\168\056\249\041\002\164\018\085\164\252\084\001\098\011\043\086\126\202\000\177\196\021'..
    '\045\063\117\128\161\002\139\151\063\070\128\080\145\085\200\031\043\064\095\161\213\200\031\178\030\144\242\023\075\077\242\087\205\064\198\254\151\228\127\214\105\229\121\013\119\234\139\242\043\073\103\107\035\189\015\062'..
    '\214\112\011\216\021\177\108\071\241\099\207\145\031\252\087\080\002\012\187\018\138\028\249\030\246\005\253\231\074\040\118\228\123\217\152\181\146\116\186\033\066\113\055\092\143\001\214\167\163\043\073\239\237\113\085\242'..
    '\180\147\243\107\040\056\188\002\008\000\004\032\000\016\128\000\064\000\002\000\001\008\000\004\032\000\016\128\000\064\000\002\000\001\008\000\004\032\000\016\128\000\064\000\002\064\092\062\001\111\048\039\203\198\202\061'..
    '\046\000\000\000\000\073\069\078\068\174\066\096\130',
  ['text']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\001\181\073\068\065\084\120\218\237\220\061\074\003'..
    '\065\028\064\241\183\034\041\003\042\088\137\141\181\189\214\193\082\207\032\120\001\045\068\123\251\232\009\130\164\246\006\226\021\180\240\010\182\174\034\233\255\022\110\163\097\101\243\053'..
    '\217\236\190\007\211\044\132\097\230\023\118\146\016\054\139\008\108\121\173\185\005\002\008\096\002\008\096\002\008\096\002\008\096\002\008\096\002\008\048\065\093\224\006\120\001\070\064\052'..
    '\124\140\128\231\098\205\219\179\110\094\054\227\175\161\061\096\000\236\182\244\013\252\005\156\001\015\203\000\232\001\143\064\214\242\187\072\000\071\192\083\074\128\046\240\218\226\119\254'..
    '\223\222\128\125\224\051\213\025\112\233\230\255\106\007\184\072\121\008\031\187\231\099\157\164\004\216\043\185\126\080\156\009\139\030\165\183\212\004\227\112\194\061\089\200\025\016\255\108'..
    '\064\170\131\175\017\243\251\069\204\111\194\002\152\000\002\152\000\002\216\010\001\228\021\175\053\181\185\173\127\090\128\097\197\107\077\109\126\235\143\136\105\070\039\034\250\017\145\023'..
    '\163\095\092\035\209\040\043\213\252\115\091\127\182\162\127\079\095\246\079\017\030\194\126\010\050\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004'..
    '\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\048\001\004\016\192\004\016\192\004\016\192\004\016\192\218\010\208\001\250\252\060'..
    '\244\168\202\051\252\203\170\242\218\188\152\171\083\135\133\215\229\113\053\183\192\121\226\057\239\152\242\129\219\077\004\120\007\054\019\207\153\003\091\222\130\060\003\106\209\176\037\115'..
    '\142\181\094\019\128\171\226\128\060\005\054\022\060\215\007\112\015\092\123\008\155\103\128\000\002\152\000\002\152\000\002\152\000\002\152\000\002\152\000\045\234\027\099\154\183\013\159\115'..
    '\032\144\000\000\000\000\073\069\078\068\174\066\096\130',
  ['note']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\003\161\073\068\065\084\120\218\237\157\203\075\021'..
    '\081\028\199\063\055\196\107\230\045\180\157\218\162\093\181\043\123\016\065\069\059\033\031\069\237\163\191\032\043\177\199\182\141\004\121\251\023\220\022\148\010\061\246\045\130\090\212\162'..
    '\199\042\136\212\086\089\153\081\186\057\045\206\009\084\238\204\157\215\117\094\223\015\012\200\232\029\046\223\207\153\223\156\115\102\156\083\049\198\032\210\099\155\034\144\000\009\016\018'..
    '\032\001\066\002\036\064\072\064\233\104\139\249\249\030\096\020\024\006\246\001\253\192\142\130\103\246\027\152\007\062\000\115\192\099\096\041\234\193\042\017\071\194\157\192\085\096\028\216'..
    '\089\242\070\188\012\076\002\083\192\159\173\016\208\231\172\031\086\001\217\192\091\096\004\248\220\074\001\123\128\151\064\175\242\110\200\034\112\204\149\168\196\047\194\157\192\140\194\247'..
    '\165\215\085\135\142\086\008\184\006\028\084\198\077\025\000\198\146\022\208\003\092\247\249\253\035\224\052\208\005\084\010\190\117\001\103\092\075\247\098\002\232\014\148\172\049\038\200\118'..
    '\217\120\051\030\240\024\069\220\038\124\114\185\020\228\024\065\207\128\097\159\150\127\183\196\229\102\018\152\013\153\089\164\018\180\223\099\255\125\149\124\234\030\251\015\036\217\013\253'..
    '\229\106\223\102\106\192\074\201\005\212\220\096\108\051\043\238\119\137\008\240\250\163\138\078\128\120\249\104\050\046\101\036\064\002\036\064\072\128\004\008\009\144\000\033\001\018\032\036'..
    '\064\002\132\004\180\156\118\224\030\246\121\158\037\247\115\123\026\095\164\173\132\225\087\177\055\146\006\215\237\027\195\206\092\142\109\245\151\041\219\116\116\163\240\255\179\004\236\142'..
    '\120\092\077\071\199\012\095\215\128\012\132\063\157\198\023\043\067\009\010\018\254\083\224\028\176\170\018\148\124\111\231\065\147\240\159\003\231\099\132\175\018\228\019\254\067\096\168\073'..
    '\248\163\192\095\093\003\074\024\126\081\005\228\038\252\034\010\200\085\248\069\019\144\187\240\211\020\144\244\092\076\021\251\180\242\080\147\174\230\072\150\194\183\029\216\096\079\001\123'..
    '\017\245\169\226\169\006\199\122\098\140\169\070\056\086\213\125\214\143\168\199\110\121\062\105\013\196\190\097\255\231\032\238\128\104\043\006\089\165\026\136\013\186\064\171\057\010\063\151'..
    '\215\128\233\152\018\010\017\126\154\215\128\056\117\059\011\053\063\177\124\210\018\128\049\166\221\024\051\219\036\200\103\198\152\142\152\159\145\128\132\036\100\053\252\092\246\130\162\212'..
    '\115\050\092\243\035\231\147\149\251\001\065\070\177\100\120\132\155\251\110\232\026\112\113\093\075\015\067\054\071\184\057\156\011\090\117\173\120\046\100\203\079\237\102\074\017\039\227\194'..
    '\156\009\185\110\249\089\158\013\013\114\038\228\190\229\103\125\058\122\013\184\224\033\033\115\083\202\069\020\176\190\028\213\129\239\110\171\023\161\236\100\177\027\154\119\244\088\138\074'..
    '\144\144\000\009\016\018\032\001\066\002\036\064\072\128\004\008\009\144\000\033\001\018\032\018\017\224\245\114\214\154\034\100\151\199\254\229\036\005\044\122\236\031\080\254\158\025\124\077'..
    '\082\192\123\143\253\087\148\191\231\251\037\222\037\041\192\235\013\225\035\216\119\229\151\149\155\192\217\144\153\109\032\232\045\201\030\224\147\079\189\155\197\222\175\125\141\125\209\119'..
    '\145\169\001\071\092\203\247\010\255\039\176\023\123\031\059\017\001\000\183\129\059\170\056\129\184\129\093\091\128\036\005\108\007\094\000\135\148\175\047\175\128\147\004\124\114\035\236\050'..
    '\086\253\216\101\172\250\148\115\067\022\176\203\088\045\180\106\032\054\015\028\117\150\197\070\222\000\039\194\132\031\117\036\188\008\156\002\110\185\139\077\217\249\225\106\254\113\066\174'..
    '\162\023\165\004\109\166\219\117\069\135\177\235\204\244\211\120\169\147\034\177\002\124\001\062\098\023\182\155\113\018\034\017\087\128\136\137\038\227\036\064\002\132\004\072\128\144\000\009'..
    '\016\018\080\062\254\001\130\142\247\022\011\054\051\039\000\000\000\000\073\069\078\068\174\066\096\130',
  ['select']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\002\139\073\068\065\084\120\218\237\156\075\142\211'..
    '\064\016\064\095\034\228\204\022\056\212\040\011\190\130\061\071\128\021\156\098\194\017\208\108\065\048\128\068\224\080\100\182\132\077\177\136\145\034\033\039\237\110\027\059\241\123\146\119'..
    '\118\171\082\175\219\149\116\236\154\069\004\050\028\115\083\160\000\005\136\002\020\032\010\080\128\040\064\001\162\000\005\136\002\020\032\010\080\128\040\064\001\053\021\112\005\108\128\024'..
    '\248\216\212\177\084\045\062\231\126\252\057\215\247\055\126\068\164\028\171\024\031\171\196\216\155\226\255\022\017\139\022\099\052\029\139\122\172\172\248\102\137\127\073\254\004\238\141\108'..
    '\245\110\128\251\137\231\054\197\191\006\158\000\219\204\024\022\192\039\096\153\027\223\212\107\192\178\078\224\162\227\228\119\094\003\174\071\152\188\235\142\206\205\145\144\146\252\180\248'..
    '\018\239\115\085\068\092\069\196\102\004\247\254\077\029\075\213\193\125\058\167\038\116\057\022\116\080\132\078\229\168\034\226\203\145\196\125\143\136\139\158\199\152\172\128\210\004\118\158'..
    '\252\041\010\200\077\100\047\201\159\170\128\182\009\237\045\249\109\126\007\156\035\041\223\100\214\123\223\148\014\157\147\253\091\098\054\241\103\067\043\224\003\240\032\243\250\031\192\099'..
    '\224\151\155\113\121\252\006\158\239\205\244\054\172\129\071\037\201\087\192\142\109\061\139\191\182\156\249\079\011\182\048\020\080\176\018\058\153\249\010\200\091\009\157\205\124\005\052\175'..
    '\132\103\013\018\138\011\174\002\218\073\088\001\183\245\177\002\030\118\157\124\191\134\142\000\087\128\002\020\032\010\080\128\040\064\001\162\000\005\200\072\005\156\250\179\161\163\037\117'..
    '\043\098\005\188\028\089\236\111\129\087\083\017\112\234\207\134\090\003\164\076\192\169\063\027\058\090\238\036\158\247\186\046\128\047\128\187\003\199\124\011\188\003\222\076\169\008\139\053'..
    '\064\001\162\000\005\136\002\020\032\010\080\128\040\064\001\231\204\130\221\022\252\223\222\015\043\242\094\230\062\138\091\017\255\210\244\214\140\015\231\014\152\124\128\075\224\006\184\080'..
    '\192\255\079\126\111\018\020\144\158\252\094\036\040\096\087\092\111\104\247\166\228\037\240\177\139\194\060\119\230\243\158\188\150\051\075\224\115\233\074\152\059\243\015\206\252\053\135\095'..
    '\220\043\095\009\182\042\024\182\085\129\201\183\089\135\237\106\076\254\009\052\108\178\101\217\192\045\203\206\177\111\104\073\015\209\020\009\246\013\077\140\063\183\223\207\177\126\067\246'..
    '\013\077\160\164\217\210\182\190\118\093\018\192\148\251\134\150\118\205\061\038\193\190\161\013\241\231\092\223\219\248\254\033\051\048\238\134\042\064\001\162\000\005\136\002\020\032\010\080'..
    '\128\040\064\001\162\000\005\136\002\020\032\010\056\127\254\000\005\083\216\131\146\139\230\088\000\000\000\000\073\069\078\068\174\066\096\130',
  ['import']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\004\077\073\068\065\084\120\218\237\157\207\075\022'..
    '\065\024\199\063\086\188\175\146\090\026\116\201\075\135\010\059\020\100\244\003\162\232\080\098\097\026\036\029\139\254\130\050\168\172\160\083\097\029\180\063\033\188\005\069\189\025\070\157'..
    '\162\130\172\014\118\041\130\136\126\145\145\144\089\025\100\032\211\097\007\020\115\222\247\109\119\223\221\153\157\231\011\011\050\251\178\238\206\103\158\103\230\153\121\118\182\074\041\133'..
    '\040\061\045\144\042\016\000\002\064\036\000\188\213\162\152\175\215\008\116\002\237\064\051\208\004\044\078\249\025\021\240\029\024\001\134\128\002\240\218\022\000\085\049\141\130\106\128\110'..
    '\224\004\080\239\064\195\043\000\103\128\023\089\000\208\164\031\104\131\099\214\063\013\156\003\046\104\043\113\018\064\019\048\012\172\112\216\013\095\005\014\001\083\174\001\168\001\030\057'..
    '\216\242\231\211\029\096\127\026\016\162\140\130\142\101\164\242\001\218\128\027\064\222\021\000\141\186\195\045\214\201\237\004\106\129\170\020\014\147\038\108\131\016\022\064\007\176\196\112'..
    '\238\148\030\138\222\007\126\089\214\210\215\000\015\108\130\016\022\192\062\067\249\077\224\162\197\174\102\012\216\173\125\190\021\016\194\002\088\107\040\191\236\128\191\159\210\029\174\021'..
    '\016\194\142\130\126\106\255\062\087\117\192\164\005\149\108\122\168\217\253\067\014\184\166\163\118\147\238\106\119\250\219\054\000\229\060\160\237\000\172\128\224\251\100\220\031\224\000\048'..
    '\088\228\055\173\186\111\171\022\000\025\132\032\000\082\134\032\000\082\134\032\000\082\134\032\000\082\134\032\000\204\016\186\074\004\107\173\192\149\168\067\111\001\080\060\098\238\044\097'..
    '\009\007\129\211\018\136\085\246\254\242\122\090\162\205\112\126\026\088\079\200\229\077\177\128\232\150\176\016\056\047\022\080\249\251\203\003\247\128\237\134\243\171\009\145\109\145\085\011'..
    '\048\077\008\110\137\104\009\093\004\041\046\243\169\093\092\208\140\222\024\202\031\107\235\008\123\124\193\188\016\213\038\000\102\052\152\194\255\108\145\062\096\070\203\181\063\078\050\073'..
    '\076\133\105\208\089\181\128\049\224\008\201\038\092\133\106\124\089\030\134\094\007\118\001\239\109\190\201\172\186\160\217\170\007\142\235\081\202\042\230\095\074\077\205\010\124\000\096\117'..
    '\156\033\145\112\202\018\000\002\064\000\136\004\128\000\016\009\000\001\032\114\008\192\120\153\101\162\010\001\024\040\179\172\092\229\128\062\013\113\092\255\157\243\035\166\086\042\204\145'..
    '\083\074\245\041\165\198\245\209\167\203\194\094\175\095\253\171\033\165\084\062\194\053\043\121\152\244\223\215\170\178\100\187\154\175\004\239\157\205\085\106\111\047\150\106\183\134\242\204'..
    '\205\005\165\246\246\162\111\163\160\001\095\033\216\226\130\074\037\063\217\230\142\050\231\130\202\073\003\108\035\120\255\184\058\075\022\096\083\031\144\250\235\066\018\009\123\008\193\198'..
    '\081\144\087\016\108\029\134\122\003\193\230\056\192\011\008\166\097\104\014\232\005\014\003\013\014\060\199\059\096\029\193\027\252\078\013\067\077\000\250\129\163\142\053\166\017\146\219\191'..
    '\168\226\000\076\115\051\054\043\084\110\166\004\098\158\203\004\096\192\193\103\121\238\034\000\211\198\173\039\181\153\185\212\009\239\200\210\040\200\022\089\177\167\143\175\125\128\173\149'..
    '\239\069\032\230\069\229\219\010\192\155\202\183\017\128\087\149\111\027\000\239\042\191\216\048\052\105\185\182\036\153\057\011\232\245\177\242\109\138\003\138\205\061\217\088\249\222\204\005'..
    '\101\182\229\071\005\016\119\046\231\128\143\149\031\216\082\124\185\156\253\017\114\045\227\206\053\205\124\110\232\124\062\123\028\088\134\031\170\248\130\076\098\055\224\059\000\089\144\145'..
    '\056\064\000\136\028\004\096\218\147\173\206\131\058\051\109\089\246\035\073\000\163\134\242\022\015\000\108\052\148\127\078\018\192\075\067\121\183\007\000\076\207\152\232\198\173\005\067\121'..
    '\059\017\183\242\181\092\103\129\061\134\115\183\194\092\048\108\028\208\000\188\045\226\015\111\019\100\215\061\035\185\116\193\074\169\014\216\068\240\229\192\189\134\223\076\000\043\041\254'..
    '\161\184\088\001\000\244\016\124\137\084\020\164\241\092\074\210\002\032\200\072\126\088\164\083\242\069\079\008\114\146\166\146\006\000\193\103\108\135\009\062\107\235\163\062\018\108\135\060'..
    '\154\086\032\246\009\216\012\060\245\176\242\071\128\109\081\042\063\174\072\120\084\155\096\079\152\078\200\065\125\035\248\146\236\086\224\067\212\139\197\189\036\185\148\224\075\171\029\064'..
    '\179\118\077\181\142\087\248\164\118\053\175\244\240\187\016\103\067\179\061\055\052\243\146\201\056\001\032\000\068\002\192\095\253\005\050\159\162\224\225\117\056\115\000\000\000\000\073\069'..
    '\078\068\174\066\096\130',
  ['palette']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\009\051\073\068\065\084\120\218\237\157\125\144\087'..
    '\085\025\199\063\251\003\151\052\005\119\067\212\169\108\091\016\045\026\043\226\165\246\133\151\095\073\074\160\036\142\204\048\099\239\229\031\134\017\205\040\173\100\099\142\226\064\141\003'..
    '\163\012\050\142\211\148\070\152\078\003\136\142\105\086\044\088\205\174\089\041\075\188\013\176\005\014\138\152\178\010\203\002\079\127\156\243\155\104\187\207\185\247\254\126\247\237\247\242'..
    '\157\057\179\051\231\236\239\222\115\206\247\156\231\060\231\121\158\115\110\157\136\080\067\122\200\213\186\160\070\064\141\128\026\106\004\084\045\134\102\184\110\117\192\024\224\163\192\101'..
    '\192\088\155\206\007\222\011\052\216\191\057\224\168\077\199\128\035\192\094\096\143\077\187\128\151\108\089\246\026\153\049\045\104\012\240\089\096\186\077\163\034\122\238\000\240\034\240\071'..
    '\160\019\120\022\232\171\017\096\208\008\092\015\124\009\104\077\232\157\199\129\231\128\095\001\235\129\183\170\145\128\060\176\008\248\124\202\162\240\024\240\008\176\018\120\165\210\009\168'..
    '\003\190\000\116\000\159\201\160\072\254\045\240\019\224\233\074\036\096\050\240\000\240\169\050\080\078\126\007\220\010\116\087\002\001\141\192\082\224\027\069\168\189\253\064\023\208\003\236'..
    '\004\254\001\244\002\239\000\111\218\191\167\129\243\108\058\027\248\032\208\012\140\182\090\211\100\224\226\034\234\045\192\047\129\239\001\175\150\043\001\215\001\015\002\035\067\252\166\199'..
    '\046\140\207\003\047\000\239\070\080\143\102\187\192\095\009\092\003\140\008\241\219\035\192\002\224\023\177\244\144\136\196\145\134\137\200\074\009\142\215\069\100\133\136\076\136\169\062\131'..
    '\235\054\075\068\126\046\034\199\067\212\241\009\017\185\032\234\250\196\209\192\102\017\233\014\216\168\094\017\089\032\034\103\039\208\241\094\233\066\017\185\067\068\094\013\088\223\125\034'..
    '\242\137\044\019\048\094\068\014\005\104\200\033\017\249\166\136\212\167\212\241\094\179\098\145\136\188\017\160\238\239\136\200\013\089\036\032\047\034\111\249\084\254\148\136\172\018\145\134'..
    '\140\116\252\224\212\032\034\203\069\228\132\079\059\078\139\200\226\044\017\048\039\128\060\221\037\034\147\050\218\241\094\051\249\229\000\179\225\007\089\032\032\031\160\243\215\137\200\240'..
    '\050\233\252\051\197\210\189\118\180\187\240\195\052\009\024\239\035\118\078\138\200\045\101\214\241\131\211\092\017\233\243\033\225\150\052\008\104\246\089\112\143\139\200\245\101\222\249\133'..
    '\244\113\017\217\239\104\235\128\136\204\040\230\217\197\058\100\134\001\143\057\204\197\071\129\153\192\227\009\155\016\218\129\077\192\065\155\054\218\188\082\241\055\096\138\245\051\104\126'..
    '\149\117\192\229\073\109\196\086\250\140\252\124\010\163\116\137\213\178\188\052\175\142\136\222\113\137\136\236\118\180\253\101\187\118\196\042\130\174\243\145\249\105\136\157\054\165\243\207'..
    '\036\097\106\068\239\106\242\017\189\075\227\036\160\081\068\094\139\099\049\042\049\109\012\160\050\174\143\240\125\173\014\205\239\164\136\076\142\139\128\007\125\084\205\176\207\107\023\145'..
    '\077\034\114\208\166\141\054\047\236\115\014\158\089\145\150\150\022\105\107\107\027\092\191\003\017\147\254\053\071\095\188\034\034\067\162\094\132\039\090\147\178\023\246\000\223\010\185\252'..
    '\044\001\126\111\023\235\139\109\154\101\243\058\074\010\245\200\229\200\229\098\015\248\120\216\161\100\140\003\190\028\229\034\092\039\034\093\014\249\058\041\101\153\157\180\008\042\164\081'..
    '\014\145\220\043\034\239\137\074\004\205\114\052\108\085\006\100\118\139\149\189\046\066\167\196\180\254\204\119\188\119\081\084\004\108\113\088\053\027\050\034\179\059\028\106\232\226\024\021'..
    '\128\058\135\249\125\191\223\090\016\068\080\230\029\225\034\075\172\107\144\012\200\236\123\108\044\209\134\051\054\098\027\128\169\192\189\049\174\005\002\124\095\041\187\004\184\170\212\053'..
    '\096\147\067\198\213\151\137\218\152\068\210\164\196\134\082\102\192\069\192\012\165\108\057\112\162\200\081\179\020\056\229\040\063\109\195\067\202\009\171\149\252\153\192\133\234\236\247\121'..
    '\232\124\037\104\234\048\240\080\009\149\125\001\184\195\118\180\087\231\223\014\108\046\051\002\030\007\222\240\200\031\098\131\207\138\034\224\070\037\127\045\165\007\187\166\037\179\227\012'..
    '\119\092\167\148\093\093\076\088\202\165\054\022\071\219\148\117\083\131\151\184\217\164\132\182\140\242\018\187\057\031\237\071\139\219\169\117\190\030\081\119\076\009\078\027\023\086\004\077'..
    '\087\242\215\087\112\007\150\234\079\056\102\215\055\205\060\017\152\128\058\096\154\082\246\124\133\118\126\084\182\169\191\071\065\192\165\138\234\212\239\096\184\156\209\006\220\169\244\071'..
    '\014\184\203\042\007\065\176\077\201\255\088\024\002\052\215\090\087\068\177\154\089\195\109\062\226\056\135\057\203\016\004\061\074\254\007\162\032\096\091\133\138\159\255\009\153\111\109\109'..
    '\165\189\253\255\068\255\132\128\207\058\172\228\015\015\067\192\101\074\254\206\106\080\101\074\180\077\105\199\157\060\035\178\181\163\065\099\148\252\029\021\218\231\047\218\005\023\128\206'..
    '\206\078\175\255\233\142\131\000\141\230\070\037\191\183\066\009\072\205\054\165\017\112\174\146\127\052\097\189\058\041\068\105\155\026\030\170\239\020\051\233\097\197\180\250\190\140\197\233'..
    '\068\157\166\088\051\248\001\155\214\091\247\105\152\103\076\084\250\110\071\024\143\088\191\242\144\122\201\094\156\078\214\210\087\148\054\111\140\050\052\049\073\189\186\220\160\089\016\182'..
    '\135\089\003\052\089\127\094\010\122\117\057\225\044\116\211\115\103\146\004\068\169\087\151\019\174\198\059\096\249\164\182\136\107\251\128\190\018\009\136\082\175\046\039\220\170\228\063\171'..
    '\237\015\180\097\121\068\201\255\080\214\245\234\020\049\027\061\122\228\145\176\251\128\093\033\077\020\113\234\213\229\128\225\152\203\062\188\112\000\120\034\044\001\154\201\097\108\136\074'..
    '\085\154\207\087\067\029\176\006\104\082\202\151\099\204\248\132\089\003\052\002\198\133\172\220\230\010\027\233\094\248\017\048\207\033\073\086\023\099\138\216\174\228\079\004\206\161\134\194'..
    '\200\191\011\227\073\211\176\192\053\250\093\004\236\006\014\121\228\215\147\220\173\086\089\151\249\107\125\058\255\001\224\153\098\141\113\130\241\240\123\033\095\229\157\063\027\115\104\111'..
    '\158\227\127\186\048\215\220\080\044\001\056\008\184\182\010\059\253\044\204\053\055\091\172\034\209\228\248\223\221\150\164\254\064\114\204\017\152\053\218\062\204\011\147\044\203\149\136\122'..
    '\140\243\164\201\042\029\211\048\145\018\023\004\248\237\030\204\157\068\123\131\190\108\168\207\195\254\002\140\247\040\187\177\012\008\168\179\166\129\249\086\125\030\141\238\104\138\002\093'..
    '\118\228\031\010\245\043\031\211\234\066\199\005\075\231\100\216\036\060\091\068\182\075\114\184\063\236\249\224\160\230\232\181\214\144\052\024\035\209\015\236\165\061\234\111\199\068\239\093'..
    '\158\192\251\118\097\014\096\124\059\168\204\015\059\003\092\135\041\254\153\161\011\151\010\105\089\066\035\254\095\034\242\157\098\071\125\216\051\098\211\029\021\185\041\067\157\063\213\199'..
    '\011\087\042\006\068\228\041\123\040\111\088\084\245\014\122\107\226\086\160\197\035\255\117\059\213\143\164\044\122\134\098\098\150\062\028\193\179\078\096\204\241\175\089\069\164\007\227\076'..
    '\217\076\028\087\028\007\100\106\166\099\100\172\206\192\232\159\225\168\223\078\123\231\079\038\175\073\011\058\003\234\128\063\091\091\144\151\121\185\021\248\083\138\051\224\033\224\235\138'..
    '\042\061\145\008\078\114\198\133\160\126\066\001\110\198\219\190\159\003\030\197\220\235\159\022\218\148\252\197\089\238\252\048\004\020\054\026\107\148\178\102\074\059\180\087\042\052\087\233'..
    '\115\089\223\118\135\245\148\119\216\197\201\011\115\129\239\166\212\142\115\203\213\238\017\150\128\055\049\183\162\104\011\199\143\129\027\082\104\199\126\037\255\115\149\070\000\118\151\185'..
    '\194\241\188\159\097\062\067\146\036\182\042\249\119\147\113\007\082\177\193\058\183\057\140\113\195\128\095\039\076\130\118\110\109\044\198\049\146\093\139\097\009\215\215\055\097\062\138\115'..
    '\145\082\222\143\249\046\204\099\009\180\099\136\181\220\094\161\148\095\069\000\239\084\057\205\000\128\125\214\220\251\182\099\038\172\005\022\038\208\142\083\232\065\081\000\203\200\232\055'..
    '\211\074\173\212\095\129\057\014\075\096\014\184\015\115\143\194\136\152\219\242\012\240\083\165\236\010\224\139\149\072\000\024\215\229\060\031\115\236\092\043\034\062\029\115\123\110\070\063'..
    '\199\150\175\084\002\010\154\145\075\028\021\054\107\091\049\113\050\113\121\166\222\069\143\084\200\100\052\071\212\223\144\249\036\240\148\099\097\046\224\048\038\116\241\097\138\117\100\232'..
    '\104\192\219\058\251\111\091\086\145\051\160\128\151\048\223\007\243\243\023\143\004\086\097\140\101\011\035\214\213\181\054\245\101\113\006\196\161\025\236\195\024\199\086\056\118\204\005\188'..
    '\223\046\210\189\192\253\017\173\017\154\172\127\187\026\068\208\096\204\193\124\198\042\204\071\057\119\242\223\207\088\117\098\190\021\022\020\141\118\246\053\123\148\173\001\110\170\054\002'..
    '\010\050\249\110\219\248\176\051\110\000\115\144\099\027\038\096\120\135\157\045\071\173\076\239\195\120\176\026\237\206\251\030\244\067\230\087\146\065\235\104\146\159\050\156\096\205\002\147'..
    '\082\104\231\094\107\150\056\089\013\107\128\134\110\204\103\005\219\049\031\205\076\010\167\129\175\102\177\243\147\038\160\128\045\024\051\241\052\204\201\249\129\152\223\183\012\248\003\025'..
    '\069\037\127\208\089\048\135\039\238\012\160\141\085\053\001\131\119\203\121\204\209\166\124\128\013\157\134\030\140\201\252\073\050\142\172\017\048\024\099\128\143\096\014\007\142\181\127\071'..
    '\096\124\192\231\099\092\145\245\118\231\187\219\106\073\143\002\191\201\242\168\047\039\002\042\030\185\090\023\212\008\168\017\080\067\141\128\170\197\127\000\225\254\085\109\231\028\065\215'..
    '\000\000\000\000\073\069\078\068\174\066\096\130',
  ['trash']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\003\042\073\068\065\084\120\218\237\157\187\110\019'..
    '\065\020\134\063\035\100\017\097\003\009\029\164\161\012\116\064\184\072\145\016\148\032\019\030\033\188\001\004\132\073\068\141\004\069\156\071\064\121\001\226\144\055\160\009\080\064\195\165'..
    '\067\130\196\084\216\016\140\004\213\080\236\112\017\242\088\078\188\179\059\222\249\127\105\100\233\172\103\143\247\124\187\123\102\103\086\062\037\099\012\082\126\218\163\016\008\128\000\072'..
    '\002\016\173\246\006\246\123\038\128\107\064\013\152\002\038\129\253\067\238\243\059\176\009\188\005\214\128\085\160\019\202\001\151\002\025\005\141\001\243\192\029\224\128\103\095\095\129\007'..
    '\064\003\248\033\000\112\196\158\149\211\025\251\125\005\204\002\031\098\006\048\009\108\000\071\115\242\191\009\156\003\182\098\076\194\099\064\051\199\224\255\062\001\030\003\251\098\004\112'..
    '\011\056\025\064\254\153\006\110\196\006\096\002\184\221\103\123\019\184\008\084\128\210\144\173\002\092\002\158\244\241\119\023\024\207\037\018\198\152\060\218\117\227\086\221\163\223\197\062'..
    '\126\231\242\136\069\094\087\192\085\135\125\213\014\017\125\233\062\176\238\216\086\139\233\022\116\220\097\095\206\192\119\195\097\063\017\211\048\244\155\189\055\255\175\042\208\245\236\187'..
    '\010\108\247\176\119\237\182\040\000\184\156\150\034\241\031\196\048\084\018\000\001\016\000\133\096\052\000\148\129\037\160\109\019\216\176\173\095\114\204\162\249\244\223\182\177\042\167\057'..
    '\010\106\228\057\095\050\162\090\006\110\166\005\224\179\157\191\145\006\087\027\056\172\028\080\144\028\176\162\080\237\088\003\197\108\208\069\249\186\077\048\115\228\053\109\059\058\234\000'..
    '\143\072\166\184\051\155\138\008\230\209\126\212\166\046\148\003\244\032\038\000\146\000\008\128\036\000\002\032\009\128\000\072\002\032\000\146\000\008\128\020\057\128\127\215\160\119\180\198'..
    '\154\082\255\236\148\210\091\190\046\237\118\127\141\030\251\106\100\216\223\247\241\253\105\161\174\007\244\090\131\030\104\141\053\165\254\190\143\239\239\014\002\005\048\236\254\066\251\061'..
    '\074\194\074\194\146\000\008\128\036\000\002\032\009\128\000\072\002\032\000\146\000\008\128\036\000\002\032\000\146\000\008\128\036\000\002\032\009\128\000\072\002\032\000\146\000\036\047\081'..
    '\013\098\243\213\063\122\000\043\003\218\124\245\207\078\129\190\027\090\054\198\044\025\099\218\182\045\089\091\086\253\163\127\055\052\184\243\212\215\241\041\009\043\007\008\128\036\000\002'..
    '\032\009\128\000\072\002\032\000\187\149\171\232\066\181\000\049\058\232\176\111\135\004\160\229\176\159\042\000\128\211\014\251\167\144\000\188\113\216\231\011\000\192\117\012\175\067\002\208'..
    '\116\216\107\192\226\008\007\255\030\112\217\177\109\045\013\007\105\077\198\141\003\239\251\220\047\215\073\254\129\253\005\073\001\159\144\085\005\206\144\252\243\249\021\199\119\190\000\199'..
    '\236\103\016\000\000\022\072\234\116\197\160\058\240\048\164\043\000\146\130\152\079\251\036\173\162\232\025\112\001\248\025\026\000\072\042\163\110\144\084\041\045\162\062\146\148\191\109\133'..
    '\250\032\182\005\156\005\158\023\048\248\047\129\153\052\131\239\235\073\184\101\047\209\133\052\146\084\000\234\144\148\090\063\143\135\234\219\190\043\233\029\034\041\027\062\011\076\217\091'..
    '\083\037\240\128\119\237\173\230\157\029\094\055\125\158\072\033\212\148\143\090\154\140\019\000\001\144\004\032\094\253\002\052\233\115\139\073\195\018\016\000\000\000\000\073\069\078\068\174'..
    '\066\096\130',
  ['close']=
    '\137\080\078\071\013\010\026\010\000\000\000\013\073\072\068\082\000\000\000\096\000\000\000\096\008\006\000\000\000\226\152\119\056\000\000\002\069\073\068\065\084\120\218\237\156\203\078\195'..
    '\048\016\069\111\187\104\186\134\111\066\168\170\064\032\241\093\201\063\116\141\000\129\120\169\223\068\215\180\155\097\019\054\165\143\164\052\245\076\124\174\228\077\026\169\227\123\018\219'..
    '\177\199\030\152\153\080\058\013\177\000\000\000\064\000\000\000\002\000\000\016\000\000\128\000\000\000\004\000\000\032\000\000\000\001\000\000\008\000\000\064\000\000\064\075\141\036\149\146'..
    '\022\117\041\235\107\081\116\186\248\205\172\139\082\217\095\189\153\089\209\209\255\029\179\020\117\172\235\170\186\248\191\065\071\105\041\095\146\206\054\092\127\151\116\043\105\233\244\201'..
    '\047\036\061\074\154\108\248\109\033\233\060\122\031\048\169\043\088\004\051\063\092\031\048\011\006\161\137\249\179\072\125\192\182\118\212\099\159\144\052\214\046\043\054\050\179\231\061\021'..
    '\251\048\179\113\066\243\147\199\216\251\010\122\143\045\155\138\122\141\041\187\010\123\123\032\114\123\229\221\189\141\057\181\187\046\251\163\092\070\030\110\007\003\057\012\255\092\015\135'..
    '\083\126\000\157\194\024\247\223\034\169\191\066\187\052\040\194\135\160\060\076\255\118\097\084\008\243\189\000\056\182\097\097\204\247\004\224\088\198\133\050\223\027\128\255\026\024\206\124'..
    '\143\000\014\053\050\164\249\094\001\180\053\052\172\249\093\174\009\031\043\051\225\094\210\213\142\123\230\146\086\146\166\059\238\249\148\116\035\233\219\099\037\061\003\104\010\065\081\205'..
    '\143\144\152\181\146\116\039\233\165\143\230\071\201\140\059\004\066\008\243\035\052\065\235\205\209\195\158\246\254\183\095\184\142\096\062\185\161\000\104\221\025\079\027\220\123\033\233\073'..
    '\210\024\000\233\070\066\151\081\032\012\123\104\126\040\008\195\224\230\207\037\189\134\134\192\084\004\115\065\076\198\049\029\013\000\022\100\088\146\100\081\158\069\121\210\082\072\204\034'..
    '\049\139\212\196\254\003\032\057\151\244\244\060\211\211\217\160\193\022\165\060\183\040\177\073\143\109\170\121\110\083\101\163\118\066\000\028\085\144\024\064\021\196\252\054\016\170\072\185'..
    '\161\219\206\011\146\252\158\025\180\239\196\148\094\156\023\228\249\192\166\101\029\219\123\031\022\229\103\193\204\111\002\033\212\121\065\035\051\043\205\108\081\151\178\190\166\032\229\100'..
    '\241\071\202\013\037\053\017\001\000\000\008\000\000\064\000\000\000\002\000\000\016\000\000\128\000\000\000\004\000\000\032\000\000\000\001\000\000\008\000\161\244\003\204\185\040\117\240\247'..
    '\149\051\000\000\000\000\073\069\078\068\174\066\096\130',
}
function UI.icon_image(kind)
  UI.quick_icons=UI.quick_icons or {}
  local image=UI.quick_icons[kind]
  if not image then
    image=ImGui.CreateImageFromMem(UI.quick_icon_png[kind])
    ImGui.Attach(ctx,image)
    UI.quick_icons[kind]=image
  end
  return image
end
function UI.timecode_badge(block)
  local fps,drop_frame=project_timecode_settings()
  local time,stamp=M.block_time(block,fps,drop_frame)
  if time==nil then return false,false end
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  local available=ImGui.GetContentRegionAvail(ctx)
  ImGui.BeginGroup(ctx)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local height=ImGui.GetTextLineHeight(ctx)
  local side=math.min(UI_METRICS.timecode_icon_size,height)
  ImGui.Dummy(ctx,side,height)
  local color=ImGui.GetColor(ctx,ImGui.Col_TextDisabled)
  local image=UI.icon_image('clock')
  ImGui.DrawList_AddImage(ImGui.GetWindowDrawList(ctx),image,sx,sy+(height-side)*0.5,
    sx+side,sy+(height+side)*0.5,0,0,1,1,color)
  local caption=stamp or M.timecode_label(time)
  local caption_width=ImGui.CalcTextSize(ctx,caption)
  if available>=side+UI_METRICS.timecode_label_gap+caption_width then
    ImGui.SameLine(ctx,0,UI_METRICS.timecode_label_gap)
    ImGui.TextDisabled(ctx,caption)
  end
  ImGui.EndGroup(ctx)
  local hovered=ImGui.IsItemHovered(ctx)
  ImGui.SetItemTooltip(ctx,tr('Timeline position')..': '..caption..'\n'..tr('Click to go to timecode'))
  ImGui.PopFont(ctx)
  return hovered,true
end
function UI.quick_access_button(id,caption,kind,side,selected,instruction)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local clicked=UI.source_button('quick_'..id,'',side,side,selected)
  local image=UI.icon_image(kind)
  local icon_side=math.max(0,math.min(UI_METRICS.quick_icon_size,side-UI_METRICS.quick_icon_total_inset))
  local offset=(side-icon_side)*0.5
  local color=ImGui.GetColor(ctx,ImGui.Col_Text)
  ImGui.DrawList_AddImage(ImGui.GetWindowDrawList(ctx),image,
    sx+offset,sy+offset,sx+offset+icon_side,sy+offset+icon_side,
    0,0,1,1,color)
  local hint=tr(caption)
  local detail=instruction and tr(instruction)
  if detail and detail~=hint then hint=hint..'\n'..detail end
  ImGui.SetItemTooltip(ctx,hint)
  return clicked
end
-- Editing belongs to one existing block in one owner/document generation.
function UI.note_edit_valid(edit)
  if not (edit and edit.owner==session and edit.epoch==epoch and session
      and edit.doc==session.doc and not session.error and not session.conflict
      and not modal and not UI.info and not bulk_selection
      and not UI.note_drag and not UI.place and M.visible(edit.block,hide_completed)
      and startup_layout_frames>=STARTUP_LAYOUT_FRAMES) then return false end
  local tab,column=M.note_location(session.doc,edit.block)
  return tab~=nil and tab.id==edit.tab_id and column==edit.column and not tab.folded and not column.folded
end
function UI.note_editing(block)
  local edit=UI.note_edit
  return edit~=nil and edit.block==block
end
-- Keep a draft until it is deliberately committed. This makes Esc a real
-- cancellation, rather than an attempt to undo already serialized keystrokes.
function UI.end_note_edit(discard)
  local edit=UI.note_edit
  UI.note_edit=nil;UI.new_input=nil;UI.note_press=nil
  UI.end_edit_after_frame=nil;UI.note_outside_press=nil
  UI.note_cancel_prompt=nil
  if edit then
    if not discard and edit.original~=nil and edit.value~=edit.original
        and edit.owner==session and edit.doc==session.doc
        and not session.error and not session.conflict
        and api.valid(session.target) then
      local tab,column=M.note_location(edit.doc,edit.block)
      if tab and column==edit.column and tab.id==edit.tab_id then
        if edit.block.kind=='check' then edit.block.label=edit.value
        else edit.block.text=edit.value end
        touch(nil,'edit_note')
      end
    end
    edit.owner.history.key=nil;edit.owner.input_state=nil
    if edit.owner==session then undo_boundary=true end
  end
end
function UI.activate_note(tab,column,block)
  UI.end_note_edit()
  session.active_group_id=column.id
  local original=(block.kind=='check' and block.label)
    or ((block.kind=='text' or block.kind=='note') and block.text)
  local edit={owner=session,doc=session.doc,epoch=epoch,tab_id=tab.id,
    column=column,block=block,original=original,value=original,focus=true}
  if not UI.note_edit_valid(edit) then return end
  UI.note_edit=edit
end
function UI.request_note_cancel()
  local edit=UI.note_edit
  if not edit or UI.note_cancel_prompt then return end
  if edit.original==nil or edit.value==edit.original then
    UI.end_note_edit(true)
  else
    UI.note_cancel_prompt={edit=edit,open=true}
    UI.note_outside_press=nil;UI.end_edit_after_frame=nil
  end
end
function UI.note_edit_update()
  local edit=UI.note_edit
  if edit and (not UI.note_edit_valid(edit) or history_request) then
    UI.end_note_edit();return
  end
  if edit and escape_pressed then
    UI.request_note_cancel();return
  end
  if UI.note_cancel_prompt then return end
  if edit and edit.rect then
    local x,y=ImGui.GetMousePos(ctx)
    local r=edit.rect
    local outside=x<r[1] or x>=r[3] or y<r[2] or y>=r[4]
    for button=0,1 do
      if outside and ImGui.IsMouseClicked(ctx,button) then
        UI.note_outside_press={edit=edit,button=button}
      end
    end
  end
  local outside_press=UI.note_outside_press
  if outside_press and outside_press.edit==edit and not ImGui.IsMouseDown(ctx,outside_press.button) then
    -- The pressed control keeps its geometry until mouse release.
    UI.end_edit_after_frame=edit;UI.note_outside_press=nil
  end
  local press=UI.note_press
  if press then
    local x,y=ImGui.GetMousePos(ctx)
    if (x-press.x)^2+(y-press.y)^2>UI_METRICS.pointer_drag_threshold^2 then press.dragged=true end
    if press.owner~=session or press.epoch~=epoch or UI.note_drag
        or (not ImGui.IsMouseDown(ctx,0) and not ImGui.IsMouseReleased(ctx,0)) then UI.note_press=nil end
  end
end
function UI.note_text_click(tab,column,block,hovered)
  if modal or UI.info or UI.note_drag or bulk_selection
      or startup_layout_frames<STARTUP_LAYOUT_FRAMES then return end
  if hovered and ImGui.IsMouseClicked(ctx,0) then
    local x,y=ImGui.GetMousePos(ctx)
    UI.note_press={block=block,owner=session,epoch=epoch,x=x,y=y}
  end
  local press=UI.note_press
  if press and press.block==block and ImGui.IsMouseReleased(ctx,0) then
    UI.note_press=nil
    if hovered and not press.dragged and press.owner==session and press.epoch==epoch then
      UI.activate_note(tab,column,block)
    end
  end
end
-- Keep focus requests until native multiline navigation actually activates.
function UI.input_focus_valid(request)
  local edit=UI.note_edit
  return request~=nil and UI.note_edit_valid(edit) and request.owner==session
    and request.epoch==epoch and request.tab_id==edit.tab_id and request.column==edit.column
    and request.key==(edit.block.kind=='check' and 'label:' or 'text:')..edit.block.id
end
-- Shared wrapped draft editor: native child scrolling and native text-input/IME
-- bridge, with source-based cursor/selection/history and visual rows only.
function UI.wrapped_editor(m,height,id,save_on_enter)
  local before=m.value
  local e=m.source_editor
  if not e or e.text~=m.value then e=M.editor_new(m.value);m.source_editor=e end
  if m.focus then e.focused=true;e.focus_pending=true;m.focus=nil end
  local now=reaper.time_precise()
  e.blink_time=e.blink_time or now
  local font_size=ImGui.GetFontSize(ctx)
  if e.font_size~=font_size then e.glyphs={};e.rows=nil;e.font_size=font_size end
  local tab_text=string.rep(' ',UI_METRICS.editor_tab_spaces)
  local function measure(char)
    local w=e.glyphs[char]
    if w==nil then
      w=ImGui.CalcTextSize(ctx,char=='\t' and tab_text or char)
      w=math.max(0,w);e.glyphs[char]=w
    end
    return w
  end
  local pad_x,pad_y=ImGui.GetStyleVar(ctx,ImGui.StyleVar_FramePadding)
  local background=ImGui.GetStyleColor(ctx,ImGui.Col_FrameBg)
  ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,background)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,pad_x+UI_METRICS.editor_extra_pad_x,pad_y+UI_METRICS.editor_extra_pad_y)
  local visible=ImGui.BeginChild(ctx,id or 'import_source_wrapped',0,height,ImGui.ChildFlags_Borders)
  ImGui.PopStyleVar(ctx);ImGui.PopStyleColor(ctx)
  if not visible then ImGui.EndChild(ctx); return false,m.value end
  local origin_x,origin_y=ImGui.GetCursorScreenPos(ctx)
  local window_x,window_y=ImGui.GetWindowPos(ctx)
  local window_w,window_h=ImGui.GetWindowSize(ctx)
  local scrollbar=ImGui.GetStyleVar(ctx,ImGui.StyleVar_ScrollbarSize)
  -- Reserve scrollbar width even before it appears, avoiding a reflow cycle.
  local wrap_width=math.max(1,window_w-2*(pad_x+UI_METRICS.editor_extra_pad_x)-scrollbar-UI_METRICS.editor_wrap_right_inset)
  local line_h=ImGui.GetTextLineHeight(ctx)
  local scroll=ImGui.GetScrollY(ctx)
  local view_h=math.max(1,window_h-2*(pad_y+UI_METRICS.editor_extra_pad_y))
  local view_top=origin_y+scroll
  local function layout()
    if not e.rows or e.wrap_width~=wrap_width then
      e.rows=M.editor_rows(e.text,wrap_width,measure);e.wrap_width=wrap_width
    end
    return e.rows
  end
  local reflowed=not e.rows or e.wrap_width~=wrap_width
  local rows=layout()
  local mx,my=ImGui.GetMousePos(ctx)
  local hovered=ImGui.IsWindowHovered(ctx)
  local over_text=hovered and mx>=origin_x and mx<origin_x+wrap_width
    and my>=view_top and my<view_top+view_h
  if over_text then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_TextInput) end
  local mods=ImGui.GetKeyMods(ctx)
  local shift=(mods&ImGui.Mod_Shift)~=0
  local primary=(mods&ImGui.Mod_Ctrl)~=0 and (mods&ImGui.Mod_Alt)==0
  local os=reaper.GetOS()
  local mac=os:match('OSX') or os:match('macOS')
  local word=(mods&ImGui.Mod_Alt)~=0 or (primary and not mac)
  local function hit()
    local row=math.max(1,math.min(#rows,math.floor((my-origin_y)/line_h)+1))
    local pos=M.editor_hit(e.text,rows[row],mx-origin_x,measure)
    return pos,pos==rows[row].last and not rows[row].hard
  end
  local follow=e.focused and reflowed
  if ImGui.IsMouseClicked(ctx,0) then
    if over_text then
      local pos,upstream=hit()
      M.editor_move(e,pos,shift,upstream)
      if ImGui.IsMouseDoubleClicked(ctx,0) then
        local first=M.editor_word(e.text,pos,-1)
        local last=M.editor_word(e.text,first,1)
        while last>first and e.text:sub(M.editor_prev(e.text,last)+1,last):match('^%s+$') do last=M.editor_prev(e.text,last) end
        e.anchor=first;e.cursor=last
      end
      e.focused=true;e.focus_pending=true;e.dragging=true;follow=true
    elseif not hovered then
      e.focused=false;e.focus_pending=false;e.dragging=nil
    end
  end
  if e.dragging then
    if ImGui.IsMouseDown(ctx,0) then
      if not ImGui.IsMouseClicked(ctx,0) then
        local pos,upstream=hit();M.editor_move(e,pos,true,upstream);follow=true
      end
    else e.dragging=nil end
  end
  -- Read committed characters before native InputText consumes its queue.
  -- The bridge rejects them from its empty buffer; the draft stores them once.
  local characters={}
  local index=0
  while true do
    local ok,codepoint=ImGui.GetInputQueueCharacter(ctx,index)
    if not ok then break end
    if codepoint>=32 and codepoint~=127 and codepoint<=0x10FFFF
        and not (codepoint>=0xD800 and codepoint<=0xDFFF) then
      characters[#characters+1]=utf8.char(codepoint)
    end
    index=index+1
  end
  local selected_first,selected_last=M.editor_range(e)
  local preserve_clipboard
  if e.focused and primary and selected_first==selected_last
      and (ImGui.IsKeyPressed(ctx,ImGui.Key_C,false) or ImGui.IsKeyPressed(ctx,ImGui.Key_X,false)) then
    preserve_clipboard=ImGui.GetClipboardText(ctx)
  end
  local cursor_row=M.editor_row(e,rows)
  local caret_x=M.editor_x(e.text,rows[cursor_row],e.cursor,measure)
  local input_x=origin_x+math.max(0,math.min(wrap_width-1,caret_x))
  local input_y=math.max(view_top,math.min(view_top+math.max(0,view_h-line_h),origin_y+(cursor_row-1)*line_h))
  ImGui.SetCursorScreenPos(ctx,input_x,input_y)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,0,0)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameBorderSize,0)
  for _,color in ipairs({ImGui.Col_FrameBg,ImGui.Col_FrameBgHovered,ImGui.Col_FrameBgActive,
      ImGui.Col_Border,ImGui.Col_Text,ImGui.Col_TextSelectedBg,ImGui.Col_InputTextCursor,ImGui.Col_NavCursor}) do
    ImGui.PushStyleColor(ctx,color,0x00000000)
  end
  if e.focused and (e.focus_pending or not e.bridge_active) and not ImGui.IsMouseDown(ctx,0) then
    ImGui.SetKeyboardFocusHere(ctx)
  end
  if not UI.import_capture then
    -- Completion owns an unmodified Tab key; CharFilter keeps the bridge empty.
    -- Committed text, clipboard operations and selection belong to the draft.
    UI.import_capture=ImGui.CreateFunctionFromEEL('EventChar=0;')
    ImGui.Attach(ctx,UI.import_capture)
  end
  local keep_active=ImGui.GetConfigVar(ctx,ImGui.ConfigVar_InputTextEnterKeepActive)
  ImGui.SetConfigVar(ctx,ImGui.ConfigVar_InputTextEnterKeepActive,1)
  ImGui.SetNextItemWidth(ctx,1)
  ImGui.InputText(ctx,'##import_text','',ImGui.InputTextFlags_NoUndoRedo|
    ImGui.InputTextFlags_CallbackCharFilter|ImGui.InputTextFlags_CallbackCompletion,UI.import_capture)
  ImGui.SetConfigVar(ctx,ImGui.ConfigVar_InputTextEnterKeepActive,keep_active)
  if preserve_clipboard~=nil then ImGui.SetClipboardText(ctx,preserve_clipboard) end
  e.bridge_active=ImGui.IsItemActive(ctx)
  if e.bridge_active then e.focused=true;e.focus_pending=false end
  ImGui.PopStyleColor(ctx,8);ImGui.PopStyleVar(ctx,2)
  local function pressed(key,repeat_key)return ImGui.IsKeyPressed(ctx,key,repeat_key or false)end
  local function move(pos,upstream)
    M.editor_move(e,pos,shift,upstream);follow=true
  end
  local function replace(value,gesture,first,last)
    if M.editor_replace(e,value,now,gesture,first,last) then follow=true end
  end
  if e.focused and not UI.note_cancel_prompt
      and ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_RootAndChildWindows) then
    local first,last=M.editor_range(e)
    local command=false
    if primary then
      if pressed(ImGui.Key_A) then e.anchor=0;e.cursor=#e.text;e.history.key=nil;follow=true;command=true
      elseif pressed(ImGui.Key_C) then
        if first~=last then ImGui.SetClipboardText(ctx,e.text:sub(first+1,last)) end
        command=true
      elseif pressed(ImGui.Key_X) then
        if first~=last then ImGui.SetClipboardText(ctx,e.text:sub(first+1,last));replace('','cut') end
        command=true
      elseif pressed(ImGui.Key_V) then replace(ImGui.GetClipboardText(ctx),'paste');command=true
      elseif pressed(ImGui.Key_Z) then follow=M.editor_history(e,shift and 1 or -1) or follow;command=true
      elseif pressed(ImGui.Key_Y) then follow=M.editor_history(e,1) or follow;command=true end
    end
    if not command then
      if pressed(ImGui.Key_LeftArrow,true) then
        move(primary and mac and rows[M.editor_row(e,rows)].first or not shift and first~=last and first or word and M.editor_word(e.text,e.cursor,-1) or M.editor_prev(e.text,e.cursor))
      elseif pressed(ImGui.Key_RightArrow,true) then
        move(primary and mac and rows[M.editor_row(e,rows)].last or not shift and first~=last and last or word and M.editor_word(e.text,e.cursor,1) or M.editor_next(e.text,e.cursor),primary and mac)
      elseif pressed(ImGui.Key_UpArrow,true) or pressed(ImGui.Key_DownArrow,true)
          or pressed(ImGui.Key_PageUp,true) or pressed(ImGui.Key_PageDown,true) then
        local delta=pressed(ImGui.Key_UpArrow,true) and -1 or pressed(ImGui.Key_DownArrow,true) and 1
          or (pressed(ImGui.Key_PageUp,true) and -1 or 1)*math.max(1,math.floor(view_h/line_h)-1)
        if primary and mac then move(delta<0 and 0 or #e.text)
        else
          local pos,x,upstream=M.editor_vertical(e,rows,delta,measure)
          move(pos,upstream);e.preferred_x=x
        end
      elseif pressed(ImGui.Key_Home,true) then move(primary and 0 or rows[M.editor_row(e,rows)].first)
      elseif pressed(ImGui.Key_End,true) then
        local row=rows[M.editor_row(e,rows)];move(primary and #e.text or row.last,not primary and not row.hard)
      elseif pressed(ImGui.Key_Backspace,true) then
        if first==last then first=primary and mac and rows[M.editor_row(e,rows)].first or word and M.editor_word(e.text,first,-1) or M.editor_prev(e.text,first) end
        replace('',nil,first,last)
      elseif pressed(ImGui.Key_Delete,true) then
        if first==last then last=word and M.editor_word(e.text,last,1) or M.editor_next(e.text,last) end
        replace('',nil,first,last)
      elseif pressed(ImGui.Key_Enter,true) or pressed(ImGui.Key_KeypadEnter,true) then
        if save_on_enter and not shift then m.commit_requested=true
        else replace('\n') end
      elseif pressed(ImGui.Key_Tab,true) then
        if shift then e.focused=false;e.focus_pending=false else replace('\t') end
      end
      if #characters>0 and not primary then replace(table.concat(characters)) end
    end
  end
  -- Keep recovery data current even if a later drawing call fails.
  m.value=e.text
  rows=layout();cursor_row=M.editor_row(e,rows)
  if follow then
    e.blink_time=now
    local top=(cursor_row-1)*line_h
    if top<scroll then ImGui.SetScrollY(ctx,top)
    elseif top+line_h>scroll+view_h then ImGui.SetScrollY(ctx,top+line_h-view_h) end
  end
  local draw_list=ImGui.GetWindowDrawList(ctx)
  local text_color=ImGui.GetColor(ctx,ImGui.Col_Text)
  local selection_color=ImGui.GetColor(ctx,ImGui.Col_TextSelectedBg)
  local first,last=M.editor_range(e)
  local start_row=math.max(1,math.floor(scroll/line_h)+1)
  local end_row=math.min(#rows,math.ceil((scroll+view_h)/line_h)+1)
  for i=start_row,end_row do
    local row=rows[i]
    local y=origin_y+(i-1)*line_h
    if e.focused and first~=last and last>row.first and first<=row.last then
      local x1=M.editor_x(e.text,row,math.max(first,row.first),measure)
      local x2=M.editor_x(e.text,row,math.min(last,row.last),measure)
      if row.hard and last>row.last then x2=x2+math.max(UI_METRICS.editor_newline_selection_min_width,measure(' ')) end
      x1=math.min(wrap_width,x1);x2=math.min(wrap_width,x2)
      if x2>x1 then ImGui.DrawList_AddRectFilled(draw_list,origin_x+x1,y,origin_x+x2,y+line_h,selection_color) end
    end
    local rendered=e.text:sub(row.first+1,row.last):gsub('\t',tab_text)
    ImGui.DrawList_AddText(draw_list,origin_x,y,text_color,rendered)
  end
  if e.focused and (now-(e.blink_time or now))%UI_METRICS.editor_caret_period<UI_METRICS.editor_caret_visible_time then
    local x=math.min(wrap_width,M.editor_x(e.text,rows[cursor_row],e.cursor,measure))
    local y=origin_y+(cursor_row-1)*line_h
    ImGui.DrawList_AddLine(draw_list,origin_x+x,y,origin_x+x,y+line_h,text_color,UI_METRICS.editor_caret_thickness)
  end
  -- The complete content extent is registered with a real item after restoring
  -- the cursor. This also registers blank lines below the last visible glyph.
  ImGui.SetCursorScreenPos(ctx,origin_x,origin_y)
  ImGui.Dummy(ctx,0,math.max(line_h,#rows*line_h))
  ImGui.EndChild(ctx)
  return e.text~=before,e.text
end
function UI.import_source(m,height)
  return UI.wrapped_editor(m,height,'import_source_wrapped',false)
end

function UI.confirm_geometry(title,message)
  local delete_w,delete_h=UI.button_size(tr('Delete'))
  local cancel_w,cancel_h=UI.button_size(tr('Cancel'))
  local content_w=math.max(ImGui.CalcTextSize(ctx,tr(title)),
    ImGui.CalcTextSize(ctx,tr(message)),delete_w+UI_METRICS.item_gap_x+cancel_w)
  local width=math.ceil(math.max(UI_METRICS.confirm_min_width,
    math.min(UI_METRICS.confirm_max_width,content_w+2*UI_METRICS.window_pad_x)))
  width=math.max(width,delete_w+cancel_w+UI_METRICS.item_gap_x+2*UI_METRICS.window_pad_x)
  local _,title_h=ImGui.CalcTextSize(ctx,tr(title))
  local _,message_h=ImGui.CalcTextSize(ctx,tr(message),nil,nil,false,math.max(1,width-2*UI_METRICS.window_pad_x))
  local height=math.ceil(2*UI_METRICS.window_pad_y+title_h+1+message_h+
    math.max(delete_h,cancel_h)+3*UI_METRICS.item_gap_y)
  return width,height
end
function UI.name_geometry(title)
  local apply_w,button_h=UI.button_size(tr('Apply'))
  local cancel_w=UI.button_size(tr('Cancel'))
  local width=math.max(UI_METRICS.popup_sizes.name[1],
    ImGui.CalcTextSize(ctx,tr(title))+2*UI_METRICS.window_pad_x,
    apply_w+cancel_w+UI_METRICS.item_gap_x+2*UI_METRICS.window_pad_x)
  local height=math.max(UI_METRICS.popup_sizes.name[2],
    2*UI_METRICS.window_pad_y+ImGui.GetTextLineHeight(ctx)+1+
    ImGui.GetFrameHeight(ctx)+button_h+4*UI_METRICS.item_gap_y)
  return math.ceil(width),math.ceil(height)
end
-- Keep native selection, overflow scrolling and keyboard navigation. Suppress
-- only the tab header's mouse-down action; never disable its document contents.
-- Recognize a double-click on press; perform its action on the second release.
function UI.double_click_released(key,hovered)
  -- ReaImGui 0.10 does not expose ImGui.GetID. Use a stable UI-local key.
  local id=key
  if hovered and ImGui.IsMouseDoubleClicked(ctx,0) then
    UI.double_press={id=id,owner=session,epoch=epoch}
  end
  local press=UI.double_press
  if ImGui.IsMouseReleased(ctx,0) and press and press.id==id then
    UI.double_press=nil
    return hovered and press.owner==session and press.epoch==epoch
  end
  return false
end
function UI.seek_note(b,hovered)
  if bulk_selection or UI.note_drag or startup_layout_frames<STARTUP_LAYOUT_FRAMES then return end
  -- Use an explicit press/release gesture; a click on the badge must not
  -- start text editing or unexpectedly seek while dragging the mouse.
  if hovered and ImGui.IsMouseClicked(ctx,0) then
    local mx,my=ImGui.GetMousePos(ctx)
    UI.timecode_press={block=b,owner=session,epoch=epoch,x=mx,y=my}
  end
  local press=UI.timecode_press
  if not press or press.block~=b then return end
  if ImGui.IsMouseReleased(ctx,0) then
    UI.timecode_press=nil
    local mx,my=ImGui.GetMousePos(ctx)
    local dragged=(mx-press.x)^2+(my-press.y)^2>UI_METRICS.pointer_drag_threshold^2
    if not hovered or dragged or press.block~=b or press.owner~=session or press.epoch~=epoch
        or not session or not session.target or not api.valid(session.target) then return end
    local fps,drop_frame=project_timecode_settings()
    local offset=reaper.GetProjectTimeOffset(session.proj,false)
    local position=M.seek_position(b,offset,fps,drop_frame)
    if position~=nil then
      -- Commit an active note draft before giving keyboard focus to REAPER.
      if UI.note_edit then UI.end_note_edit() end
      reaper.SetEditCurPos2(session.proj,position,true,false)
      -- The edit cursor position alone doesn't transfer keyboard focus from
      -- an undocked ImGui window. This is the native REAPER arrange focus API.
      reaper.SetCursorContext(1,nil)
    end
  elseif not ImGui.IsMouseDown(ctx,0) then
    UI.timecode_press=nil
  end
end
-- Native modal dimming with outside-click cancellation. Check nested popups
-- before rendering them, so selecting an option outside the modal is safe.
function UI.modal_cancelled(m)
  local nested=ImGui.IsPopupOpen(ctx,'',ImGui.PopupFlags_AnyPopupId)
  local x,y=ImGui.GetWindowPos(ctx)
  local w,h=ImGui.GetWindowSize(ctx)
  local mx,my=ImGui.GetMousePos(ctx)
  local outside=mx<x or mx>=x+w or my<y or my>=y+h
  for button=0,1 do
    if ImGui.IsMouseClicked(ctx,button) then
      m.outside_press=outside and not nested and button or nil
    end
    if m.outside_press==button and ImGui.IsMouseReleased(ctx,button) then
      m.outside_press=nil
      if outside and not nested then return true end
    end
  end
  return escape_pressed
end
function UI.help_url()
  return REPOSITORY_URL..'/blob/main/'..(language=='ru' and 'README_RU.md' or 'README.md')
end
function UI.toolbar_next(row,width)
  if row.used>0 and row.used+UI_METRICS.group_gap+width<=row.width then
    ImGui.SameLine(ctx,0,UI_METRICS.group_gap)
    row.used=row.used+UI_METRICS.group_gap+width
  else row.used=width end
end
function UI.toolbar_right(row,width)
  if row.used>0 and row.used+UI_METRICS.group_gap+width<=row.width then
    ImGui.SameLine(ctx,0,row.width-row.used-width)
  else
    -- Register the empty leading space as an item on the next row instead
    -- of moving the cursor beyond the last submitted item.
    local spacer=math.max(0,row.width-width)
    if spacer>0 then ImGui.Dummy(ctx,spacer,0);ImGui.SameLine(ctx,0,0) end
  end
  row.used=row.width
end
-- Authored dialogs use the configured outer margin and centering.
-- Content edits never resize a dialog; only a resized host can constrain it.
function UI.popup_dimensions(kind)
  local m=UI_METRICS
  local dimensions=m.popup_sizes[kind] or m.popup_sizes.name
  local width,height=table.unpack(dimensions)
  local primary=kind=='note_cancel' and 'Discard changes' or kind=='import' and 'Import' or kind=='restore' and 'Restore' or 'Apply'
  local button_w,button_h=UI.button_size(tr(primary))
  local cancel_w,cancel_h=UI.button_size(tr(kind=='note_cancel' and 'Continue editing' or 'Cancel'))
  button_h=math.max(button_h,cancel_h)
  local content_h=0
  if kind=='import' then
    content_h=m.import_pane_min_height
  elseif kind=='select' then content_h=m.options_panel_min_height
  end
  width=math.max(width,button_w+cancel_w+m.item_gap_x+2*m.window_pad_x)
  height=math.max(height,2*m.window_pad_y+ImGui.GetTextLineHeight(ctx)+1+
    2*m.item_gap_y+button_h+m.popup_footer_gap+content_h)
  return width,height
end
function UI.place_popup(width,height)
  local x,y=ImGui.GetWindowPos(ctx)
  local ww,wh=ImGui.GetWindowSize(ctx)
  local margin=UI_METRICS.popup_margin
  width=math.min(width,math.max(1,ww-2*margin))
  height=math.min(height,math.max(1,wh-2*margin))
  ImGui.SetNextWindowPos(ctx,x+(ww-width)*0.5,y+(wh-height)*0.5,ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx,width,height,ImGui.Cond_Always)
  ImGui.SetNextWindowSizeConstraints(ctx,width,height,width,height)
  return width,height
end
-- Called only from the stable root window scope. A false BeginPopupModal
-- can mean clipped, not closed: keep ownership and retry on a visible frame.
function UI.close_modal_if_open(title)
  if not ImGui.IsPopupOpen(ctx,title) then return true end
  if ImGui.BeginPopupModal(ctx,title,nil,
      ImGui.WindowFlags_NoTitleBar|ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings) then
    ImGui.CloseCurrentPopup(ctx);ImGui.EndPopup(ctx);return true
  end
  return false
end
function UI.popup_body(id,button_caption)
  local _,button_h=UI.button_size(button_caption)
  -- Layout-only children inherit the popup surface, not the document paper.
  ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0)
  local visible=ImGui.BeginChild(ctx,id,0,-button_h-UI_METRICS.popup_footer_gap)
  ImGui.PopStyleColor(ctx)
  return visible
end
function UI.read_text(text,owner,max_width)
  local width=ImGui.GetContentRegionAvail(ctx)
  if max_width then width=math.min(width,max_width) end
  width=math.max(1,width)
  local line_h=ImGui.GetTextLineHeight(ctx)
  local cache=UI.read_cache[owner]
  if not cache or cache.text~=text or cache.width~=width or cache.line_h~=line_h then
    cache={text=text,width=width,line_h=line_h,
      lines=M.wrap_read(text,width,function(value)return ImGui.CalcTextSize(ctx,value)end)}
    UI.read_cache[owner]=cache
  end
  -- Measure the first rendered line, including native table/baseline offsets.
  local first_line_center
  -- BeginGroup keeps every wrapped line aligned after a leading checkbox.
  ImGui.BeginGroup(ctx)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,0,UI_METRICS.read_line_gap)
  for _,line in ipairs(cache.lines) do
    if line=='' then ImGui.Dummy(ctx,0,line_h) else ImGui.Text(ctx,line) end
    if not first_line_center then
      local _,line_top=ImGui.GetItemRectMin(ctx)
      first_line_center=line_top+line_h*0.5
    end
  end
  ImGui.PopStyleVar(ctx)
  ImGui.EndGroup(ctx)
  return first_line_center
end
function UI.owner_title(target)
  return api.title(target,tr)
end

-- GetColor includes style alpha (including BeginDisabled's fade).
function UI.color(key)
  local color=ImGui.GetColor(ctx,key)
  return color
end

      function UI.trigger(label, menu_id, popup_id, enabled)
        local label_w, label_h = ImGui.CalcTextSize(ctx, label)
        local trigger_pad_x = UI_METRICS.menu_trigger_pad_x
        local trigger_w = label_w + trigger_pad_x * 2
        local trigger_h = ImGui.GetFrameHeight(ctx)
        if trigger_h < 1 then trigger_h = UI_METRICS.menu_bar_height end

        local trigger_clicked = ImGui.InvisibleButton(
          ctx,
          label .. "##custom_top_menu_trigger_" .. tostring(menu_id),
          trigger_w,
          trigger_h,
          ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav
        )

        local tx1, ty1 = ImGui.GetItemRectMin(ctx)
        local tx2, ty2 = ImGui.GetItemRectMax(ctx)
        local trigger_hovered = false
        if ImGui.HoveredFlags_AllowWhenBlockedByPopup then
          trigger_hovered = ImGui.IsItemHovered(
            ctx,
            ImGui.HoveredFlags_AllowWhenBlockedByPopup
          )
        else
          trigger_hovered = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_None)
        end
        if enabled==false then
          trigger_clicked=false
          trigger_hovered=false
        end

        local dl = ImGui.GetWindowDrawList(ctx)
        local close_requested = false

        if trigger_clicked then
          if UI.menu_open == menu_id then
            close_requested = true
            UI.menu_open = nil
          else
            UI.menu_open = menu_id
            ImGui.OpenPopup(ctx, popup_id)
          end
        elseif trigger_hovered
           and UI.menu_open ~= nil
           and UI.menu_open ~= menu_id
           and not (
             UI.menu_open == "view"
             and menu_id ~= "view"
             and ImGui.IsMouseDown
             and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left)
           ) then
          UI.menu_open = menu_id
          ImGui.OpenPopup(ctx, popup_id)
        end

        local menu_open = UI.menu_open == menu_id

        if trigger_hovered or menu_open then
          local open_hover_col = UI.color(ImGui.Col_Header)
          local active_col = UI.color(ImGui.Col_HeaderActive)
          local trigger_bg = (menu_open and trigger_hovered) and active_col or open_hover_col
          ImGui.DrawList_AddRectFilled(dl, tx1, ty1, tx2, ty2, trigger_bg, 0)
        end

        ImGui.DrawList_AddText(
          dl,
          tx1 + math.max(UI_METRICS.menu_label_min_inset_x, math.floor(((tx2 - tx1) - label_w) * 0.5)),
          ty1 + math.max(UI_METRICS.menu_label_min_inset_y, math.floor(((ty2 - ty1) - label_h) * 0.5)),
          UI.color(ImGui.Col_Text),
          label
        )

        return {
          menu_id=menu_id,
          popup_id=popup_id,
          x1=tx1,
          y1=ty1,
          x2=tx2,
          y2=ty2,
          close_requested=close_requested,
        }
      end


function UI.begin_menu(key,enabled)
  if UI.menu_count>0 then ImGui.SameLine(ctx,0,0) end
  UI.menu_count=UI.menu_count+1
  ImGui.BeginDisabled(ctx,enabled==false)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,UI_METRICS.menu_bar_pad_x,math.max(0,(UI_METRICS.menu_bar_height-ImGui.GetTextLineHeight(ctx))*0.5))
  local t=UI.trigger(tr(key),key,'##top_'..key,enabled)
  ImGui.PopStyleVar(ctx)
  ImGui.EndDisabled(ctx)
  if enabled==false then return false end
  ImGui.SetNextWindowPos(ctx,t.x1,t.y2,ImGui.Cond_Always)
  ImGui.SetNextWindowSize(ctx,0,0,ImGui.Cond_Always)
  local visible=ImGui.BeginPopup(ctx,t.popup_id,ImGui.WindowFlags_NoMove)
  if visible and (t.close_requested or escape_pressed) then
    ImGui.CloseCurrentPopup(ctx);ImGui.EndPopup(ctx);UI.menu_open=nil;return false
  end
  if not visible and UI.menu_open==key and not t.close_requested then UI.menu_open=nil end
  return visible
end
function UI.message(text)
  if language~='ru' then return text end
  if RU[text] then return RU[text] end
  local count=text:match('%((%d+) selected%)')
  if count then return 'Выбери один объект для редактирования заметок (выбрано: '..count..').' end
  if text:find('Select one track',1,true) then return 'Выбери одну дорожку в REAPER, чтобы открыть её заметки.' end
  if text:find('Select one item',1,true) then return 'Выбери один айтем в REAPER, чтобы открыть его заметки.' end
  return 'Диагностика: '..text
end
function UI.open_url(url)
  if not url then return end
  if reaper.CF_ShellExecute then reaper.CF_ShellExecute(url)
  elseif reaper.ExecProcess then
    local os=reaper.GetOS()
    local mac=os:match('OSX') or os:match('macOS')
    local cmd=mac and ('open "'..url..'"') or
      (os:match('Win') and ('cmd.exe /c start "" "'..url..'"') or ('xdg-open "'..url..'"'))
    reaper.ExecProcess(cmd,0)
  end
end
function UI.show_info(kind) UI.info=kind; UI.open_info=true end
function UI.about_geometry()
  local pad_x,pad_y=UI_METRICS.about_pad_x,UI_METRICS.about_pad_y
  local texts={TITLE,tr('Version: ')..VERSION,
    tr('Notes for projects, tracks and items.'),tr('Aleksei Vorobev / Patch34'),
    'https://github.com/patch-34'}
  local content_w=UI.button_size(tr('Close'))
  for _,text in ipairs(texts) do
    local text_w=ImGui.CalcTextSize(ctx,text)
    content_w=math.max(content_w,text_w)
  end
  local host_w=ImGui.GetWindowSize(ctx)
  local width=math.min(math.max(UI_METRICS.popup_sizes.about[1],
    math.ceil(content_w+2*pad_x+UI_METRICS.about_geometry_extra)),
    math.max(1,host_w-2*UI_METRICS.popup_margin))
  local content_h=0
  for i,text in ipairs(texts) do
    local _,h=ImGui.CalcTextSize(ctx,text,nil,nil,false,
      i==3 and math.max(1,width-2*pad_x) or 0)
    content_h=content_h+h
  end
  local _,button_h=UI.button_size(tr('Close'))
  -- Four inter-line gaps plus the two explicit Spacing items in About.
  local height=math.max(UI_METRICS.popup_sizes.about[2],math.ceil(2*pad_y+content_h+6*UI_METRICS.item_gap_y+
    button_h+UI_METRICS.popup_footer_gap+UI_METRICS.about_geometry_extra))
  return width,height
end
function UI.info_window()
  if not UI.info then return end
  local kind=UI.info
  if UI.open_info then ImGui.OpenPopup(ctx,'##information');UI.open_info=nil end
  local w,h
  if kind=='about' then w,h=UI.about_geometry()
  else w,h=table.unpack(UI_METRICS.popup_sizes[kind]) end
  -- About panel colors, corner radius and inset are from Viewer render_about_overlay.
  ImGui.PushStyleColor(ctx,ImGui.Col_PopupBg,UI_PALETTE.about.background)
  ImGui.PushStyleColor(ctx,ImGui.Col_Border,UI_PALETTE.about.border)
  ImGui.PushStyleColor(ctx,ImGui.Col_Text,UI_PALETTE.about.text)
  ImGui.PushStyleColor(ctx,ImGui.Col_TextDisabled,UI_PALETTE.about.dim)
  ImGui.PushStyleColor(ctx,ImGui.Col_Button,UI_PALETTE.about.button)
  ImGui.PushStyleColor(ctx,ImGui.Col_ButtonHovered,UI_PALETTE.about.button_hover)
  ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_PopupRounding,UI_METRICS.about_rounding)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,UI_METRICS.about_pad_x,UI_METRICS.about_pad_y)
  UI.place_popup(w,h)
  local visible=ImGui.BeginPopup(ctx,'##information',ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings)
  if visible then
    if escape_pressed then
      ImGui.CloseCurrentPopup(ctx);UI.info=nil;ImGui.EndPopup(ctx)
      ImGui.PopStyleVar(ctx,2);ImGui.PopStyleColor(ctx,7);return
    end
    local body_visible=UI.popup_body('information_body',tr('Close'))
    if body_visible then
      if kind=='about' then
        ImGui.Text(ctx,TITLE)
        ImGui.TextDisabled(ctx,tr('Version: ')..VERSION)
        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx,tr('Notes for projects, tracks and items.'))
        ImGui.Text(ctx,tr('Aleksei Vorobev / Patch34'))
        ImGui.Spacing(ctx)
        if ImGui.TextLink(ctx,'https://github.com/patch-34') then
          ImGui.SetClipboardText(ctx,'https://github.com/patch-34')
          UI.open_url('https://github.com/patch-34')
        end
      end
    end
    ImGui.EndChild(ctx)
    -- Same button geometry as other dialogs, with Viewer's About-button skin.
    local close_w,close_h=UI.button_size(tr('Close'))
    local close_x,close_y=ImGui.GetCursorScreenPos(ctx)
    local available_w=ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorScreenPos(ctx,close_x+math.max(0,available_w-close_w),close_y)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameRounding,UI_METRICS.about_button_rounding)
    ImGui.PushStyleColor(ctx,ImGui.Col_Border,UI_PALETTE.about.button_border)
    if ImGui.Button(ctx,ui_label('Close'),close_w,close_h) then ImGui.CloseCurrentPopup(ctx);UI.info=nil end
    ImGui.PopStyleColor(ctx);ImGui.PopStyleVar(ctx)
    ImGui.EndPopup(ctx)
  elseif not ImGui.IsPopupOpen(ctx,'##information') then UI.info=nil end
  ImGui.PopStyleVar(ctx,2);ImGui.PopStyleColor(ctx,7)
end

local function active_tab() return session.doc.tabs[session.active] end
function UI.current_group()
  local board=active_tab()
  if not board then return nil end
  for _,column in ipairs(board.columns) do
    if column.id==session.active_group_id then return column end
  end
  for _,column in ipairs(board.columns) do if not column.folded then return column end end
  return board.columns[1]
end
local function add_block(kind,column)
  local b
  if kind=='text' then b=M.text('')
  elseif kind=='note' then b=M.note('')
  else b={id=uid(),kind='select',label=tr('Status'),options={tr('Not started'),tr('In progress'),tr('Done')},selected=1} end
  column=column or active_tab().columns[1]
  column.blocks[#column.blocks+1]=b
  session.active_group_id=column.id
  touch(nil,kind=='select' and 'add_dropdown' or 'add_note')
  column.folded=false
  bulk_selection=nil
  local board,board_index=M.note_column(session.doc,column)
  session.active=board_index
  if kind=='select' then request_modal(clone_select(b))
  else UI.activate_note(board,column,b) end
end
local function import_dialog(column)
  column=column or UI.current_group()
  session.active_group_id=column.id
  request_modal({kind='import',title='Import text',value='',strip=true,timecodes=false,preview={},column=column})
end
local function refresh_import_preview(m)
  local fps,drop_frame=project_timecode_settings()
  m.preview=M.import_text(m.value,m.strip,m.timecodes,fps,drop_frame)
end
local function add_from_menu(kind,column)
  column=column or UI.current_group()
  if not column or not M.note_column(session.doc,column) then return end
  UI.end_note_edit()
  UI.place=nil;UI.place_cancelled=true;UI.note_drag=nil;bulk_selection=nil
  if kind=='import' then import_dialog(column)
  else
    add_block(kind,column)
    column.reveal_note_id=column.blocks[#column.blocks].id
  end
end
local function add_menu(column)
  if ImGui.MenuItem(ctx,ui_label('Note with checkbox')) then add_from_menu('note',column) end
  if ImGui.MenuItem(ctx,ui_label('Import text...')) then add_from_menu('import',column) end
  if ImGui.MenuItem(ctx,ui_label('Text')) then add_from_menu('text',column) end
  if ImGui.MenuItem(ctx,ui_label('Dropdown')) then add_from_menu('select',column) end
end
local function add_column()
  if not session or not session.doc or #session.doc.tabs>=8 then return end
  local board=M.tab(tr('Tab')..' '..(#session.doc.tabs+1))
  board.columns[1].name=tr('Group')..' 1'
  session.doc.tabs[#session.doc.tabs+1]=board;session.active=#session.doc.tabs
  touch(nil,'add_column');undo_boundary=true
end
-- Placement is owner/generation scoped. Only a completed target click or native
-- payload delivery queues creation, and every destination is revalidated then.
function UI.place_valid(p)
  return p and p.owner==session and p.epoch==epoch and session and p.doc==session.doc
    and not session.error and not session.conflict and not modal and not UI.info
    and not history_request and startup_layout_frames>=STARTUP_LAYOUT_FRAMES
end
function UI.place_begin(kind,mode)
  if not session or not session.doc then return end
  UI.end_note_edit();bulk_selection=nil;UI.note_drag=nil
  UI.place_sequence=(UI.place_sequence or 0)+1
  UI.place={owner=session,doc=session.doc,epoch=epoch,kind=kind,mode=mode,
    token=tostring(epoch)..':'..UI.place_sequence}
end
function UI.place_update()
  if not ImGui.IsMouseDown(ctx,0) and not ImGui.IsMouseReleased(ctx,0) then UI.place_cancelled=nil end
  local p=UI.place
  if not p then return end
  local invalid=not UI.place_valid(p) or escape_pressed
  if p.mode=='drag' and not invalid then
    -- GetDragDropPayload can temporarily be empty at the start of a frame,
    -- before creation_toolbar has registered its source again. Do not revoke
    -- the drag on that transient gap. Keep it through the release frame,
    -- so native AcceptDragDropPayload can still report delivery.
    invalid=not ImGui.IsMouseDown(ctx,0) and not ImGui.IsMouseReleased(ctx,0)
  end
  if invalid then UI.place=nil;UI.place_cancelled=true end
end
function UI.place_commit(p,section)
  if session.pending or not UI.place_valid(p) or UI.place~=p then return end
  local board,board_index=M.note_column(session.doc,section)
  if not board then return end
  session.pending=function()
    if UI.place==p and UI.place_valid(p) and api.valid(session.target) then
      local current,index=M.note_column(session.doc,section)
      if current==board then
        UI.place=nil;UI.place_cancelled=true;session.active=index
        board.folded=false;section.folded=false
        if p.kind=='import' then import_dialog(section) else add_block(p.kind,section) end
      end
    end
    if UI.place==p then UI.place=nil end
  end
end
-- Keep the delete target stationary near the top-left of the document while
-- a note is being dragged. No explicit drop preview item is inserted into a
-- section; the target is a normal native widget in the fixed toolbar.
function UI.drag_trash_target()
  local drag=UI.note_drag_current()
  if not drag or UI.place then return nil end
  local height=math.max(1,UI_METRICS.button_min_height)
  local side=math.max(0,math.min(UI_METRICS.trash_icon_size,height-UI_METRICS.trash_icon_vertical_inset))
  local label_x=math.max(UI_METRICS.trash_label_offset_x,
    UI_METRICS.trash_icon_offset_x+side+UI_METRICS.trash_icon_label_gap)
  local width=UI_METRICS.trash_icon_only and height or math.max(1,UI_METRICS.trash_target_width)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  UI.source_button('trash_drop','',width,height)
  local hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
  local color=hovered and UI_PALETTE.trash.text_hover or UI_PALETTE.trash.text
  local fill=hovered and UI_PALETTE.trash.fill_hover or UI_PALETTE.trash.fill
  local dl=ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl,sx,sy,sx+width,sy+height,ImGui.GetColorEx(ctx,fill),UI_METRICS.button_rounding)
  ImGui.DrawList_AddRect(dl,sx,sy,sx+width,sy+height,ImGui.GetColorEx(ctx,color),
    UI_METRICS.button_rounding,ImGui.DrawFlags_None,hovered and UI_METRICS.trash_hover_border_size or UI_METRICS.trash_border_size)
  local icon=UI.icon_image('trash')
  -- GetColorEx is evaluated separately: a function call in the final Lua
  -- argument position may expand to multiple return values. ReaImGui's
  -- DrawList_AddImage accepts at most 11 arguments (including draw list).
  local icon_tint=ImGui.GetColorEx(ctx,color)
  local icon_x=UI_METRICS.trash_icon_only and (sx+(width-side)*0.5) or (sx+UI_METRICS.trash_icon_offset_x)
  ImGui.DrawList_AddImage(dl,icon,icon_x,sy+(height-side)*0.5,
    icon_x+side,sy+(height+side)*0.5,0,0,1,1,icon_tint)
  if not UI_METRICS.trash_icon_only then
    ImGui.DrawList_AddText(dl,sx+label_x,sy+(height-ImGui.GetTextLineHeight(ctx))*0.5,
      ImGui.GetColorEx(ctx,color),tr('Drop to delete'))
  end
  ImGui.SetItemTooltip(ctx,tr('Delete note by dropping here'))
  if ImGui.BeginDragDropTarget(ctx) then
    local flags=ImGui.DragDropFlags_AcceptBeforeDelivery|ImGui.DragDropFlags_AcceptNoDrawDefaultRect
    local accepted,token=ImGui.AcceptDragDropPayload(ctx,'P34_NOTE',nil,flags)
    local active,kind,payload,preview,delivery=ImGui.GetDragDropPayload(ctx)
    if accepted and active and kind=='P34_NOTE' and token==drag.token and payload==drag.token and delivery then
      UI.note_delete_drop(drag)
    end
    ImGui.EndDragDropTarget(ctx)
  end
  return width
end
function UI.creation_toolbar()
  -- Recomputed each frame. The last icon supplies the exact native screen edge
  -- for controls in child windows with different padding and layout origins.
  UI.shared_actions_right=nil
  local enabled=session and session.doc and not session.error and not session.conflict
    and not modal and not UI.info and not history_request
  local dragging=UI.note_drag_current()~=nil
  local side=UI_METRICS.button_min_height
  local gap=UI_METRICS.item_gap_x
  local row={width=math.max(1,ImGui.GetContentRegionAvail(ctx)-UI_METRICS.creation_toolbar_right_inset),used=0}
  -- The trash slot is always reserved. It is only painted during native DnD,
  -- so the other toolbar buttons don't jump sideways on drag start.
  UI.toolbar_right(row,6*side+5*gap)
  local toolbar_x,toolbar_y=ImGui.GetCursorScreenPos(ctx)
  if dragging then UI.drag_trash_target() else ImGui.Dummy(ctx,side,side) end
  ImGui.SameLine(ctx,0,gap)
  if not dragging and enabled then
    if UI.quick_access_button('create_group','New group','pencil',side,false,'New group') then
      local board=active_tab()
      if board then UI.add_section(board,board.columns[#board.columns]) end
    end
  else
    ImGui.BeginDisabled(ctx,true)
    UI.quick_access_button('create_group','New group','pencil',side,false,'New group')
    ImGui.EndDisabled(ctx)
  end
  ImGui.BeginDisabled(ctx,not enabled or dragging)
  for _,action in ipairs({{'text','Text'},{'note','Note with checkbox'},
      {'select','Dropdown'},{'import','Import text...'}}) do
    ImGui.SameLine(ctx,0,gap)
    local p=UI.place
    local clicked=UI.quick_access_button('create_'..action[1],action[2],action[1],side,
      p and p.kind==action[1],'Drag or click an icon, then choose a group.')
    -- Read the actual rectangle immediately: dragging tooltips/popups may
    -- change the ImGui last-item record later in this loop iteration.
    if action[1]=='import' then
      local item_right=ImGui.GetItemRectMax(ctx)
      UI.shared_actions_right=item_right
    end
    if not UI.place_cancelled and enabled and not escape_pressed
        and startup_layout_frames>=STARTUP_LAYOUT_FRAMES and not dragging
        and ImGui.BeginDragDropSource(ctx,0) then
      if not p or p.mode~='drag' or p.kind~=action[1] then UI.place_begin(action[1],'drag');p=UI.place end
      ImGui.SetDragDropPayload(ctx,'P34_NEW',p.token,ImGui.Cond_Once)
      ImGui.Text(ctx,tr(action[2]));ImGui.EndDragDropSource(ctx)
    elseif clicked and not (p and p.mode=='drag') then
      if p and p.kind==action[1] then UI.place=nil else UI.place_begin(action[1],'click') end
    end
  end
  ImGui.EndDisabled(ctx)
  if UI.place then
    local hint=tr('Choose a group. Esc cancels.')
    ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
    local hint_w,hint_h=ImGui.CalcTextSize(ctx,hint)
    ImGui.PopFont(ctx)
    local hint_x=toolbar_x-UI_METRICS.group_gap-hint_w
    local wx=ImGui.GetWindowPos(ctx)
    if hint_x>=wx+UI_METRICS.window_pad_x then
      ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),hint_x,
        toolbar_y+(side-hint_h)*0.5,
        ImGui.GetColor(ctx,ImGui.Col_TextDisabled),hint)
    end
  end
end
-- Draw-only section highlighting: a whole tab is one recognizable target.
-- Neither a separate drop strip nor a large layout Dummy is needed.
function UI.draw_dashed_rect(list,x1,y1,x2,y2,color,dash,gap,thickness)
  dash=math.max(1,dash or UI_METRICS.drag_note_highlight_dash);gap=math.max(1,gap or UI_METRICS.drag_note_highlight_gap);thickness=thickness or UI_METRICS.drag_note_highlight_border_thickness
  local step=dash+gap
  local x=x1
  while x<x2 do
    local xe=math.min(x+dash,x2)
    ImGui.DrawList_AddLine(list,x,y1,xe,y1,color,thickness)
    ImGui.DrawList_AddLine(list,x,y2,xe,y2,color,thickness)
    x=x+step
  end
  local y=y1
  while y<y2 do
    local ye=math.min(y+dash,y2)
    ImGui.DrawList_AddLine(list,x1,y,x1,ye,color,thickness)
    ImGui.DrawList_AddLine(list,x2,y,x2,ye,color,thickness)
    y=y+step
  end
end
local function placement_alpha(color,multiplier)
  return (color&0xffffff00)|math.max(0,math.min(255,math.floor((color&0xff)*multiplier+0.5)))
end
-- The same renderer serves both the source note and placement bodies. Native
-- draw-list clipping trims off-screen edges without inventing a new border
-- at the viewport edge. No items or hitboxes are submitted here.
function UI.note_highlight(sx,sy,width,bottom)
  local m=UI_METRICS
  if width<=0 or bottom<=sy then return end
  local x1,x2=sx-m.drag_note_highlight_padding_x,sx+width+m.drag_note_highlight_padding_x
  local y1,y2=sy-m.drag_note_highlight_padding_y,bottom+m.drag_note_highlight_padding_y
  if x2<=x1 or y2<=y1 then return end
  local accent=ImGui.GetColor(ctx,ImGui.Col_CheckMark)
  local fill=placement_alpha(accent,UI_PALETTE.drag_note_highlight_fill_alpha)
  local edge=(accent & 0xffffff00)|UI_PALETTE.drag_note_highlight_edge_alpha
  local list=ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(list,x1,y1,x2,y2,fill,m.drag_note_highlight_rounding)
  UI.draw_dashed_rect(list,x1,y1,x2,y2,edge,m.drag_note_highlight_dash,m.drag_note_highlight_gap,
    m.drag_note_highlight_border_thickness)
end
function UI.placement_target(section,sx,sy,width,bottom,role,activated,visual)
  local p=UI.place
  if not UI.place_valid(p) then return end
  -- EndGroup() has just submitted the whole section as a real native item.
  -- Do not SetCursorScreenPos() over it: overlay items corrupt group/window
  -- extents during drag or scrolling (Dear ImGui 1.92+ asserts on this).
  local hovered=ImGui.IsItemHovered(ctx,
    ImGui.HoveredFlags_AllowWhenBlockedByActiveItem|ImGui.HoveredFlags_AllowWhenDisabled)
  if role~='restore' then
    local mx,my=ImGui.GetMousePos(ctx)
    local wx,wy=ImGui.GetWindowPos(ctx)
    local ww,wh=ImGui.GetWindowSize(ctx)
    -- A section may extend above/below the scrolling child viewport.
    -- Restrict hover and click to what is physically visible.
    hovered=mx>=sx and mx<sx+width and my>=sy and my<bottom
      and mx>=wx and mx<wx+ww and my>=wy and my<wy+wh
    if visual then UI.note_highlight(visual.x,visual.y,visual.width,visual.bottom) end
    if hovered then ImGui.SetItemTooltip(ctx,tr('Click or drop into this tab to add here.')) end
  end
  if p.mode=='click' then
    if (role=='restore' and activated or role~='restore' and hovered and ImGui.IsMouseReleased(ctx,0)) then
      UI.place_commit(p,section)
    end
  elseif ImGui.BeginDragDropTarget(ctx) then
    local flags=ImGui.DragDropFlags_AcceptBeforeDelivery|ImGui.DragDropFlags_AcceptNoDrawDefaultRect
    local accepted,token=ImGui.AcceptDragDropPayload(ctx,'P34_NEW',nil,flags)
    local active,kind,payload,_,delivery=ImGui.GetDragDropPayload(ctx)
    if accepted and active and kind=='P34_NEW' and token==p.token
        and payload==p.token and delivery then
      UI.place_commit(p,section)
    end
    ImGui.EndDragDropTarget(ctx)
  end
  UI.section_hover(section,hovered)
end
function UI.section_hover(section,hovered)
  local drag=(UI.place and UI.place.mode=='drag') and UI.place or UI.note_drag_current()
  if not drag then return end
  if hovered and section.folded then
    local now=reaper.time_precise()
    if drag.hover_section~=section then drag.hover_section=section;drag.hover_since=now end
    if now-drag.hover_since>=0.45 then section.folded=false end
  elseif drag.hover_section==section then drag.hover_section=nil;drag.hover_since=nil end
end

local function can_history(direction)
  if not session or (not session.doc and not session.history_readonly)
      or (session.error and not (session.history_readonly and not session.doc)) or session.conflict or modal or UI.info then return false end
  return #(direction<0 and session.history.undo or session.history.redo)>0
end
local function history_shortcuts()
  if not session or modal or UI.info or UI.note_edit or (session.error and not (session.history_readonly and not session.doc)) or session.conflict then return end
  if not ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_RootAndChildWindows) then return end
  -- NoUndoRedo on document inputs prevents both histories firing for one chord.
  -- Mod_Ctrl maps to Cmd under ReaImGui's native macOS behavior.
  if ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Key_Z) and can_history(-1) then history_request=-1
  elseif (ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Mod_Shift|ImGui.Key_Z)
      or ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Key_Y)) and can_history(1) then history_request=1 end
end
local HISTORY_ACTIONS = {
  color_marker={'color marker','цветовую метку'},delete_selected={'delete selected elements','удаление выделенных элементов'},
  group_color={'group header color','цвет заголовка группы'},delete_group={'delete group','удаление группы'},
  add_group={'add group','добавление группы'},move_group={'move group','перемещение группы'},
  rename_group={'rename group','переименование группы'},

  change={'change','изменение'},typing={'typing','ввод текста'},deletion={'text deletion','удаление текста'},
  paste={'paste','вставку текста'},cut={'cut','вырезание текста'},replace={'text replacement','замену текста'},
  line_break={'line break','перевод строки'},edit_note={'note edit','изменение заметки'},checkbox={'checkbox change','отметку'},
  choose_option={'option selection','выбор значения'},edit_dropdown={'dropdown edit','изменение списка'},
  add_note={'add note','добавление заметки'},add_checkbox={'add checkbox','добавление чекбокса'},
  remove_checkbox={'remove checkbox','удаление чекбокса'},delete_item={'delete note','удаление заметки'},
  delete_note={'delete note','удаление заметки'},move_note={'move note','перемещение заметки'},
  add_dropdown={'add dropdown','добавление списка'},add_tab={'add tab','добавление вкладки'},
  delete_tab={'delete tab','удаление вкладки'},rename_tab={'rename tab','переименование вкладки'},move_tab={'move tab','перемещение вкладки'},
  add_column={'add column','добавление колонки'},delete_column={'delete column','удаление колонки'},
  rename_column={'rename column','переименование колонки'},move_column={'move column','перемещение колонки'},
  import={'import','импорт'},restore={'recovery restore','восстановление'},
}
function UI.history_caption(direction)
  local base=direction<0 and 'Undo' or 'Redo'
  local stack=session and session.history and (direction<0 and session.history.undo or session.history.redo)
  local entry=stack and stack[#stack]
  local action=entry and (HISTORY_ACTIONS[entry.action] or HISTORY_ACTIONS.change)
  return tr(base)..(action and ' '..action[language=='ru' and 2 or 1] or '')
end
function UI.history_item(direction,label_width)
  local base=direction<0 and 'Undo' or 'Redo'
  local caption=UI.history_caption(direction)
  local os_name=reaper.GetOS()
  local mac=os_name:match('OSX') or os_name:match('macOS')
  local shortcut=mac and (direction<0 and '⌘Z' or '⇧⌘Z') or (direction<0 and 'Ctrl+Z' or 'Ctrl+Shift+Z')
  local space=math.max(1,(ImGui.CalcTextSize(ctx,' ')))
  local padding=math.max(UI_METRICS.history_shortcut_min_spaces,math.ceil((label_width-ImGui.CalcTextSize(ctx,caption)+UI_METRICS.history_shortcut_gap)/space))
  -- Keep the shortcut beside these rows: long unrelated menu labels must not
  -- force ImGui's shared shortcut column farther to the right.
  return ImGui.MenuItem(ctx,caption..string.rep(' ',padding)..shortcut..'###'..base,nil,false,can_history(direction))
end
local function menu_bar()
  UI.menu_count=0
  if not ImGui.BeginMenuBar(ctx) then return end
  local enabled=session~=nil and session.doc~=nil and session.error==nil and session.conflict==nil
  if UI.begin_menu('Edit') then
    if ImGui.MenuItem(ctx,ui_label('Import text...'),nil,false,enabled) then add_from_menu('import') end
    if ImGui.MenuItem(ctx,ui_label('Open recovery copy...'),nil,false,session~=nil and not session.conflict and not session.dirty) then
      local selected,path=reaper.GetUserFileNameForRead(recovery_root()..'/',tr('Open recovery copy...'),'notes')
      if selected then
        local data,err=M.read_recovery_file(path)
        if data then
          request_modal({kind='restore',title='Restore recovery copy',document=data.document,raw=data.raw,path=path})
        else reaper.MB(tr('Could not open recovery copy: ')..tr(err),TITLE,0) end
      end
    end
    ImGui.Separator(ctx)
    local history_width=math.max(ImGui.CalcTextSize(ctx,UI.history_caption(-1)),(ImGui.CalcTextSize(ctx,UI.history_caption(1))))
    if UI.history_item(-1,history_width) then history_request=-1 end
    if UI.history_item(1,history_width) then history_request=1 end
    ImGui.EndPopup(ctx)
  end
  if UI.begin_menu('Tabs',enabled) then
    if ImGui.MenuItem(ctx,ui_label('New tab'),nil,false,#session.doc.tabs<8) then add_column() end
    ImGui.Separator(ctx)
    for index,board in ipairs(session.doc.tabs) do
      if ImGui.BeginMenu(ctx,label(board.name)..'##board_menu_'..board.id) then
        if ImGui.MenuItem(ctx,ui_label('Switch to tab')) then session.active=index end
        UI.board_actions(board,index);ImGui.EndMenu(ctx)
      end
    end
    ImGui.EndPopup(ctx)
  end
  if UI.begin_menu('Add',enabled) then
    add_menu()
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx,ui_label('New group')) then
      local board=active_tab()
      UI.add_section(board,board.columns[#board.columns])
    end
    if ImGui.MenuItem(ctx,ui_label('New tab'),nil,false,#session.doc.tabs<8) then add_column() end
    ImGui.EndPopup(ctx)
  end
  if UI.begin_menu('View') then
    if ImGui.MenuItem(ctx,ui_label('Hide completed'),nil,hide_completed) then
      hide_completed=not hide_completed;pref('hide_completed',hide_completed and '1' or '0')
    end
    if ImGui.MenuItem(ctx,ui_label('Completed notes last'),nil,completed_last) then
      completed_last=not completed_last;pref('completed_last',completed_last and '1' or '0')
    end
    if ImGui.BeginMenu(ctx,ui_label('Color marker style')) then
      for _,option in ipairs({{'strip','Left strip'},{'fill','Whole note'}}) do
        if ImGui.MenuItem(ctx,ui_label(option[2]),nil,marker_style==option[1]) then
          marker_style=option[1];pref('marker_style',marker_style)
        end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx,ui_label('Note spacing')) then
      ImGui.TextDisabled(ctx,tr('Gap above and below the separator'))
      ImGui.SetNextItemWidth(ctx,UI_METRICS.slider_width)
      local moved,value=ImGui.SliderInt(ctx,'##note_spacing',note_spacing,
        UI_METRICS.note_spacing_min,UI_METRICS.note_spacing_max,'%d px')
      if moved then note_spacing=value;pref('note_spacing',note_spacing) end
      if ImGui.MenuItem(ctx,ui_label('Reset spacing')) then
        note_spacing=UI_METRICS.note_spacing_default;pref('note_spacing',note_spacing)
      end
      ImGui.EndMenu(ctx)
    end
    ImGui.Separator(ctx)
    for _,key in ipairs({'paper','grey','white','dark'}) do
      if ImGui.MenuItem(ctx,tr(themes[key].name)..'###theme_'..key,nil,theme==key) then pending_theme=key end
    end
    ImGui.Separator(ctx)
    if ImGui.BeginMenu(ctx,ui_label('Language')) then
      if ImGui.MenuItem(ctx,'English',nil,language=='en') then pending_language='en' end
      if ImGui.MenuItem(ctx,'Русский',nil,language=='ru') then pending_language='ru' end
      ImGui.EndMenu(ctx)
    end
    ImGui.EndPopup(ctx)
  end
  if UI.begin_menu('Help') then
    local help_caption=REPOSITORY_URL and 'Help...' or 'Repository not created yet'
    if ImGui.MenuItem(ctx,ui_label(help_caption),nil,false,REPOSITORY_URL~=nil) then UI.open_url(UI.help_url()) end
    if ImGui.MenuItem(ctx,ui_label('About...')) then UI.show_info('about') end
    ImGui.EndPopup(ctx)
  end
  ImGui.EndMenuBar(ctx)
end
UI.marker_palette=MARKER_PALETTE -- compatibility alias; edit the palette in UI SETTINGS
function UI.marker_color(key)
  local palette=UI.marker_palette[theme=='dark' and 'dark' or 'light']
  local color=ImGui.GetColorEx(ctx,palette[key])
  return color
end
function UI.marker_tint(base,key,override_amount)
  if key==nil then return base end
  local palette=UI.marker_palette[theme=='dark' and 'dark' or 'light']
  local tint=palette[key]
  local amount=override_amount or (theme=='dark' and UI_PALETTE.marker_tint_dark or UI_PALETTE.marker_tint_light)
  local color=base&0xff
  for _,shift in ipairs({24,16,8}) do
    local channel=math.floor(((base>>shift)&0xff)*(1-amount)+((tint>>shift)&0xff)*amount+0.5)
    color=color|(channel<<shift)
  end
  return color
end
-- A splitter belongs to one window draw list. Column keys are weak so a
-- suspended document cannot keep its old render resources alive.
UI.marker_layers=setmetatable({},{__mode='k'})
UI.placement_layers=setmetatable({},{__mode='k'})
function UI.marker_layer(column,layers)
  layers=layers or UI.marker_layers
  local draw_list=ImGui.GetWindowDrawList(ctx)
  local layer=layers[column]
  if not layer or layer.draw_list~=draw_list or not ImGui.ValidatePtr(layer.splitter,'ImGui_DrawListSplitter*') then
    layer={draw_list=draw_list,splitter=ImGui.CreateDrawListSplitter(draw_list)}
    layers[column]=layer
  end
  return layer
end
local function marker_menu(current,apply,none_caption,id_prefix)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,UI_METRICS.item_gap_x,UI_METRICS.item_gap_y)
  if ImGui.MenuItem(ctx,ui_label(none_caption or 'No marker'),nil,current==nil) then apply(nil) end
  ImGui.Separator(ctx)
  local space_width=math.max(1,(ImGui.CalcTextSize(ctx,' ')))
  local inset=UI_METRICS.marker_menu_offset_x+UI_METRICS.marker_menu_side+UI_METRICS.marker_menu_text_gap
  local spaces=math.max(UI_METRICS.marker_menu_label_spaces,math.ceil(inset/space_width))
  for _,key in ipairs(M.marker_keys) do
    local name=key:sub(1,1):upper()..key:sub(2)
    local clicked=ImGui.MenuItem(ctx,string.rep(' ',spaces)..tr(name)..'###'..(id_prefix or 'marker_')..key,nil,current==key)
    local x,y=ImGui.GetItemRectMin(ctx)
    local _,bottom=ImGui.GetItemRectMax(ctx)
    local center=(y+bottom)*0.5
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),x+UI_METRICS.marker_menu_offset_x,center-UI_METRICS.marker_menu_side*0.5,
      x+UI_METRICS.marker_menu_offset_x+UI_METRICS.marker_menu_side,center+UI_METRICS.marker_menu_side*0.5,
      UI.marker_color(key),UI_METRICS.marker_menu_rounding)
    if clicked then apply(key) end
  end
  ImGui.PopStyleVar(ctx);ImGui.PopFont(ctx)
end
local function start_selection(tab,column)
  UI.end_note_edit()
  session.active_group_id=column.id
  session.history.key=nil;session.input_state=nil
  bulk_selection={owner=session,tab_id=tab.id,column=column,selected={}}
end
local function selection_toolbar(column,actions_right)
  local current=bulk_selection
  local count,total=M.selection_prune(column,current.selected,hide_completed)
  ImGui.TextWrapped(ctx,column.name..' — '..tr('Selected: %d'):format(count))
  local sx=ImGui.GetCursorScreenPos(ctx)
  local width=math.max(1,math.min(ImGui.GetContentRegionAvail(ctx),actions_right-sx))
  local row={width=width,used=0}
  local function button(caption,enabled,icon)
    local w,h=UI.button_size(tr(caption))
    local compact=w>row.width
    UI.quick_access_next(row,compact and h or w)
    ImGui.BeginDisabled(ctx,enabled==false)
    local clicked
    if compact then clicked=UI.quick_access_button('selection_'..icon,caption,icon,h)
    else clicked=UI.button(ctx,ui_label(caption),false) end
    ImGui.EndDisabled(ctx)
    return clicked
  end
  if button(count==total and total>0 and 'Clear selection' or 'All',total>0,'note') then
    M.selection_all(column,current.selected,hide_completed,count~=total)
  end
  count=M.selection_prune(column,current.selected,hide_completed)
  if button('Color...',count>0,'palette') then ImGui.OpenPopup(ctx,'selection_color') end
  if begin_action_popup('selection_color') then
    local first,common,has=false,nil,false
    for _,b in ipairs(column.blocks) do
      if current.selected[b.id] then
        if not has then first=b.color;common=b.color;has=true
        elseif b.color~=first then common=false end
      end
    end
    marker_menu(common,function(key)
      if M.selection_color(column,current.selected,hide_completed,key)>0 then
        touch(nil,'color_marker');undo_boundary=true
      end
    end)
    ImGui.EndPopup(ctx)
  end
  if button('Delete...',count>0,'trash') then
    local chosen={}
    for id in pairs(current.selected) do chosen[id]=true end
    request_modal({kind='delete',title='Delete selected elements?',
      message=tr('Delete %d selected elements?'):format(count),history_action='delete_selected',
      action=function()
        if M.selection_delete(column,chosen,false)>0 then touch(nil,'delete_selected');undo_boundary=true end
        bulk_selection=nil
      end})
  end
  if button('Done',true,'close') then bulk_selection=nil end
  if escape_pressed and not modal then bulk_selection=nil end
  -- Match both ends of the note separators using the same group indent.
  ImGui.Indent(ctx,UI_METRICS.inner_gap+UI_METRICS.note_row_inset_x)
  UI.note_separator(actions_right)
  ImGui.Unindent(ctx,UI_METRICS.inner_gap+UI_METRICS.note_row_inset_x)
end
local function block_actions(tab,column,index)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  if begin_action_popup('block_actions') then
    local up=M.block_neighbor(column,index,-1,hide_completed,completed_last)
    local down=M.block_neighbor(column,index,1,hide_completed,completed_last)
    if ImGui.MenuItem(ctx,ui_label('Move up'),nil,false,up~=nil) then session.pending=function() M.move_to(column.blocks,index,up); touch(nil,'move_note') end end
    if ImGui.MenuItem(ctx,ui_label('Move down'),nil,false,down~=nil) then session.pending=function() M.move_to(column.blocks,index,down); touch(nil,'move_note') end end
    if ImGui.BeginMenu(ctx,ui_label('Move to group'),#tab.columns>1) then
      for _,target in ipairs(tab.columns) do
        if target~=column and ImGui.MenuItem(ctx,label(target.name)..'##'..target.id) then
          session.pending=function()
            target.blocks[#target.blocks+1]=table.remove(column.blocks,index); touch(nil,'move_note')
          end
        end
      end
      ImGui.EndMenu(ctx)
    end
    local block=column.blocks[index]
    if block.kind=='text' and ImGui.MenuItem(ctx,ui_label('Add checkbox')) then
      if M.set_note_checkbox(block,true) then touch(nil,'add_checkbox');undo_boundary=true end
    elseif block.kind=='note' and ImGui.MenuItem(ctx,ui_label('Remove checkbox')) then
      if M.set_note_checkbox(block,false) then touch(nil,'remove_checkbox');undo_boundary=true end
    end
    if ImGui.BeginMenu(ctx,ui_label('Color marker')) then
      marker_menu(block.color,function(key)
        if M.selection_color(column,{[block.id]=true},false,key)>0 then touch(nil,'color_marker');undo_boundary=true end
      end)
      ImGui.EndMenu(ctx)
    end
    if column.blocks[index].kind=='select' and ImGui.MenuItem(ctx,ui_label('Edit field...')) then request_modal(clone_select(column.blocks[index])) end
    if ImGui.MenuItem(ctx,ui_label('Delete...')) then confirm_delete(function() table.remove(column.blocks,index); touch() end) end
    ImGui.EndPopup(ctx)
  end
  ImGui.PopFont(ctx)
end
-- An action hitbox is submitted in the note table with a stable native ID.
-- Its dots are painted after the complete note geometry is measured, using
-- the same painter and tokens as the group menu. No previous-frame rect cache.
function UI.block_action_button()
  local width,height=UI.button_size('...')
  local x,y=ImGui.GetCursorScreenPos(ctx)
  local clicked=ImGui.InvisibleButton(ctx,'##note_action_dots',width,height,
    ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav)
  local focused=ImGui.IsItemFocused(ctx)
  return {clicked=clicked,focused=focused,x=x,y=y,width=width,height=height}
end
-- Shared note shell. All note kinds stay in the calling page_body window;
-- these non-scrolling tables only allocate cells, never child windows.
-- The optional editor child and native combo popup are leaf input surfaces.
function UI.note_layout(block,width)
  local m=UI_METRICS
  local text_h=ImGui.GetTextLineHeight(ctx)
  ImGui.PushFont(ctx,ui_font,m.font_size)
  local checkbox_h=ImGui.GetTextLineHeight(ctx)+2*m.checkbox_pad_y
  ImGui.PopFont(ctx)
  local action_w,action_h=UI.button_size('...')
  local edit_w,edit_h=UI.button_size(tr('Edit...'),true)
  local checked=block.kind=='note' or block.kind=='check'
  local row=M.note_row_layout(text_h,checkbox_h,checked,m,
    math.max(checkbox_h,action_h,edit_h))
  row.has_checkbox=checked
  row.checkbox_width=checkbox_h+m.note_checkbox_text_gap
  -- Keep two standard gaps in the action column to separate the editable
  -- content from the menu hitbox. Both group and note buttons are ultimately
  -- anchored to the same absolute right edge, not to native table cell padding.
  row.action_width=action_w+2*m.item_gap_x;row.action_button_width=action_w
  row.action_height=action_h
  row.wide=width>=row.action_width+m.note_actions_min_content_width
  row.has_accessory=block.kind=='select' and UI.note_editing(block) and row.wide
    and width>=row.action_width+edit_w+2*m.item_gap_x+m.note_actions_min_content_width
  row.accessory_width=edit_w;row.accessory_height=edit_h
  row.width=width
  row.origin_x,row.origin_y=ImGui.GetCursorScreenPos(ctx)
  row.actions_right=row.origin_x+width
  return row
end
function UI.note_text_body(tab,column,b,row)
  if b.kind~='select' and UI.note_editing(b) then
    local edit=UI.note_edit
    local _,n=edit.value:gsub('\n','\n')
    local h=math.max(UI_METRICS.note_edit_min_height,math.min(UI_METRICS.note_edit_max_height,
      (n+UI_METRICS.note_edit_extra_lines)*ImGui.GetTextLineHeight(ctx)+UI_METRICS.note_edit_extra_height))
    -- This child is an input widget only. Row anchors remain in page_body.
    UI.wrapped_editor(edit,h,'##note_wrapped',true)
    if edit.commit_requested then UI.end_edit_after_frame=edit end
    return row.top+row.center
  end
  local text=(b.kind=='select' or b.kind=='check') and b.label or b.text
  local center=UI.read_text(text~='' and text or tr('(Empty text block)'),b)
  UI.note_text_click(tab,column,b,ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem))
  return center or (row.top+row.center)
end
function UI.note_heading(tab,column,b,row)
  row.content_x,row.content_y=ImGui.GetCursorScreenPos(ctx)
  local columns=1+(row.has_checkbox and 1 or 0)+(row.has_accessory and 1 or 0)
  if not ImGui.BeginTable(ctx,'note_heading',columns,
      ImGui.TableFlags_SizingFixedFit|ImGui.TableFlags_NoSavedSettings) then return end
  if row.has_checkbox then
    ImGui.TableSetupColumn(ctx,'Check',ImGui.TableColumnFlags_WidthFixed,row.checkbox_width)
  end
  ImGui.TableSetupColumn(ctx,'Text',ImGui.TableColumnFlags_WidthStretch,1)
  if row.has_accessory then
    ImGui.TableSetupColumn(ctx,'Accessory',ImGui.TableColumnFlags_WidthFixed,
      row.accessory_width+UI_METRICS.item_gap_x)
  end
  ImGui.TableNextRow(ctx,0,row.height)
  -- Submit text first for every kind; native checkbox padding cannot become
  -- the baseline of a following text cell. The leading slot is optional.
  local text_column=row.has_checkbox and 1 or 0
  ImGui.TableSetColumnIndex(ctx,text_column)
  local x,y=ImGui.GetCursorScreenPos(ctx)
  row.text_x=x;row.top=y
  ImGui.SetCursorScreenPos(ctx,x,y+row.text_y)
  local center=UI.note_text_body(tab,column,b,row)
  row.first_line_center=center
  if row.has_checkbox then
    ImGui.TableSetColumnIndex(ctx,0)
    -- Actual first-line position is the common anchor for all accessories.
    local check_row={top=center-row.center,checkbox_y=row.checkbox_y}
    local changed,value=UI.note_checkbox(b.checked,check_row)
    if changed then b.checked=value;touch(nil,'checkbox');undo_boundary=true end
  end
  if row.has_accessory and UI.note_editing(b) then
    ImGui.TableSetColumnIndex(ctx,text_column+1)
    local ax=ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx,ax+UI_METRICS.item_gap_x,center-row.accessory_height*0.5)
    if UI.button(ctx,ui_label('Edit...'),true) then request_modal(clone_select(b)) end
  end
  ImGui.EndTable(ctx)
  return center
end
function UI.note_value_body(b)
  local combo_width=math.max(1,math.min(UI_METRICS.dropdown_width,ImGui.GetContentRegionAvail(ctx)))
  ImGui.SetNextItemWidth(ctx,combo_width)
  ImGui.SetNextWindowSizeConstraints(ctx,combo_width,0,combo_width,
    math.min(UI_METRICS.dropdown_visible_rows,#b.options)*ImGui.GetTextLineHeightWithSpacing(ctx)+UI_METRICS.dropdown_popup_extra_height)
  if ImGui.BeginCombo(ctx,'##value',b.options[b.selected]) then
    if escape_pressed then ImGui.CloseCurrentPopup(ctx)
    else
      for i,option in ipairs(b.options) do
        ImGui.PushID(ctx,i)
        if ImGui.Selectable(ctx,label(option)..'##option',i==b.selected) then
          b.selected=i;touch(nil,'choose_option');undo_boundary=true
        end
        if i==b.selected then ImGui.SetItemDefaultFocus(ctx) end
        ImGui.PopID(ctx)
      end
    end
    ImGui.EndCombo(ctx)
  end
end
local function draw_block(tab,column,b,index,actions_right)
  local anchor_hovered,has_timecode=UI.timecode_badge(b)
  if has_timecode then UI.seek_note(b,anchor_hovered) end
  local x,y=ImGui.GetCursorScreenPos(ctx)
  local width=math.max(1,math.min(ImGui.GetContentRegionAvail(ctx),actions_right-x))
  local row=UI.note_layout(b,width)
  local action_hit,first_line_center=nil,nil
  -- Every note owns this same padding/spacing contract. No kind inherits
  -- native table CellPadding, and no hidden button determines heading height.
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_CellPadding,0,0)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,UI_METRICS.item_gap_x,0)
  local table_open=row.wide and ImGui.BeginTable(ctx,'block',2,
    ImGui.TableFlags_SizingStretchProp|ImGui.TableFlags_NoSavedSettings,width)
  if not row.wide or table_open then
    if table_open then
      ImGui.TableSetupColumn(ctx,'Content',ImGui.TableColumnFlags_WidthStretch,1)
      ImGui.TableSetupColumn(ctx,'Actions',ImGui.TableColumnFlags_WidthFixed,row.action_width)
      ImGui.TableNextRow(ctx,0,row.height);ImGui.TableNextColumn(ctx)
    end
    first_line_center=UI.note_heading(tab,column,b,row)
    if table_open then
      ImGui.TableNextColumn(ctx)
      local _,ay=ImGui.GetCursorScreenPos(ctx)
      local action_y=UI.note_editing(b) and (row.top+row.text_y)
        or ((first_line_center or (ay+row.center))-row.action_height*0.5)
      -- Table cells provide width reservation, but their local cursor
      -- includes native spacing. Use the same absolute trailing-action guide
      -- as the group header; both controls follow one vertical guide.
      ImGui.SetCursorScreenPos(ctx,UI.trailing_action_left(row.actions_right,row.action_button_width),action_y)
      action_hit=UI.block_action_button()
    end
    if b.kind=='select' then
      if table_open then ImGui.TableNextRow(ctx);ImGui.TableNextColumn(ctx) end
      local bx,by=ImGui.GetCursorScreenPos(ctx)
      ImGui.SetCursorScreenPos(ctx,bx,by+UI_METRICS.note_content_gap_y)
      UI.note_value_body(b)
    end
    if not table_open then action_hit=UI.block_action_button() end
    if table_open then ImGui.EndTable(ctx) end
  end
  ImGui.PopStyleVar(ctx,2)
  return action_hit,first_line_center,row
end
local function draw_selection_block(column,b,index,actions_right)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local width=math.max(1,math.min(ImGui.GetContentRegionAvail(ctx),actions_right-sx))
  local summary=b.text or b.label or ''
  if b.kind=='note' or b.kind=='check' then summary=(b.checked and '[x] ' or '[ ] ')..summary
  elseif b.kind=='select' then summary=summary..'\n'..b.options[b.selected] end
  if summary=='' then summary=tr('(Empty text block)') end
  ImGui.BeginGroup(ctx)
  UI.timecode_badge(b)
  local center=UI.read_text(summary,b,math.max(1,width-
    math.max(UI_METRICS.selection_text_gutter,UI_METRICS.selection_check_right_offset)))
  ImGui.EndGroup(ctx)
  local _,bottom=ImGui.GetItemRectMax(ctx)
  local height=math.max(UI_METRICS.selection_min_height,bottom-sy+UI_METRICS.selection_bottom_pad)
  ImGui.SetCursorScreenPos(ctx,sx,sy)
  ImGui.Dummy(ctx,width,height)
  return center
end
function UI.selection_hit_area(b,sx,sy,width,bottom,center)
  local save_x,save_y=ImGui.GetCursorScreenPos(ctx)
  ImGui.SetCursorScreenPos(ctx,sx,sy)
  if ImGui.InvisibleButton(ctx,'##bulk_select',width,math.max(1,bottom-sy),
      ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav) then
    local selected=bulk_selection.selected
    selected[b.id]=not selected[b.id] or nil
  end
  local hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
  if bulk_selection.selected[b.id] then
    ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
    local tw,th=ImGui.CalcTextSize(ctx,'✓')
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),
      sx+math.max(0,width-UI_METRICS.item_gap_x-tw),
      (center or (sy+bottom)*0.5)-th*0.5,ImGui.GetColor(ctx,ImGui.Col_Text),'✓')
    ImGui.PopFont(ctx)
  end
  ImGui.SetCursorScreenPos(ctx,save_x,save_y)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,0,0)
  ImGui.Dummy(ctx,0,0)
  ImGui.PopStyleVar(ctx)
  return hovered
end
function UI.note_marker_strip(key,sx,sy,bottom,gutter)
  local m=UI_METRICS
  local left=math.min(gutter,m.marker_strip_offset_x)
  local right=math.min(gutter,left+m.marker_strip_width)
  if right>left then
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),sx+left,sy+m.marker_strip_pad_y,
      sx+right,math.max(sy+m.marker_strip_min_bottom_offset,bottom-m.marker_strip_pad_y),
      UI.marker_color(key),m.marker_strip_rounding)
  end
end
function UI.note_gutter(width)
  local m=UI_METRICS
  local marker_right=m.marker_strip_offset_x+m.marker_strip_width
  local handle_x=math.max(m.drag_handle_offset_x,marker_right)
  local wanted=math.max(m.note_indent,handle_x+m.drag_handle_width+m.note_gutter_end_gap)
  return math.min(wanted,math.max(0,width-1))
end
function UI.note_padding(height)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,0,0)
  ImGui.Dummy(ctx,0,height)
  ImGui.PopStyleVar(ctx)
end
local function draw_marked_block(tab,column,b,index,actions_right)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local width=math.min(ImGui.GetContentRegionAvail(ctx),math.max(1,actions_right-sx))
  local selecting=bulk_selection and bulk_selection.column==column
  ImGui.PushID(ctx,b.id)
  local completed=M.completed(b)
  if completed then
    local alpha=ImGui.GetStyleVar(ctx,ImGui.StyleVar_Alpha)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_Alpha,alpha*UI_METRICS.completed_note_alpha)
  end
  local layer
  -- A palette popup can change the model while draw_block is submitted.
  -- Keep this shell's background, style pushes and marker on one frame value.
  local frame_marker=b.color
  local colored_fill=frame_marker and marker_style=='fill'
  if colored_fill or selecting then
    layer=UI.marker_layer(column)
    ImGui.DrawListSplitter_Split(layer.splitter,2)
    ImGui.DrawListSplitter_SetCurrentChannel(layer.splitter,1)
  end
  if colored_fill then
    -- Native edit fields and checkboxes share the same soft tint as the
    -- block background. Text colors, focus and input behavior stay native.
    for _,key in ipairs({ImGui.Col_FrameBg,ImGui.Col_FrameBgHovered,ImGui.Col_FrameBgActive}) do
      local base=ImGui.GetStyleColor(ctx,key)
      ImGui.PushStyleColor(ctx,key,UI.marker_tint(base,frame_marker))
    end
  end
  local gutter=UI.note_gutter(width)
  -- Indent(0) means the native default indent, not zero pixels.
  if gutter>0 then ImGui.Indent(ctx,gutter) end
  ImGui.BeginGroup(ctx)
  UI.note_padding(UI_METRICS.note_padding_y)
  -- Measure content independently of native trailing ItemSpacing. Both sides
  -- of the shell get the same actual padding, which also belongs to its fill.
  ImGui.BeginGroup(ctx)
  local action_hit,first_line_center=nil,nil
  if selecting then first_line_center=draw_selection_block(column,b,index,actions_right)
  else action_hit,first_line_center=draw_block(tab,column,b,index,actions_right) end
  ImGui.EndGroup(ctx)
  local _,content_bottom=ImGui.GetItemRectMax(ctx)
  local pad_x=ImGui.GetCursorScreenPos(ctx)
  ImGui.SetCursorScreenPos(ctx,pad_x,content_bottom)
  UI.note_padding(UI_METRICS.note_padding_y)
  ImGui.EndGroup(ctx)
  local _,bottom=ImGui.GetItemRectMax(ctx)
  if gutter>0 then ImGui.Unindent(ctx,gutter) end
  local selection_hovered=selecting and UI.selection_hit_area(b,sx,sy,width,bottom,first_line_center)
  if layer then
    if colored_fill then ImGui.PopStyleColor(ctx,3) end
    ImGui.DrawListSplitter_SetCurrentChannel(layer.splitter,0)
    if colored_fill then
      local base=ImGui.GetStyleColor(ctx,ImGui.Col_ChildBg)
      local color=ImGui.GetColorEx(ctx,UI.marker_tint(base,frame_marker))
      ImGui.DrawList_AddRectFilled(layer.draw_list,sx,sy,sx+width,
        math.max(sy+UI_METRICS.marker_fill_min_height,bottom),color,UI_METRICS.marker_fill_rounding)
    end
    if selecting and (bulk_selection.selected[b.id] or selection_hovered) then
      local key=bulk_selection.selected[b.id] and ImGui.Col_HeaderActive or ImGui.Col_HeaderHovered
      ImGui.DrawList_AddRectFilled(layer.draw_list,sx,sy,sx+width,bottom,
        placement_alpha(ImGui.GetColor(ctx,key),UI_PALETTE.text_selection_alpha/255),
        UI_METRICS.selection_rounding)
    end
    if frame_marker and not colored_fill then UI.note_marker_strip(frame_marker,sx,sy,bottom,gutter) end
    ImGui.DrawListSplitter_Merge(layer.splitter)
  elseif frame_marker then
    UI.note_marker_strip(frame_marker,sx,sy,bottom,gutter)
  end
  if completed then ImGui.PopStyleVar(ctx) end
  if not selecting then
    UI.note_drag_handle(tab,column,b,sx,sy,bottom,gutter,first_line_center)
  end
  -- The original note remains visibly selected during native DnD. This is
  -- drawn over this block alone, not around the containing group/section.
  -- The source becomes known in note_drag_handle(), so paint AFTER it.
  local dragged=UI.note_drag_current()
  if dragged and dragged.block==b then
    UI.note_highlight(sx,sy,width,bottom)
  end
  if UI.note_editing(b) then UI.note_edit.rect={sx,sy,sx+width,bottom} end
  -- Paint only after the complete note rectangle is known. This uses the
  -- current frame even when scrolling or changing the note's line count.
  if action_hit and not UI.note_drag_current() and not UI.place then
    local mx,my=ImGui.GetMousePos(ctx)
    local hovered=ImGui.IsWindowHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
      and mx>=sx and mx<sx+width and my>=sy and my<bottom
    if hovered or action_hit.focused or UI.note_editing(b) or ImGui.IsPopupOpen(ctx,'block_actions') then
      local dot_color=ImGui.GetColor(ctx,ImGui.Col_Text)
      if completed then dot_color=placement_alpha(dot_color,UI_METRICS.completed_note_alpha) end
      UI.paint_menu_dots(action_hit.x,action_hit.y,action_hit.width,action_hit.height,dot_color)
    end
  end
  -- Open and draw the popup in the block ID scope, after any nested tables.
  if action_hit and action_hit.clicked and not UI.note_drag_current() and not UI.place then
    ImGui.OpenPopup(ctx,'block_actions')
  end
  -- Test the complete block rectangle without placing an overlay over its
  -- checkbox or dropdown. The window check excludes clipped areas and popups.
  if startup_layout_frames>=STARTUP_LAYOUT_FRAMES and ImGui.IsWindowHovered(ctx) then
    local mx,my=ImGui.GetMousePos(ctx)
    if mx>=sx and mx<sx+width and my>=sy and my<bottom and ImGui.IsMouseReleased(ctx,1) then
      ImGui.OpenPopup(ctx,'block_actions')
    end
  end
  -- Menus use full opacity and are outside the measured note group.
  if not selecting then block_actions(tab,column,index) end
  ImGui.PopID(ctx)
  return {block=b,x=sx,y=sy,width=width,bottom=bottom}
end
-- One native row contains the existing note and separator, including the
-- space where its insertion line appears. It adds no overlay or dummy row.
-- Only the source row can inherit the active grip ID; it is never a target.
function UI.note_row(tab,column,block,index,actions_right)
  ImGui.BeginGroup(ctx)
  local rect=draw_marked_block(tab,column,block,index,actions_right)
  -- The note's measured bottom is the single spacing anchor. Native item
  -- gaps do not accumulate here; one preference controls both sides of the line.
  ImGui.SetCursorScreenPos(ctx,rect.x,rect.bottom)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,0,0)
  UI.note_separator(actions_right,note_spacing)
  ImGui.EndGroup(ctx)
  ImGui.PopStyleVar(ctx)
  UI.note_drop_row(column,block,rect.x,rect.y,rect.width,rect.bottom)
  return rect
end
-- Native drag-and-drop owns mouse capture and delivery. UI state binds its
-- short token to the current owner and document; only delivery mutates notes.
function UI.note_drag_current()
  local drag=UI.note_drag
  if not drag or UI.drag_cancelled or drag.owner~=session or drag.epoch~=epoch
      or not session or session.doc~=drag.doc or session.error or session.conflict
      or modal or UI.info or UI.place or bulk_selection or history_request or escape_pressed
      or startup_layout_frames<STARTUP_LAYOUT_FRAMES or not M.visible(drag.block,hide_completed) then return nil end
  return drag
end
function UI.note_drag_update()
  if UI.drag_cancelled and not ImGui.IsMouseDown(ctx,0) and not ImGui.IsMouseReleased(ctx,0) then UI.drag_cancelled=nil end
  if not UI.note_drag then return end
  local drag=UI.note_drag_current()
  local active,kind,token=ImGui.GetDragDropPayload(ctx)
  local column
  if drag then local tab;tab,column=M.note_location(drag.doc,drag.block) end
  -- The native payload may be absent until this frame's source is submitted.
  -- Keep a valid drag through that gap and the mouse-release delivery frame.
  local ended=not ImGui.IsMouseDown(ctx,0) and not ImGui.IsMouseReleased(ctx,0)
  if not drag or column~=drag.column or (active and (kind~='P34_NOTE' or token~=drag.token))
      or (not active and ended) then
    UI.note_drag=nil;UI.drag_cancelled=true
  end
end
function UI.draw_note_grip(draw_list,cx,cy,width,height,color)
  local m=UI_METRICS
  local side=math.max(0,math.min(m.drag_handle_icon_size,width,height))
  local radius=math.min(m.drag_handle_dot_radius,side/6)
  local pitch=math.min(m.drag_handle_dot_pitch,math.max(0,(side-2*radius)*0.5))
  if radius<=0 or pitch<=0 then return end
  for row=-1,1 do
    for column=0,1 do
      ImGui.DrawList_AddCircleFilled(draw_list,cx+(column-0.5)*pitch,
        cy+row*pitch,radius,color)
    end
  end
end
function UI.note_drag_handle(tab,column,block,sx,sy,bottom,gutter,first_line_center)
  if bulk_selection then return end
  local save_x,save_y=ImGui.GetCursorScreenPos(ctx)
  local m=UI_METRICS
  gutter=gutter or UI.note_gutter(ImGui.GetContentRegionAvail(ctx))
  local offset=math.min(gutter,math.max(m.drag_handle_offset_x,m.marker_strip_offset_x+m.marker_strip_width))
  local width=math.min(m.drag_handle_width,math.max(0,gutter-offset-m.note_gutter_end_gap))
  local center=first_line_center or (sy+ImGui.GetTextLineHeight(ctx)*0.5)
  local height=math.max(1,math.min(m.drag_handle_max_height,bottom-sy))
  -- Both the hitbox and the six visible dots use the first-line center.
  -- No vertical correction or image-alpha rectangle participates in alignment.
  local offset_y=center-sy-height*0.5
  if width<=0 then return end
  local hx,hy=sx+offset,sy+offset_y
  ImGui.SetCursorScreenPos(ctx,hx,hy)
  ImGui.InvisibleButton(ctx,'##drag_note',width,height,ImGui.ButtonFlags_MouseButtonLeft)
  local color=ImGui.GetColor(ctx,ImGui.Col_TextDisabled)
  UI.draw_note_grip(ImGui.GetWindowDrawList(ctx),hx+width*0.5,center,width,height,color)
  ImGui.SetItemTooltip(ctx,tr('Drag to move note'))
  if not UI.drag_cancelled and not escape_pressed and not modal and not UI.info and not history_request
      and startup_layout_frames>=STARTUP_LAYOUT_FRAMES and ImGui.BeginDragDropSource(ctx,0) then
    local drag=UI.note_drag_current()
    if not drag or drag.block~=block then
      UI.drag_sequence=(UI.drag_sequence or 0)+1
      drag={owner=session,epoch=epoch,doc=session.doc,column=column,block=block,
        token=tostring(epoch)..':'..tostring(block.id)..':'..UI.drag_sequence}
      UI.end_note_edit()
      UI.note_drag=drag;UI.double_press=nil
      session.history.key=nil;session.input_state=nil;undo_boundary=true
    end
    ImGui.SetDragDropPayload(ctx,'P34_NOTE',drag.token,ImGui.Cond_Once)
    ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
    local caption=(block.text or block.label or ''):match('([^\n]*)') or ''
    -- Drag source tooltip auto-sizes. TextWrapped has no stable wrap width
    -- there and could create a one-character-wide vertical column of text.
    local pos,chars=0,0
    while pos<#caption and chars<UI_METRICS.drag_preview_max_chars do pos=M.editor_next(caption,pos);chars=chars+1 end
    if pos<#caption then caption=caption:sub(1,pos)..'…' end
    ImGui.Text(ctx,caption~='' and caption or tr('(Empty text block)'))
    ImGui.PopFont(ctx)
    ImGui.EndDragDropSource(ctx)
  end
  ImGui.SetCursorScreenPos(ctx,save_x,save_y)
  ImGui.Dummy(ctx,0,0)
end
function UI.note_delete_drop(drag)
  if session.pending or not UI.note_drag_current() or UI.note_drag~=drag then return end
  local owner,doc,generation,block=session,session.doc,epoch,drag.block
  session.pending=function()
    if session~=owner or session.doc~=doc or epoch~=generation
        or not api.valid(owner.target) then return end
    local _,column=M.note_location(doc,block)
    if not column then return end
    UI.note_drag=nil
    UI.drag_cancelled=true
    confirm_delete(function()
      -- Re-resolve membership after the confirmation, not on mouse release.
      if session~=owner or session.doc~=doc or not api.valid(owner.target) then return end
      local _,target,index=M.note_location(doc,block)
      if target and index then
        table.remove(target.blocks,index)
        UI.new_input=nil;owner.history.key=nil;owner.input_state=nil
        touch(nil,'delete_note')
      end
    end,'note')
  end
end
function UI.note_drop_commit(drag,target,anchor,after)
  if session.pending or not UI.note_drag_current() or UI.note_drag~=drag then return end
  local owner,doc,generation=session,session.doc,epoch
  session.pending=function()
    -- Re-resolve pointer membership after all widgets have been submitted.
    if session==owner and session.doc==doc and epoch==generation and UI.note_drag_current()==drag
        and api.valid(session.target) then
      local moved,tab,index=M.note_move(doc,drag.block,target,anchor,after,completed_last,hide_completed)
      if moved then
        target.folded=false;tab.folded=false;session.active=index;force_tab=tab.id
        UI.new_input=nil;session.history.key=nil;session.input_state=nil
        touch(nil,'move_note');undo_boundary=true
      end
    end
    UI.note_drag=nil
  end
end
-- Consume delivery from an already submitted native item. Both note rows
-- and section fallback targets share this owner/token/plan validation.
function UI.note_drop_item(column,anchor,after,line_y,span)
  local drag=UI.note_drag_current()
  if not drag then return end
  if not M.note_drop_plan(drag.doc,drag.block,column,anchor,after,
      completed_last,hide_completed) then return end
  if ImGui.BeginDragDropTarget(ctx) then
    local flags=ImGui.DragDropFlags_AcceptBeforeDelivery|ImGui.DragDropFlags_AcceptNoDrawDefaultRect
    local accepted,token=ImGui.AcceptDragDropPayload(ctx,'P34_NOTE',nil,flags)
    local active,kind,payload,preview,delivery=ImGui.GetDragDropPayload(ctx)
    if accepted and active and kind=='P34_NOTE' and token==drag.token and payload==drag.token then
      if preview and line_y and span then
        -- The native target includes its group heading. The insertion line
        -- follows the already measured NOTE shell and separator guide.
        local min_x=span.x
        local max_x=min_x+span.width-UI_METRICS.note_separator_right_inset
        local color=ImGui.GetColor(ctx,ImGui.Col_CheckMark)
        if max_x>min_x then
          ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),min_x,line_y,
            max_x,line_y,color,UI_METRICS.drop_line_thickness)
        end
      end
      if delivery then UI.note_drop_commit(drag,column,anchor,after) end
    end
    ImGui.EndDragDropTarget(ctx)
  end
end
-- EndGroup forwards an active child's ID. A whole source section therefore
-- has the source ID and BeginDragDropTarget rejects it. Accept same-section
-- reordering on the existing neighboring rows; never on the source row.
function UI.note_drop_row(column,block,sx,sy,width,bottom)
  local drag=UI.note_drag_current()
  if not drag or drag.column~=column or drag.block==block then return end
  local _,my=ImGui.GetMousePos(ctx)
  local after=my>=(sy+bottom)*0.5
  UI.note_drop_item(column,block,after,after and bottom+2 or sy,{x=sx,width=width})
end
-- Section fallback retains all N+1 boundaries for transfers between groups,
-- including empty destinations. No extra items or overlay hitboxes are added.
function UI.note_drop_section(column,rects)
  local drag=UI.note_drag_current()
  if not drag or drag.column==column then return end
  local anchor,after,line_y
  if #rects>0 then
    local _,my=ImGui.GetMousePos(ctx)
    anchor,after,line_y=M.note_insertion_slot(rects,my)
  end
  UI.note_drop_item(column,anchor,after,line_y,rects[1])
end
function UI.note_drag_tab(tab,hovered)
  local drag=UI.note_drag_current()
  if not drag then return end
  if hovered then
    local now=reaper.time_precise()
    if drag.hover_tab~=tab then drag.hover_tab=tab;drag.hover_since=now end
    if now-drag.hover_since>=0.45 and session.doc.tabs[session.active]~=tab then force_tab=tab.id end
  elseif drag.hover_tab==tab then drag.hover_tab=nil;drag.hover_since=nil end
end
function UI.note_drag_scroll()
  local drag=(UI.place_valid(UI.place) and UI.place.mode=='drag') and UI.place or UI.note_drag_current()
  if not drag or not ImGui.IsWindowHovered(ctx,ImGui.HoveredFlags_ChildWindows|ImGui.HoveredFlags_AllowWhenBlockedByActiveItem) then return end
  local x,y=ImGui.GetWindowPos(ctx)
  local width,height=ImGui.GetWindowSize(ctx)
  local mx,my=ImGui.GetMousePos(ctx)
  if mx<x or mx>x+width or my<y or my>y+height then return end
  local now=reaper.time_precise()
  local dt=math.min(0.05,math.max(0,now-(drag.scroll_time or now-1/60)))
  drag.scroll_time=now
  local edge=math.min(UI_METRICS.note_drag_scroll_edge,height*0.2)
  local step=my<y+edge and -(y+edge-my)/edge or my>y+height-edge and (my-y-height+edge)/edge or 0
  if step~=0 then
    local maximum=ImGui.GetScrollMaxY(ctx)
    ImGui.SetScrollY(ctx,math.max(0,math.min(maximum,ImGui.GetScrollY(ctx)+step*UI_METRICS.note_drag_scroll_speed*dt)))
  end
end

-- Right-side geometry is shared by column headings, tab headings and
-- note tables. All are children with different native padding, so deriving
-- each action edge from GetContentRegionAvail() creates visible misalignment.
-- Compute the thumb's bounds exactly as the overlay renderer does, and keep
-- the shared action line to its left. No interactive overlay is added.
function UI.overlay_scroll_bounds(window_right,pad_x)
  local m=UI_METRICS
  local right=window_right-math.min(pad_x,m.overlay_scroll_inset)
  local left=math.max(window_right-pad_x,right-m.overlay_scroll_width)
  return left,right
end
function UI.board_actions_edge(body_window_right,pad_x)
  local scroll_left=UI.overlay_scroll_bounds(body_window_right,pad_x)
  local m=UI_METRICS
  return math.min(body_window_right-pad_x,scroll_left-m.action_to_scroll_gap)-m.action_right_inset
end
-- A fixed-width separator uses the same right guide as the note/menu buttons.
-- The native Separator() stretches to a different content edge after Indent()
-- and may overflow into the overlay scrollbar's track.
function UI.note_separator(right,gap)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local m=UI_METRICS
  local end_x=math.max(sx,math.min(right-m.note_separator_right_inset,
    sx+ImGui.GetContentRegionAvail(ctx)))
  if end_x>sx then
    local line_y=gap~=nil and sy+gap+0.5 or sy-m.note_separator_raise+0.5
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),sx,line_y,end_x,line_y,
      ImGui.GetColor(ctx,ImGui.Col_Separator),m.note_separator_thickness)
  end
  -- A single native item reserves the line and both adjustable gaps. Other
  -- separator uses retain their pre-existing geometry when gap is absent.
  ImGui.Dummy(ctx,0,gap~=nil and 2*gap+m.note_separator_height or m.note_separator_height)
end

-- Thin, draggable scrollbar thumb drawn over the note viewport. The native
-- scrollbar is hidden (without disabling mouse-wheel scrolling), so ImGui
-- never reserves a changing right-hand gutter. There is no extra widget,
-- cursor repositioning or BeginGroup manipulation. Keep the entire hit zone
-- in the existing window padding, outside the rightmost note-action button.
function UI.overlay_scroll_thumb(board)
  local drag=UI.overlay_scroll_drag
  if drag and (not ImGui.IsMouseDown(ctx,0) or drag.owner~=session or drag.epoch~=epoch) then
    UI.overlay_scroll_drag=nil
    drag=nil
  end
  local max_scroll=ImGui.GetScrollMaxY(ctx)
  if max_scroll<=1 then
    if drag and drag.board==board then UI.overlay_scroll_drag=nil end
    return
  end
  local wx,wy=ImGui.GetWindowPos(ctx)
  local ww,wh=ImGui.GetWindowSize(ctx)
  local m=UI_METRICS
  local top=wy+m.overlay_scroll_margin
  local track_h=wh-2*m.overlay_scroll_margin
  if track_h<m.overlay_scroll_min_track_height then return end
  local thumb_h=math.max(m.overlay_scroll_min_thumb_height,
    track_h*wh/(wh+max_scroll))
  thumb_h=math.min(thumb_h,track_h)
  local travel=track_h-thumb_h
  local scroll=math.max(0,math.min(max_scroll,ImGui.GetScrollY(ctx)))
  local thumb_y=top+(travel>0 and travel*scroll/max_scroll or 0)
  local pad_x=ImGui.GetStyleVar(ctx,ImGui.StyleVar_WindowPadding)
  local left,right=UI.overlay_scroll_bounds(wx+ww,pad_x)
  if right<=left then return end
  local hit_left=math.max(wx+ww-pad_x,left-m.overlay_scroll_hit_pad_left)
  local hit_right=math.min(wx+ww,right+m.overlay_scroll_hit_pad_right)
  local mx,my=ImGui.GetMousePos(ctx)
  local on_thumb=mx>=hit_left and mx<=hit_right and my>=thumb_y and my<=thumb_y+thumb_h
  local active=drag and drag.board==board
  if not active and not UI.place and not UI.note_drag_current()
      and startup_layout_frames>=STARTUP_LAYOUT_FRAMES
      and ImGui.IsWindowHovered(ctx) and on_thumb and ImGui.IsMouseClicked(ctx,0) then
    UI.overlay_scroll_drag={owner=session,epoch=epoch,board=board,offset=my-thumb_y}
    active=true
  end
  if active and ImGui.IsMouseDown(ctx,0) and travel>0 then
    local offset=UI.overlay_scroll_drag.offset
    local ratio=math.max(0,math.min(1,(my-offset-top)/travel))
    ImGui.SetScrollY(ctx,ratio*max_scroll)
  end
  local color=ImGui.GetColorEx(ctx,themes[theme].viewer[
    active and 'C_SCROLL_A' or on_thumb and 'C_SCROLL_H' or 'C_SCROLL'])
  local dl=ImGui.GetWindowDrawList(ctx)
  ImGui.DrawList_AddRectFilled(dl,left,thumb_y,right,thumb_y+thumb_h,color,
    m.overlay_scroll_width*0.5)
end

function UI.column_node(column)
  -- TreeNodeEx draws the native disclosure arrow at the current font size.
  -- This size affects only the arrow, not the note text or the trailing menu.
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size+UI_METRICS.tab_arrow_extra_px)
  ImGui.SetNextItemOpen(ctx,not column.folded,ImGui.Cond_Always)
  local mouse=ImGui.IsMouseDown(ctx,0) or ImGui.IsMouseReleased(ctx,0)
  if mouse then
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_DisabledAlpha,1);ImGui.BeginDisabled(ctx,true)
  end
  -- Keep the native arrow hit-box narrow: the title and the trailing menu
  -- are separately submitted items. The whole arrow+title hover background
  -- is painted by column_header without changing any ImGui hit boxes.
  ImGui.PushStyleColor(ctx,ImGui.Col_HeaderHovered,0x00000000)
  local open=ImGui.TreeNodeEx(ctx,'column_fold','',
    ImGui.TreeNodeFlags_NoTreePushOnOpen|ImGui.TreeNodeFlags_FramePadding|ImGui.TreeNodeFlags_SpanLabelWidth)
  ImGui.PopStyleColor(ctx)
  local toggled=not mouse and ImGui.IsItemToggledOpen(ctx)
  local hovered=ImGui.IsItemHovered(ctx,mouse and ImGui.HoveredFlags_AllowWhenDisabled or 0)
  if mouse then ImGui.EndDisabled(ctx);ImGui.PopStyleVar(ctx) end
  ImGui.PopFont(ctx)
  if startup_layout_frames>=STARTUP_LAYOUT_FRAMES then
    if hovered and ImGui.IsMouseClicked(ctx,0) then UI.column_press={column=column,owner=session,epoch=epoch} end
    local press=UI.column_press
    if ImGui.IsMouseReleased(ctx,0) and press and press.column==column then
      UI.column_press=nil
      if hovered and press.owner==session and press.epoch==epoch then open=column.folded==true;toggled=true end
    end
    if toggled and open==(column.folded==true) then
      column.folded=not open
      if UI.note_edit and UI.note_edit.column==column then UI.end_note_edit() end
      if bulk_selection and bulk_selection.column==column then bulk_selection=nil end
      session.history.key=nil;session.input_state=nil;undo_boundary=true
    end
  end
end
-- Public columns contain independently collapsible vertical tabs. Internal
-- tab/column field names are retained for storage/history helper compatibility.
function UI.add_section(board,after)
  if session.pending then return end
  local owner,doc,generation=session,session.doc,epoch
  session.pending=function()
    if session~=owner or session.doc~=doc or epoch~=generation then return end
    for bi,candidate in ipairs(doc.tabs) do
      if candidate==board then
        for i,section in ipairs(board.columns) do
          if section==after then
            local created=M.column(tr('Group')..' '..(#board.columns+1))
            table.insert(board.columns,i+1,created);session.active_group_id=created.id
            session.active=bi;touch(nil,'add_group');undo_boundary=true;return
          end
        end
      end
    end
  end
end
-- Headings register a clipped, single-line native item. Long user names do
-- not extend the layout or wrap into vertical text in narrow columns.
function UI.heading_text(text,width,height,show_tooltip)
  width=math.max(0,width)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  ImGui.Dummy(ctx,width,height)
  if width>0 then
    local color=ImGui.GetColor(ctx,ImGui.Col_Text)
    local shown=text:gsub('[\r\n]',' ')
    local line_h=ImGui.GetTextLineHeight(ctx)
    ImGui.PushClipRect(ctx,sx,sy,sx+width,sy+height,true)
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),sx,sy+(height-line_h)*0.5,color,shown)
    ImGui.PopClipRect(ctx)
  end
  local hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
  if show_tooltip~=false then ImGui.SetItemTooltip(ctx,text) end
  return hovered
end
-- Align both group and note menus to the right edge of their shared
-- content guide. Native tables and SameLine use different local origins;
-- button placement must not depend on those origins or their padding.
function UI.trailing_action_left(right,width) return right-width end
-- One theme-aware dot painter for groups and notes. Caller supplies the
-- current-frame hitbox; the layout container never affects visual geometry.
function UI.paint_menu_dots(sx,sy,width,height,color)
  local m=UI_METRICS
  local radius=math.max(0.5,math.min(m.group_menu_dot_radius,height*0.25,width/8))
  local spacing=math.max(2*radius+1,math.min(m.group_menu_dot_spacing,(width-2*radius)*0.5))
  local cx,cy=sx+width*0.5,sy+height*0.5
  local tint=color or ImGui.GetColor(ctx,ImGui.Col_Text)
  local dl=ImGui.GetWindowDrawList(ctx)
  for i=-1,1 do
    ImGui.DrawList_AddCircleFilled(dl,cx+i*spacing,cy,radius,tint,12)
  end
end
function UI.group_menu_dots(width,height,id)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  width,height=math.max(1,width),math.max(1,height)
  local clicked=ImGui.InvisibleButton(ctx,id or '##section_actions_dots',width,height,
    ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav)
  UI.paint_menu_dots(sx,sy,width,height)
  return clicked
end
-- The quick-add icon is the standard Lucide circle-plus mask. The SVG's
-- circle/plus geometry and stroke are not reconstructed using draw-list lines.
function UI.group_add_checkbox_button(section,width,empty)
  local m=UI_METRICS
  local side=m.group_add_note_size
  if width<side then return end
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local top_gap=empty and m.group_add_note_empty_top_gap or m.group_add_note_top_gap
  local x=sx+(width-side)*0.5
  local y=sy+top_gap
  ImGui.SetCursorScreenPos(ctx,x,y)
  local clicked=ImGui.InvisibleButton(ctx,'##group_add_checkbox',side,side,
    ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav)
  local hovered=ImGui.IsItemHovered(ctx)
  -- Apply theme-aware opacity to the Lucide mask, leaving the native 36px
  -- click target intact even though the visible mark is smaller and lighter.
  local base_color=ImGui.GetColor(ctx,hovered and ImGui.Col_Text or ImGui.Col_TextDisabled)
  local opacity=hovered and m.group_add_note_hover_alpha or m.group_add_note_idle_alpha
  local color=placement_alpha(base_color,opacity)
  local icon=UI.icon_image('circle_plus')
  local icon_side=math.min(side,m.group_add_note_icon_size)
  local offset=(side-icon_side)*0.5
  ImGui.DrawList_AddImage(ImGui.GetWindowDrawList(ctx),icon,
    x+offset,y+offset,x+offset+icon_side,y+offset+icon_side,0,0,1,1,color)
  ImGui.SetItemTooltip(ctx,tr('Add checkbox note'))
  -- Register bottom padding as a native item, so the next group's heading
  -- cannot overlap the button even in a small/docked viewport.
  ImGui.SetCursorScreenPos(ctx,sx,y+side)
  ImGui.Dummy(ctx,0,m.group_add_note_bottom_gap)
  if clicked then add_from_menu('note',section) end
end
local function column_header(board,section,index,actions_right)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  if bulk_selection and bulk_selection.column==section then
    selection_toolbar(section,actions_right);ImGui.PopFont(ctx);return
  end
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local content_w=ImGui.GetContentRegionAvail(ctx)
  -- The section body uses an overlay scrollbar without a native gutter.
  -- Use the same absolute button edge in both child windows.
  -- A single right edge for heading background, title, and trailing menu.
  -- Keep the optional inset in the layout itself, not only in the drawing.
  local width=math.max(1,math.min(content_w,actions_right-sx))
  local heading_right=sx+width
  local menu_w,height=UI.button_size('...')
  local gap=UI_METRICS.tab_heading_menu_gap
  local min_title=UI_METRICS.tab_heading_min_title
  -- Paint backgrounds BEFORE the native disclosure arrow and the text;
  -- otherwise the later draw-list rectangles cover their foreground pixels.
  -- Backgrounds have no ImGui hitboxes.
  if section.header_color then
    local tint_amount=theme=='dark' and UI_METRICS.group_header_tint_dark or UI_METRICS.group_header_tint_light
    local fill=UI.marker_tint(themes[theme].paper,section.header_color,tint_amount)
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),sx,sy,
      heading_right,sy+math.max(height,UI_METRICS.group_header_min_height),
      ImGui.GetColorEx(ctx,fill),UI_METRICS.button_rounding)
  end
  -- The hover background now covers the whole group header, including
  -- the reserved trailing-menu rectangle. It is draw-only, behind the items:
  -- no new hitboxes, no changed click/drag semantics and no layout row.
  local mx,my=ImGui.GetMousePos(ctx)
  local heading_hovered=ImGui.IsWindowHovered(ctx) and mx>=sx and mx<heading_right
      and my>=sy and my<sy+height and not UI.place and not UI.note_drag_current()
  if heading_hovered and (ImGui.IsMouseClicked(ctx,0) or ImGui.IsMouseClicked(ctx,1)) then
    session.active_group_id=section.id
  end
  if heading_hovered and heading_right>sx then
    local hover_color=ImGui.GetColor(ctx,ImGui.Col_HeaderHovered)
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),
      sx,sy,heading_right,sy+height,placement_alpha(hover_color,UI_METRICS.tab_heading_hover_alpha),UI_METRICS.button_rounding)
  end
  ImGui.BeginGroup(ctx)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size+UI_METRICS.tab_arrow_extra_px)
  local arrow_line_h=ImGui.GetTextLineHeight(ctx)
  ImGui.PopFont(ctx)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,UI_METRICS.frame_pad_x,
    math.max(0,(height-arrow_line_h)*0.5))
  UI.column_node(section)
  ImGui.PopStyleVar(ctx)
  local arrow_hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
  ImGui.SameLine(ctx,0,UI_METRICS.tab_heading_arrow_text_gap)
  local text_x=ImGui.GetCursorScreenPos(ctx)
  local available=math.max(0,width-(text_x-sx))
  local show_menu=available>=min_title+gap+menu_w
  local title_w=math.max(0,available-(show_menu and gap+menu_w or 0))
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size+UI_METRICS.tab_heading_extra_px)
  local title_hovered=UI.heading_text(section.name,title_w,height,false)
  ImGui.PopFont(ctx)
  if show_menu then
    ImGui.SameLine(ctx,0,gap)
    ImGui.SetCursorScreenPos(ctx,UI.trailing_action_left(heading_right,menu_w),sy)
    -- Keep the menu's native ID and hitbox stable even when the pointer is
    -- elsewhere. Rendering a Dummy in its place would break keyboard focus.
    if UI.group_menu_dots(menu_w,height) then ImGui.OpenPopup(ctx,'section_actions') end
  end
  ImGui.EndGroup(ctx)
  local hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
  UI.section_hover(section,hovered or title_hovered or arrow_hovered)
  if UI.double_click_released('rename_section_'..section.id,title_hovered) then
    request_modal({kind='rename_column',title='Rename group',target=section,value=section.name})
  end
  if ImGui.IsMouseReleased(ctx,1) and hovered then ImGui.OpenPopup(ctx,'section_actions') end
  if begin_action_popup('section_actions') then
    if ImGui.MenuItem(ctx,ui_label('New group below')) then UI.add_section(board,section) end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx,ui_label('Select elements...'),nil,false,#section.blocks>0) then start_selection(board,section) end
    if ImGui.MenuItem(ctx,ui_label('Rename')) then
      request_modal({kind='rename_column',title='Rename group',target=section,value=section.name})
    end
    if ImGui.BeginMenu(ctx,ui_label('Group header color')) then
      marker_menu(section.header_color,function(key)
        if section.header_color~=key then
          section.header_color=key;touch(nil,'group_color');undo_boundary=true
        end
      end,'No color','group_')
      ImGui.EndMenu(ctx)
    end
    if ImGui.MenuItem(ctx,ui_label('Move up'),nil,false,index>1) then
      session.pending=function()M.move(board.columns,index,-1);touch(nil,'move_group')end
    end
    if ImGui.MenuItem(ctx,ui_label('Move down'),nil,false,index<#board.columns) then
      session.pending=function()M.move(board.columns,index,1);touch(nil,'move_group')end
    end
    if ImGui.MenuItem(ctx,ui_label('Delete group...'),nil,false,#board.columns>1) then
      confirm_delete(function()table.remove(board.columns,index);touch(nil,'delete_group')end,'group')
    end
    ImGui.EndPopup(ctx)
  end
  ImGui.PopFont(ctx)
end
function UI.board_actions(board,index)
  if ImGui.MenuItem(ctx,ui_label('Rename')) then
    request_modal({kind='rename_column',title='Rename tab',target=board,value=board.name})
  end
  if ImGui.MenuItem(ctx,ui_label('Move left'),nil,false,index>1) then
    UI.queue_tab_reorder(board.id,session.doc.tabs[index-1].id)
  end
  if ImGui.MenuItem(ctx,ui_label('Move right'),nil,false,index<#session.doc.tabs) then
    UI.queue_tab_reorder(board.id,session.doc.tabs[index+2] and session.doc.tabs[index+2].id)
  end
  if ImGui.MenuItem(ctx,ui_label('Delete tab...'),nil,false,#session.doc.tabs>1) then
    confirm_tab_delete(board)
  end
end


-- Each outer model tab is one horizontal page. Its nested columns remain
-- independent, collapsible groups. Internal names are intentionally retained
-- to read older v1/v2 project notes and preserve history helpers.
-- Tab gestures use their own state, never the note/creation payload types.
function UI.queue_tab_reorder(id,before)
  if session.pending then return end
  local owner,doc,generation=session,session.doc,epoch
  session.pending=function()
    if session~=owner or session.doc~=doc or epoch~=generation
        or not api.valid(owner.target) then return end
    local moved
    session.active,moved=M.reorder_tab(doc,id,before,session.active)
    if moved then touch(nil,'move_tab');undo_boundary=true;bulk_selection=nil end
  end
end
function UI.tab_gesture_valid(press)
  return press and press.owner==session and press.doc==session.doc and press.epoch==epoch
    and not session.error and not session.conflict and not modal
    and not UI.info and not UI.place and not bulk_selection and not history_request
    and not escape_pressed and not UI.note_drag_current()
    and startup_layout_frames>=STARTUP_LAYOUT_FRAMES
end
function UI.tab_reorder_target(rects,mx,my,left,top,width,height,hovered)
  if not hovered or mx<left or mx>=left+width or my<top or my>=top+height then return nil end
  for _,r in ipairs(rects) do
    if mx<r.x+r.width*0.5 then return {before=r.id,x=r.x} end
  end
  local last=rects[#rects]
  if last then return {x=last.x+last.width} end
end
function UI.tabs_strip()
  local m=UI_METRICS
  if not UI.tab_gesture_valid(UI.tab_gesture) then UI.tab_gesture=nil end
  local available=math.max(1,ImGui.GetContentRegionAvail(ctx))
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local side=m.button_min_height
  local gap=m.tabs_strip_button_gap
  local pad=m.tabs_strip_pad_x
  local controls_w=2*side+gap
  local right_inset=math.min(m.tabs_actions_right_inset,math.max(0,available-controls_w))
  local strip_h=math.max(m.tabs_strip_height,side+2*m.tabs_strip_pad_y)
  -- Read the shared action edge, but clamp against the CURRENT window width.
  local fallback_right=sx+available-right_inset
  local menu_right=math.min(fallback_right,UI.shared_actions_right or fallback_right)
  menu_right=math.max(sx+controls_w,menu_right)
  local list_width=math.max(1,menu_right-sx-controls_w-gap-pad)
  local label_widths={}
  local total=0
  ImGui.PushFont(ctx,heading_bold_font,UI_METRICS.font_size)
  for index,board in ipairs(session.doc.tabs) do
    local caption=board.name:gsub('[\r\n]',' ')
    local tw=ImGui.CalcTextSize(ctx,caption)
    label_widths[index]=math.max(m.tabs_strip_min_width,tw+2*m.tabs_strip_label_pad_x)
    total=total+label_widths[index]+(index>1 and m.tabs_strip_gap or 0)
  end
  ImGui.PopFont(ctx)
  local tab_h=strip_h-m.tabs_strip_pad_y*2
  -- Reserve the native horizontal scrollbar below the labels instead of
  -- letting it clip their lower half in a narrow docker.
  if total>list_width then strip_h=strip_h+ImGui.GetStyleVar(ctx,ImGui.StyleVar_ScrollbarSize) end
  local strip_color=ImGui.GetColorEx(ctx,themes[theme].chrome)
  ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),
    sx,sy,sx+available,sy+strip_h,strip_color)
  -- Start the only child exactly at the visible tab-list position. The popup
  -- controls below are submitted in the PARENT window's original ID scope.
  ImGui.SetCursorScreenPos(ctx,sx+pad,sy)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,0,0)
  ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0x00000000)
  ImGui.SetNextWindowContentSize(ctx,total,0)
  local visible=ImGui.BeginChild(ctx,'page_tabs',list_width,strip_h,0,
    ImGui.WindowFlags_HorizontalScrollbar)
  ImGui.PopStyleColor(ctx);ImGui.PopStyleVar(ctx)
  if visible then
    local rects={}
    local tx,ty=ImGui.GetCursorScreenPos(ctx)
    local mx,my=ImGui.GetMousePos(ctx)
    ImGui.SetCursorScreenPos(ctx,tx,ty+m.tabs_strip_pad_y)
    for index,board in ipairs(session.doc.tabs) do
      if index>1 then ImGui.SameLine(ctx,0,m.tabs_strip_gap) end
      local w=label_widths[index]
      local h=tab_h
      -- Stable native IDs eliminate an unnecessary PushID/PopID scope.
      local clicked=ImGui.InvisibleButton(ctx,'##open_page_'..board.id,w,h,
        ImGui.ButtonFlags_MouseButtonLeft)
      local hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
      local x,y=ImGui.GetItemRectMin(ctx)
      rects[#rects+1]={id=board.id,x=x,width=w}
      if ImGui.IsItemActivated(ctx) and UI.tab_gesture_valid({owner=session,doc=session.doc,epoch=epoch}) then
        local payload=ImGui.GetDragDropPayload(ctx)
        if not payload then
          UI.tab_gesture={owner=session,doc=session.doc,epoch=epoch,id=board.id}
        end
      end
      local press=UI.tab_gesture
      if press and press.id==board.id and ImGui.IsItemActive(ctx)
          and ImGui.IsMouseDragging(ctx,0,m.pointer_drag_threshold) then
        if not press.dragging then UI.end_note_edit();UI.double_press=nil end
        press.dragging=true
      end
      local active=session.active==index
      if hovered or active then
        local c=ImGui.GetColor(ctx,hovered and ImGui.Col_HeaderHovered or ImGui.Col_Header)
        ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),x,y,x+w,y+h,
          placement_alpha(c,hovered and 0.65 or 0.4),m.button_rounding)
      end
      if active then
        local accent=ImGui.GetColor(ctx,ImGui.Col_CheckMark)
        ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),x,y+h-m.tabs_strip_active_line,
          x+w,y+h,accent)
      end
      local caption=board.name:gsub('[\r\n]',' ')
      ImGui.PushFont(ctx,active and heading_bold_font or ui_font,UI_METRICS.font_size)
      local tw,th=ImGui.CalcTextSize(ctx,caption)
      ImGui.PushClipRect(ctx,x,y,x+w,y+h,true)
      ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),x+m.tabs_strip_label_pad_x,
        y+(h-th)*0.5,ImGui.GetColor(ctx,ImGui.Col_Text),caption)
      ImGui.PopClipRect(ctx)
      ImGui.PopFont(ctx)
      if clicked and not (UI.tab_gesture and UI.tab_gesture.dragging) and not UI.note_drag_current() then
        UI.end_note_edit();session.active=index;bulk_selection=nil
      end
      if hovered then UI.note_drag_tab(board,true) end
      if not (UI.tab_gesture and UI.tab_gesture.dragging)
          and UI.double_click_released('tab_'..board.id,hovered) then
        request_modal({kind='rename_column',title='Rename tab',target=board,value=board.name})
      end
      local menu='tab_actions_'..board.id
      if hovered and ImGui.IsMouseReleased(ctx,1) then ImGui.OpenPopup(ctx,menu) end
      if begin_action_popup(menu) then
        UI.tab_gesture=nil
        UI.board_actions(board,index);ImGui.EndPopup(ctx)
      end
    end
    local press=UI.tab_gesture
    if press and press.dragging then
      local hovered=ImGui.IsWindowHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
      -- Scrollbar space is excluded from both delivery and the insertion line.
      local scrollbar=ImGui.GetStyleVar(ctx,ImGui.StyleVar_ScrollbarSize)
      local content_h=strip_h-(total>list_width and scrollbar or 0)
      local target=UI.tab_reorder_target(rects,mx,my,sx+pad,sy,list_width,content_h,hovered)
      if target then
        local ix=math.max(sx+pad,math.min(sx+pad+list_width,target.x))
        local color=ImGui.GetColor(ctx,ImGui.Col_CheckMark)
        ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),ix,sy+m.tabs_strip_pad_y,
          ix,sy+content_h,color,m.tabs_drop_line_width)
        if ImGui.IsMouseReleased(ctx,0) then UI.queue_tab_reorder(press.id,target.before) end
      end
      if target and ImGui.IsMouseDown(ctx,0) then
        local now=reaper.time_precise()
        local dt=math.min(0.05,math.max(0,now-(press.scroll_time or now)))
        press.scroll_time=now
        local edge=math.min(m.tabs_drag_scroll_edge,list_width*0.25)
        local direction=mx<sx+pad+edge and -1 or mx>sx+pad+list_width-edge and 1 or 0
        ImGui.SetScrollX(ctx,math.max(0,math.min(ImGui.GetScrollMaxX(ctx),
          ImGui.GetScrollX(ctx)+direction*m.tabs_drag_scroll_speed*dt)))
      else press.scroll_time=nil end
    end
  elseif UI.tab_gesture then
    -- A clipped strip cannot accept a release during a docking/resize frame.
    if ImGui.IsMouseReleased(ctx,0) then UI.tab_gesture=nil end
  end
  ImGui.EndChild(ctx)
  if ImGui.IsMouseReleased(ctx,0) or not ImGui.IsMouseDown(ctx,0) then UI.tab_gesture=nil end
  -- Draw tab controls in the parent, never under the scrolling child ID.
  local control_y=sy+(strip_h-side)*0.5
  local menu_x=menu_right-side
  local add_x=menu_x-gap-side
  ImGui.SetCursorScreenPos(ctx,add_x,control_y)
  ImGui.BeginDisabled(ctx,#session.doc.tabs>=8)
  if UI.source_button('add_page','+',side,side) then add_column() end
  ImGui.EndDisabled(ctx)
  ImGui.SetItemTooltip(ctx,tr('New tab'))
  ImGui.SetCursorScreenPos(ctx,menu_x,control_y)
  if UI.source_button('page_actions','...',side,side) then ImGui.OpenPopup(ctx,'page_actions') end
  if begin_action_popup('page_actions') then
    UI.board_actions(active_tab(),session.active)
    ImGui.EndPopup(ctx)
  end
  -- The strip is one layout row, although its controls are drawn explicitly.
  ImGui.SetCursorScreenPos(ctx,sx,sy)
  ImGui.Dummy(ctx,available,strip_h)
end

local function draw_document()
  -- A hovered tab may have requested a page switch during the previous frame.
  if force_tab then
    for i,board in ipairs(session.doc.tabs) do
      if board.id==force_tab then session.active=i;break end
    end
    force_tab=nil
  end
  local board=active_tab()
  if not board then return end
  -- Legacy minimized-column state is not meaningful for single-page tabs.
  board.folded=false
  UI.tabs_strip()
  board=active_tab()
  if not board then return end
  board.folded=false
  local container_flags=ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoScrollWithMouse
  if ImGui.BeginChild(ctx,'active_page_panel',0,0,0,container_flags) then
    ImGui.PushID(ctx,board.id)
    local content_x=ImGui.GetCursorScreenPos(ctx)
    local content_w=ImGui.GetContentRegionAvail(ctx)
    local body_right=content_x+content_w
    local pad_x=ImGui.GetStyleVar(ctx,ImGui.StyleVar_WindowPadding)
    local safe_right=UI.board_actions_edge(body_right,pad_x)
    -- Prefer the same absolute action edge as the toolbar and page tabs,
    -- but never move native group/note controls into the scrollbar region.
    local actions_right=math.min(safe_right,UI.shared_actions_right or safe_right)
    if ImGui.BeginChild(ctx,'page_body',0,0,0,ImGui.WindowFlags_NoScrollbar) then
      -- A regular BeginChild has no top window padding. Without this inset
      -- the first group header touches the tab strip above it.
      if UI_METRICS.group_panel_top_padding>0 then
        local px,py=ImGui.GetCursorScreenPos(ctx)
        ImGui.SetCursorScreenPos(ctx,px,py+UI_METRICS.group_panel_top_padding)
      end
      ImGui.Indent(ctx,UI_METRICS.inner_gap)
      local placing=UI.place_valid(UI.place)
      for si,section in ipairs(board.columns) do
        ImGui.PushID(ctx,section.id)
        local sx,sy=ImGui.GetCursorScreenPos(ctx)
        local section_width=math.max(1,ImGui.GetContentRegionAvail(ctx))
        local placement_layer
        if placing then
          -- A dedicated outer splitter allows note marker layers to nest.
          -- The outline is behind contents/separators, so their edges stay
          -- intact even when a separator runs through a placement area.
          placement_layer=UI.marker_layer(section,UI.placement_layers)
          ImGui.DrawListSplitter_Split(placement_layer.splitter,2)
          ImGui.DrawListSplitter_SetCurrentChannel(placement_layer.splitter,1)
          ImGui.PushStyleVar(ctx,ImGui.StyleVar_DisabledAlpha,1)
          ImGui.BeginDisabled(ctx,true)
        end
        ImGui.BeginGroup(ctx)
        ImGui.BeginGroup(ctx)
        column_header(board,section,si,actions_right)
        ImGui.EndGroup(ctx)
        local _,header_bottom=ImGui.GetItemRectMax(ctx)
        local header_hovered=ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_AllowWhenBlockedByActiveItem)
        UI.section_hover(section,header_hovered)
        local note_rects={}
        -- Folded groups use their heading; expanded groups replace this with
        -- actual note-body geometry, measured BEFORE the trailing separator.
        local placement_visual={x=sx,y=sy,width=math.max(1,math.min(section_width,actions_right-sx)),bottom=header_bottom}
        if not section.folded then
          ImGui.Indent(ctx,UI_METRICS.inner_gap+UI_METRICS.note_row_inset_x)
          local body_x,body_y=ImGui.GetCursorScreenPos(ctx)
          local body_width=math.max(1,math.min(ImGui.GetContentRegionAvail(ctx),actions_right-body_x))
          ImGui.PushFont(ctx,font,size)
          local order=M.display_order(section,hide_completed,completed_last)
          for _,index in ipairs(order) do
            note_rects[#note_rects+1]=UI.note_row(board,section,
              section.blocks[index],index,actions_right)
            if section.reveal_note_id==section.blocks[index].id then
              ImGui.SetScrollHereY(ctx,0.5);section.reveal_note_id=nil
            end
          end
          if #order==0 then
            if #section.blocks>0 then ImGui.TextDisabled(ctx,tr('Completed items hidden')) end
            ImGui.Dummy(ctx,0,placing and UI_METRICS.empty_tab_placement_height or UI_METRICS.inner_gap)
            local _,empty_bottom=ImGui.GetItemRectMax(ctx)
            placement_visual={x=body_x,y=body_y,width=body_width,bottom=empty_bottom}
          else
            local first,last=note_rects[1],note_rects[#note_rects]
            placement_visual={x=first.x,y=first.y,width=first.width,bottom=last.bottom}
          end
          ImGui.PopFont(ctx)
          if not placing and not bulk_selection and not UI.note_drag_current() then
            -- A group-local action, independent of the active-group selector.
            -- The full hitbox is part of the group's measured height.
            local quick_x=ImGui.GetCursorScreenPos(ctx)
            local quick_width=math.max(0,math.min(body_width,actions_right-quick_x))
            UI.group_add_checkbox_button(section,quick_width,#order==0)
          end
          ImGui.Unindent(ctx,UI_METRICS.inner_gap+UI_METRICS.note_row_inset_x)
        end
        ImGui.EndGroup(ctx)
        local _,bottom=ImGui.GetItemRectMax(ctx)
        if placing then ImGui.EndDisabled(ctx);ImGui.PopStyleVar(ctx) end
        if not placing then UI.note_drop_section(section,note_rects) end
        if placing then
          ImGui.DrawListSplitter_SetCurrentChannel(placement_layer.splitter,0)
          UI.placement_target(section,sx,sy,section_width,bottom,'section',nil,placement_visual)
          ImGui.DrawListSplitter_Merge(placement_layer.splitter)
        end
        ImGui.PopID(ctx)
      end
      UI.note_drag_scroll()
      ImGui.Unindent(ctx,UI_METRICS.inner_gap)
      UI.overlay_scroll_thumb(board)
    end
    ImGui.EndChild(ctx) -- page_body, including clipped frames
    ImGui.PopID(ctx)
  end
  ImGui.EndChild(ctx) -- active_page_panel, including clipped frames
  if session.pending then local fn=session.pending;session.pending=nil;fn() end
end

local function draw_modal()
  -- A native modal must be explicitly closed when its owner/draft changes.
  -- This runs in a stable root ID scope even when the document epoch changes.
  if UI.editor_popup and UI.editor_popup.draft~=modal then
    if not UI.close_modal_if_open(UI.editor_popup.title) then return end
    UI.editor_popup=nil
  end
  if open_modal then ImGui.OpenPopup(ctx,open_modal);open_modal=nil end
  if not modal then return end
  local m=modal
  UI.editor_popup={draft=m,title=m.title}
  local width,height=UI.popup_dimensions(m.kind)
  if m.kind=='new_tab' or m.kind=='rename_column' then
    width,height=UI.name_geometry(m.title)
  elseif m.kind=='delete' then
    if not m.width then m.width,m.height=UI.confirm_geometry('Confirm deletion',m.message) end
    width,height=m.width,m.height
  end
  UI.place_popup(width,height)
  local border=themes[theme].dim
  ImGui.PushStyleColor(ctx,ImGui.Col_Border,border)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_PopupBorderSize,UI_METRICS.popup_border_size)
  local visible=ImGui.BeginPopupModal(ctx,m.title,nil,ImGui.WindowFlags_NoTitleBar|ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings)
  ImGui.PopStyleVar(ctx);ImGui.PopStyleColor(ctx)
  if visible then
    if UI.modal_cancelled(m) then
      ImGui.CloseCurrentPopup(ctx);modal=nil;ImGui.EndPopup(ctx);return
    end
    ImGui.Text(ctx,tr(m.kind=='delete' and 'Confirm deletion' or m.title));ImGui.Separator(ctx)
    local primary=m.kind=='delete' and 'Delete' or m.kind=='import' and 'Import' or m.kind=='restore' and 'Restore' or 'Apply'
    local enter=false
    local body_visible=UI.popup_body('editor_body',tr(primary))
    if body_visible then
      if m.kind=='restore' then
        ImGui.TextWrapped(ctx,tr('This replaces all notes of the current owner. Review the copy; it may contain an incomplete operation. Undo is available after restoration.'))
        ImGui.TextWrapped(ctx,UI.owner_title(session.target))
        ImGui.TextWrapped(ctx,m.path)
        ImGui.InputTextMultiline(ctx,'##restore_preview',m.raw,-1,-1,ImGui.InputTextFlags_ReadOnly)
      elseif m.kind=='new_tab' or m.kind=='rename_column' then
        if m.focus then ImGui.SetKeyboardFocusHere(ctx);m.focus=nil end
        ImGui.SetNextItemWidth(ctx,-1)
        enter,m.value=ImGui.InputText(ctx,'##name',m.value,ImGui.InputTextFlags_AutoSelectAll|ImGui.InputTextFlags_EnterReturnsTrue)
      elseif m.kind=='import' then
        local panes_w=ImGui.GetContentRegionAvail(ctx)
        if ImGui.BeginTable(ctx,'import_panes',2,ImGui.TableFlags_SizingStretchSame|ImGui.TableFlags_NoSavedSettings,
            panes_w,0) then
          ImGui.TableSetupColumn(ctx,'source',ImGui.TableColumnFlags_WidthStretch,1)
          ImGui.TableSetupColumn(ctx,'preview',ImGui.TableColumnFlags_WidthStretch,1)
          -- Each pair shares a native table row: wrapped hints and labels can
          -- grow without moving either editor independently.
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx,tr('Destination tab'))
          ImGui.SetNextItemWidth(ctx,-1)
          if ImGui.BeginCombo(ctx,'##import_column',m.column.name) then
            for _,column in ipairs(active_tab().columns) do
              if ImGui.Selectable(ctx,label(column.name)..'##destination'..column.id,m.column==column) then m.column=column end
            end
            ImGui.EndCombo(ctx)
          end
          local rv,value=UI.checkbox(ui_label('Remove numbering'),m.strip)
          if rv then m.strip=value;refresh_import_preview(m) end
          rv,value=UI.checkbox(ui_label('Split at timecodes'),m.timecodes)
          if rv then m.timecodes=value;refresh_import_preview(m) end
          -- One extra item gap separates the header from the panel labels.
          ImGui.Dummy(ctx,0,0)
          ImGui.TableNextColumn(ctx)
          ImGui.TextWrapped(ctx,tr('Paste text or a numbered list on the left. The notes to be added appear on the right.'))
          ImGui.TextWrapped(ctx,tr('Separate paragraphs with a blank line. In a numbered list, start each new item on a new line.'))
          if m.timecodes then
            ImGui.TextWrapped(ctx,tr('Timecodes: MM:SS, HH:MM:SS or HH:MM:SS:FF (project FPS); optional milliseconds without frames. Click the clock/time indicator to jump and focus arrange.'))
          end
          ImGui.Dummy(ctx,0,0)
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          ImGui.Text(ctx,tr('Source text'))
          ImGui.TableNextColumn(ctx)
          ImGui.TextDisabled(ctx,tr('Preview: %d notes'):format(#m.preview))
          ImGui.TableNextRow(ctx)
          ImGui.TableNextColumn(ctx)
          local _,remaining_h=ImGui.GetContentRegionAvail(ctx)
          -- Let the table fit its rows; leave only the normal trailing item gap.
          local pane_h=math.max(UI_METRICS.import_pane_min_height,math.floor(remaining_h-UI_METRICS.item_gap_y))
          rv,value=UI.import_source(m,pane_h)
          if rv then m.value=value;refresh_import_preview(m) end
          ImGui.TableNextColumn(ctx)
          if ImGui.BeginChild(ctx,'import_preview',0,pane_h,ImGui.ChildFlags_Borders) then
            if #m.preview==0 then
              -- Use the raw style value and capture only its first return.
              -- Lua expands all returns from a call in the last argument slot.
              local hint_color=ImGui.GetStyleColor(ctx,ImGui.Col_TextDisabled)
              ImGui.PushStyleColor(ctx,ImGui.Col_Text,hint_color)
              ImGui.TextWrapped(ctx,tr('Paste text to see the resulting notes.'))
              ImGui.PopStyleColor(ctx)
            end
            for i,text in ipairs(m.preview) do ImGui.TextWrapped(ctx,i..'. '..text);ImGui.Separator(ctx) end
          end
          ImGui.EndChild(ctx)
          ImGui.EndTable(ctx)
        end
      elseif m.kind=='delete' then
        ImGui.TextWrapped(ctx,tr(m.message))
      elseif m.kind=='select' then
        ImGui.Text(ctx,tr('Field name'))
        if m.focus then ImGui.SetKeyboardFocusHere(ctx);m.focus=nil end
        ImGui.SetNextItemWidth(ctx,-1)
        local rv,value=ImGui.InputText(ctx,'##field_name',m.label)
        if rv then m.label=value end
        ImGui.TextWrapped(ctx,tr('Options (select a circle to set the current value)'))
        local _,add_h=UI.button_size(tr('+ Option'))
        local _,available_h=ImGui.GetContentRegionAvail(ctx)
        if ImGui.BeginChild(ctx,'options',0,math.max(UI_METRICS.options_panel_min_height,available_h-add_h-UI_METRICS.item_gap_y),ImGui.ChildFlags_Borders) then
          local action
          for i,option in ipairs(m.options) do
            ImGui.PushID(ctx,i)
            if ImGui.RadioButton(ctx,'##selected',m.selected==i) then m.selected=i end
            ImGui.SameLine(ctx)
            local available=ImGui.GetContentRegionAvail(ctx)
            local delete_w=UI.button_size(tr('X'))
            local actions_w=math.max(UI_METRICS.option_actions_reserved_width,
              2*ImGui.GetFrameHeight(ctx)+delete_w+3*UI_METRICS.item_gap_x)
            ImGui.SetNextItemWidth(ctx,math.max(1,math.min(available,
              math.max(UI_METRICS.option_input_min_width,available-actions_w))))
            rv,value=ImGui.InputText(ctx,'##option',option)
            if rv then m.options[i]=value end
            ImGui.SameLine(ctx)
            if ImGui.ArrowButton(ctx,'up',ImGui.Dir_Up) then action=function()M.move_option(m,i,-1)end end
            ImGui.SameLine(ctx)
            if ImGui.ArrowButton(ctx,'down',ImGui.Dir_Down) then action=function()M.move_option(m,i,1)end end
            ImGui.SameLine(ctx);ImGui.BeginDisabled(ctx,#m.options<=1)
            if UI.button(ctx,ui_label('X')) then action=function()M.remove_option(m,i)end end
            ImGui.EndDisabled(ctx);ImGui.PopID(ctx)
          end
          if action then action() end
        end
        ImGui.EndChild(ctx)
        if UI.button(ctx,ui_label('+ Option')) then m.options[#m.options+1]=tr('New option') end
      end
    end
    ImGui.EndChild(ctx) -- editor_body, including clipped frames
    -- The action row belongs to the popup, outside its scrollable body.
    local valid=true
    if m.kind=='new_tab' or m.kind=='rename_column' then valid=m.value:match('%S')~=nil
    elseif m.kind=='import' then valid=#m.preview>0
    elseif m.kind=='select' then
      valid=m.label:match('%S')~=nil
      for _,option in ipairs(m.options) do if not option:match('%S') then valid=false end end
    end
    local done=false
    ImGui.BeginDisabled(ctx,not valid)
    local apply=UI.button(ctx,ui_label(primary))
    if valid and (apply or enter) then
      if m.kind=='new_tab' then
        local t=M.tab(m.value,'');session.doc.tabs[#session.doc.tabs+1]=t
        session.active=#session.doc.tabs;force_tab=t.id
      elseif m.kind=='restore' then
        session.doc=m.document;session.active=1;force_tab=session.doc.tabs[1].id
        session.error=nil;session.history_readonly=nil;session.restore_pending=true
      elseif m.kind=='rename_column' then m.target.name=m.value
      elseif m.kind=='import' then
        m.column.folded=false
        local fps,drop_frame=project_timecode_settings()
        for _,text in ipairs(m.preview) do
          local block=M.note(text)
          -- Save positive metadata for compatibility; never suppress badges
          -- just because import-time splitting was disabled.
          if m.timecodes and M.timecode_prefix(text,fps,drop_frame)~=nil then block.timecode=true end
          m.column.blocks[#m.column.blocks+1]=block
        end
      elseif m.kind=='delete' then m.action();edit_action=m.history_action
      elseif m.kind=='select' then
        m.target.label=m.label;m.target.options=m.options;m.target.selected=m.selected
      end
      if m.kind~='delete' then
        local action=({new_tab='add_tab',rename_column='rename_column',import='import',select='edit_dropdown',restore='restore'})[m.kind]
        if m.kind=='rename_column' then
          action=m.title=='Rename group' and 'rename_group' or m.title=='Rename tab' and 'rename_tab' or action
        end
        touch(nil,action)
      end
      undo_boundary=true;done=true
    end
    ImGui.EndDisabled(ctx)
    ImGui.SameLine(ctx)
    if UI.button(ctx,ui_label('Cancel')) then done=true end
    if done then ImGui.CloseCurrentPopup(ctx);modal=nil end
    ImGui.EndPopup(ctx)
  end
  if not visible and not ImGui.IsPopupOpen(ctx,m.title) then modal=nil end
end
-- Independent confirmation avoids discarding the note draft when the
-- ordinary document modal temporarily invalidates the active text widget.
local function draw_note_cancel_popup()
  local title='Discard note changes?###note_cancel'
  local prompt=UI.note_cancel_prompt
  if prompt and (prompt.edit~=UI.note_edit or prompt.edit.owner~=session) then
    UI.note_cancel_prompt=nil;prompt=nil
  end
  -- Lua state can disappear on owner change, external reload or another
  -- modal. Close the corresponding native popup in its stable root scope.
  if UI.note_cancel_window and UI.note_cancel_window~=prompt then
    if not UI.close_modal_if_open(title) then return end
    UI.note_cancel_window=nil
  end
  if not prompt then return end
  local opening=prompt.open
  if opening then
    ImGui.OpenPopup(ctx,title);prompt.open=false;UI.note_cancel_window=prompt
  end
  local width,height=UI.popup_dimensions('note_cancel')
  UI.place_popup(width,height)
  if ImGui.BeginPopupModal(ctx,title,nil,
      ImGui.WindowFlags_NoTitleBar|ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings) then
    ImGui.Text(ctx,tr('Discard note changes?'))
    ImGui.Separator(ctx)
    ImGui.TextWrapped(ctx,tr('The note has unsaved changes. Discard them?'))
    ImGui.Spacing(ctx)
    local discard=UI.button(ctx,ui_label('Discard changes'))
    ImGui.SameLine(ctx)
    local keep=UI.button(ctx,ui_label('Continue editing')) or (escape_pressed and not opening)
    if discard then
      ImGui.CloseCurrentPopup(ctx);UI.note_cancel_window=nil
      UI.end_note_edit(true)
    elseif keep then
      ImGui.CloseCurrentPopup(ctx);UI.note_cancel_window=nil
      UI.note_cancel_prompt=nil
      local edit=UI.note_edit
      if edit then
        edit.focus=true
        if edit.source_editor then
          edit.source_editor.focused=true;edit.source_editor.focus_pending=true
        end
      end
    end
    ImGui.EndPopup(ctx)
  elseif not ImGui.IsPopupOpen(ctx,title) then
    UI.note_cancel_prompt=nil;UI.note_cancel_window=nil
  end
end
local function problem_view()
  ImGui.TextWrapped(ctx,UI.message(session.error or 'Native notes changed while this draft was being edited. Automatic writing is paused.'))
  if session.recovery then
    if session.recovery.folder then
      ImGui.TextWrapped(ctx,tr('Recovery copies: ')..session.recovery.folder)
      if UI.button(ctx,ui_label('Copy recovery path')) then ImGui.SetClipboardText(ctx,session.recovery.folder) end
    end
    if #session.recovery.errors>0 then ImGui.TextWrapped(ctx,tr('Recovery export failed. See the REAPER console.')) end
  end
  local raw=session.doc and M.serialize(session.doc) or session.raw
  if UI.button(ctx,ui_label(session.doc and 'Copy local draft' or 'Copy original notes')) then ImGui.SetClipboardText(ctx,raw) end
  ImGui.SameLine(ctx)
  if UI.button(ctx,ui_label('Reload native notes...')) then
    if reaper.MB(language=='ru' and 'Отбросить локальные правки и перечитать сохранённые заметки этого объекта?\nЕсли черновик нужен, сначала скопируй его.' or 'Discard the local view and reload the saved notes for this object?\nCopy the local draft first if you need to keep it.',TITLE,4)==6 then
      load_notes(session,api.read(session.target))
    end
  end
  if not session.doc and UI.button(ctx,ui_label('Open original as plain text...')) then
    if reaper.MB(language=='ru' and 'Поместить весь исходный текст в новый блок?\nДанные не будут удалены. Сохранённые заметки изменятся только после следующей правки.' or 'Keep the complete original text in a new text block?\nNo data will be removed. The native notes will change only after your next edit.',TITLE,4)==6 then
      session.doc=M.plain(session.raw); session.error=nil
      -- The first subsequent edit must be undoable to the exact unsupported
      -- or damaged original, using the same guarded path as recovery Undo.
      session.history_readonly=true; epoch=epoch+1
    end
  end
  ImGui.InputTextMultiline(ctx,'##recovery',raw,-1,-1,ImGui.InputTextFlags_ReadOnly)
end
local function scope_selector()
  local row={width=ImGui.GetContentRegionAvail(ctx),used=0}
  local scope_width=UI_METRICS.scope_min_width
  for _,kind in ipairs({'project','track','item'}) do
    scope_width=math.max(scope_width,ImGui.CalcTextSize(ctx,tr(scope_labels[kind]))+
      ImGui.GetFrameHeight(ctx)+2*UI_METRICS.frame_pad_x)
  end
  UI.toolbar_next(row,scope_width)
  ImGui.SetNextItemWidth(ctx,scope_width)
  local switched=false
  if ImGui.BeginCombo(ctx,'##note_scope',tr(scope_labels[scope])) then
    for _,kind in ipairs({'project','track','item'}) do
      if ImGui.Selectable(ctx,tr(scope_labels[kind])..'###scope_'..kind,scope==kind) and scope~=kind then
        scope=kind; pref('scope',kind); switched=true
      end
    end
    ImGui.EndCombo(ctx)
  end
  -- Exactly the same native SliderInt style/number placement as the
  -- separator-spacing control; the formatted value stays inside the track.
  local label_w=ImGui.CalcTextSize(ctx,tr('Font'))
  local gap=UI_METRICS.inner_gap
  local slider_w=math.max(UI_METRICS.font_slider_min_width,
    math.min(UI_METRICS.slider_width,row.width-label_w-gap))
  UI.toolbar_right(row,label_w+gap+slider_w)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx,tr('Font'));ImGui.SameLine(ctx,0,gap)
  ImGui.SetNextItemWidth(ctx,slider_w)
  local rv,value=ImGui.SliderInt(ctx,'##font_size',size,
    UI_METRICS.note_text_min_size,UI_METRICS.note_text_max_size,'%d px')
  if rv then size=value;pref('size',size) end
  return switched
end
local function header_context()
  local x,y=ImGui.GetWindowPos(ctx)
  local w=ImGui.GetWindowWidth(ctx)
  local _,bottom=ImGui.GetCursorScreenPos(ctx)
  local mx,my=ImGui.GetMousePos(ctx)
  local dock=ImGui.GetWindowDockID(ctx)
  if dock<0 and dock~=last_docker then last_docker=dock; pref('last_docker',dock) end
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseReleased(ctx,1)
      and mx>=x and mx<=x+w and my>=y and my<bottom then ImGui.OpenPopup(ctx,'header_context') end
  if begin_action_popup('header_context') then
    if ImGui.MenuItem(ctx,ui_label('Dock to docker'),nil,dock~=0) then dock_request=dock~=0 and 0 or last_docker end
    ImGui.EndPopup(ctx)
  end
end
local function frame()
  frame_checkpoint=nil
  changed=false; undo_boundary=false; edit_key=nil; edit_action=nil; history_request=nil
  if not sync_project() then return false end
  if bulk_selection and (bulk_selection.owner~=session or not session or not session.doc or session.error or session.conflict) then bulk_selection=nil end
  if bulk_selection then
    local board=M.note_column(session.doc,bulk_selection.column)
    if not board or board.folded or bulk_selection.column.folded then bulk_selection=nil end
  end
  if UI.place and not UI.place_valid(UI.place) then UI.place=nil;UI.place_cancelled=true end
  if pending_language then
    language=pending_language;pending_language=nil;pref('language',language)
    modal=nil;open_modal=nil;UI.info=nil;UI.menu_open=nil
  end
  if pending_theme then
    theme=pending_theme;pending_theme=nil;pref('theme',theme)
  end
  if UI.note_edit and not UI.note_edit_valid(UI.note_edit) then UI.end_note_edit() end
  if not UI.input_focus_valid(UI.new_input) then UI.new_input=nil end
  local before=session and {raw=session.raw,active=session.active,allow_invalid=session.history_readonly} or nil
  frame_checkpoint=session and {session=session,raw=session.raw} or nil
  if session and not session.error and not session.conflict then
    session.write_attempt=nil;session.write_stage=nil
  end
  if not ctx then
    ctx=ImGui.CreateContext(CONTEXT_NAME,ImGui.ConfigFlags_DockingEnable|ImGui.ConfigFlags_NavEnableKeyboard)
    ImGui.SetConfigVar(ctx,ImGui.ConfigVar_InputTextCursorBlink,1)
    font=ImGui.CreateFont(UI_METRICS.font_family)
    ImGui.Attach(ctx,font)
    -- A real bold face (not a duplicated text shadow) for column names.
    heading_bold_font=ImGui.CreateFont(UI_METRICS.font_family,ImGui.FontFlags_Bold)
    ImGui.Attach(ctx,heading_bold_font)
    input_callback=ImGui.CreateFunctionFromEEL('seen=1; cursor=CursorPos; first=SelectionStart; last=SelectionEnd;')
    ImGui.Attach(ctx,input_callback)
  end
  ui_font=ImGui.GetFont(ctx)
  UI_METRICS.font_size=ImGui.GetFontSize(ctx)
  local warming=startup_layout_frames<STARTUP_LAYOUT_FRAMES
  -- A tiny nonzero alpha quantizes to transparent, but still allows ImGui to
  -- measure children (Alpha==0 may skip their layout). Viewer startup pattern.
  if warming then ImGui.PushStyleVar(ctx,ImGui.StyleVar_Alpha,UI_METRICS.startup_layout_warmup_alpha) end
  local nc,nv=styles()
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  ImGui.SetNextWindowSize(ctx,UI_METRICS.window_initial_width,UI_METRICS.window_initial_height,ImGui.Cond_Once)
  ImGui.SetNextWindowSizeConstraints(ctx,UI_METRICS.window_min_width,UI_METRICS.window_min_height,10000,10000)
  if dock_request~=nil then ImGui.SetNextWindowDockID(ctx,dock_request,ImGui.Cond_Always); dock_request=nil end
  local project=reaper.EnumProjects(-1,'')
  local project_name=project and reaper.GetProjectName(project,'') or ''
  local window_title=TITLE..' — '..(project_name~='' and label(project_name) or tr('Untitled project'))
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,UI_METRICS.menu_bar_pad_x,math.max(0,(UI_METRICS.menu_bar_height-ImGui.GetTextLineHeight(ctx))*0.5))
  local visible,opened=ImGui.Begin(ctx,window_title..'###Patch34ProjectNotes',true,ImGui.WindowFlags_MenuBar)
  ImGui.PopStyleVar(ctx)
  if visible then
    -- Invalidate active text widgets after external reload/project switch.
    ImGui.PushID(ctx,epoch)
    escape_pressed=ImGui.IsKeyPressed(ctx,ImGui.Key_Escape,false)
    UI.note_drag_update()
    UI.place_update()
    UI.note_edit_update()
    if not ImGui.IsMouseDown(ctx,0) and not ImGui.IsMouseReleased(ctx,0) then
      UI.double_press=nil;UI.column_press=nil;UI.timecode_press=nil
    end
    if warming then ImGui.BeginDisabled(ctx,true) else history_shortcuts() end
    menu_bar()
    local switching=scope_selector()
    if switching or history_request or modal or UI.info then UI.end_note_edit() end
    header_context()
    if switching then UI.place=nil else UI.creation_toolbar() end
    if switching then ImGui.TextDisabled(ctx,tr('Switching note owner...'))
    elseif not session then ImGui.TextWrapped(ctx,UI.message(selection_message or 'Select an object in REAPER.'))
    elseif session.error or session.conflict then problem_view()
    else
      if session.target.kind~='project' then ImGui.TextWrapped(ctx,UI.owner_title(session.target)) end
      draw_document()
    end
    if UI.end_edit_after_frame==UI.note_edit and UI.note_edit then UI.end_note_edit() end
    if UI.note_edit and not UI.note_edit_valid(UI.note_edit) then UI.end_note_edit() end
    UI.info_window()
    if warming then ImGui.EndDisabled(ctx) end
    ImGui.PopID(ctx)
    draw_modal()
    draw_note_cancel_popup()
  end
  ImGui.End(ctx) -- Begin requires End even when the window is collapsed
  if not opened and UI.note_edit then UI.end_note_edit() end
  ImGui.PopFont(ctx); ImGui.PopStyleVar(ctx,nv); ImGui.PopStyleColor(ctx,nc)
  if warming then
    -- Count collapsed attempts too, so a restored collapsed window cannot
    -- remain transparent indefinitely.
    startup_layout_frames=startup_layout_frames+1
    ImGui.PopStyleVar(ctx)
  end
  if changed and session then
    session.dirty=true
    local ok,err=M.write(session,api)
    if not ok then
      session.error=err;save_recovery(session,err,before and before.raw)
    else
      if session.restore_pending then before.allow_invalid=true;session.restore_pending=nil end
      session.history_readonly=nil
      M.history_record(session.history,before,session.raw,edit_key,reaper.time_precise(),edit_action)
      session.undo_due=reaper.time_precise()+0.8
    end
  end
  if session and (undo_boundary or not UI.note_edit) then session.history.key=nil end
  if session and (undo_boundary or (session.undo_due and reaper.time_precise()>=session.undo_due)) then flush_undo(session) end
  if history_request and can_history(history_request) then
    flush_undo(session)
    local ok,err=M.history_step(session,api,history_request)
    if ok then
      epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; session.pending=nil
      force_tab=session.doc and active_tab().id or nil
      reaper.Undo_OnStateChangeEx2(session.proj,history_request<0 and 'Undo '..session.target.kind..' notes' or 'Redo '..session.target.kind..' notes',session.target.undo_flags,-1)
    elseif err then
      session.error=err;save_recovery(session,err,before and before.raw)
    end
  end
  return opened
end
local function exit()
  if crashed then return end
  -- REAPER can terminate a deferred script without another drawing frame.
  -- Export changed note/dialog drafts; never write native notes on shutdown.
  local handled={}
  local function finish(s)
    if not s or handled[s] then return end
    handled[s]=true
    pcall(save_pending_recovery,s,'Script exited during an active draft / Закрытие во время редактирования черновика')
    if s.dirty and not s.recovery then pcall(save_recovery,s,'Closed with an unsaved draft / Закрыто с несохранённым черновиком') end
    pcall(flush_undo,s)
  end
  finish(session)
  finish(UI and UI.note_edit and UI.note_edit.owner)
  for _,s in pairs(sessions) do finish(s) end
end
reaper.atexit(exit)
local function loop()
  local ok,keep=xpcall(frame,debug.traceback)
  if not ok then
    crashed=true
    -- The UI/model may be halfway through an operation. Never write it to the
    -- project, track or item here, and never retry an ambiguous host write.
    local handled={}
    local function recover(s)
      if not s or handled[s] then return end
      handled[s]=true
      local baseline=frame_checkpoint and frame_checkpoint.session==s and frame_checkpoint.raw or s.raw
      pcall(save_recovery,s,keep,baseline,UI.recovery_pending(s))
    end
    recover(session)
    recover(UI.note_edit and UI.note_edit.owner)
    for _,s in pairs(sessions) do if s.dirty then recover(s) end end
    pcall(reaper.ShowConsoleMsg,TITLE..' v'..VERSION..'\n'..tostring(keep)..'\n')
    local first_line=tostring(keep):match('^([^\n]*)') or tostring(keep)
    local message=language=='ru' and
      'Скрипт остановлен. Аварийной записи в заметки не было.\n\nОшибка: '..first_line:sub(1,600)..'\n\nПолный стек — в консоли и report.txt аварийной копии.' or
      'The script stopped. Recovery did not write native notes.\n\nError: '..first_line:sub(1,600)..'\n\nFull stack: console and recovery report.txt.'
    pcall(reaper.MB,message,TITLE,0)
    return
  end
  if keep then reaper.defer(loop) end
end
reaper.defer(loop)
