-- @description ReaNotepad
-- @version 0.5.4
-- @author Aleksei Vorobev / Patch34
-- @about
--   Structured notes for REAPER projects, tracks and items.
--   Tabs, columns, text, completion checkboxes and editable dropdown fields.
--   Import appends to a chosen column as one undoable edit; preview before adding.
--   @note 0/1 ... @end extends v2 with multiline checkbox notes.
--   Older script versions reject these new blocks without overwriting them.
--   Dropdowns stay at 420px when space allows and shrink to fit narrow columns.
--   Visible blinking text caret; double-click a tab to rename it in place.
--   Enter / click outside applies a tab name; Esc cancels. Column names use a dialog.
--   Requires REAPER 7 and ReaImGui 0.10+ (install through ReaPack).
--   Install: Actions > Show action list > New action > Load ReaScript.
--
--   Design palette adapted from Podcast HTML/DOCX Script Viewer v3.1.0-beta.1.
--   The original viewer is not modified and is not required at runtime.
--
--   STORAGE: Project notes use native GetSetProjectNotes. Item notes use P_NOTES.
--   Track notes use P_EXT:PATCH34_PROJECT_NOTES, stored with the track in the RPP.
--   No SWS dependency. Normal notes have no sidecar files.
--   On errors only, recovery copies go to REAPER/Data/Patch34_Project_Notes_Recovery.
--   Edit > Open recovery copy previews a .notes file before explicit restoration.
--   Recovery copies can contain an incomplete operation; inspect before restoring.
--   Track notes do not use SWS Track Notes.
--   Appearance preferences and the chosen scope use global ExtState.
--   Choose Project / Track / Item at the top. Track and Item modes require exactly
--   one selected object (master track supported). Existing item notes are imported
--   without writing until the first edit. Switching owner cancels unapplied drafts.
--   Each object has its own tabs, columns and session Undo/Redo history.
--   Owner pointers and GUIDs are checked before writes; deletion never redirects
--   notes to another object. Save the project to keep all object notes on disk.
--   Changes update the open project immediately; save the RPP to persist to disk.
--   Existing plain notes are imported into the first tab without writing anything
--   until the first edit. Native notes remain readable as a small text format.
--   v1 notes migrate to the first column; opening alone does not rewrite them.
--   v2 stores columns with @column/@endcolumn inside @tab/@endtab.
--   Do not remove structural markers when editing natively.
--   Malformed/unsupported structured notes open read-only, never auto-repaired.
--   A native edit is reloaded automatically; a write conflict is never overwritten.
--
--   USE: Tab menu adds/renames/reorders/deletes tabs. Add > Column adds a column.
--   Each column has quick actions for text, checkbox notes, dropdowns and import.
--   Hover an icon for its localized description; column properties use the ... menu.
--   Column properties enable multiple selection; block properties set color markers.
--   Bulk deletion/color changes are undoable. Marker metadata uses @color in v2.
--   Older scripts open colored documents read-only; remove markers before downgrading.
--   Block actions can move widgets between columns. Up to 8 columns per tab.
--   Drag a vertical column boundary to redistribute the available width.
--   Columns fit the window; their relative widths are retained during this session.
--   Undo/Redo: Edit menu, Ctrl/Cmd+Z and Ctrl/Cmd+Shift+Z (also Ctrl/Cmd+Y).
--   History includes all content/structure edits and groups continuous typing.
--   Each note owner has a separate session history, capped at 100 entries / 16 MiB
--   per stack (at least one snapshot retained). History resets after native edits
--   or a script restart. Appearance preferences are not part of document history.
--   Popup drafts use native input Undo until Apply commits one document edit.
--   Esc or a click outside a popup discards its unapplied draft.
--   Edit mode exposes text and checkbox labels. Read mode wraps text to page width.
--   Dropdown values remain clickable in either mode; Edit... changes field names,
--   option names/order and adds/removes options. Each block has an actions menu.
--   The native multiline editor has horizontal scrolling, not soft word wrapping.
--   This is a plain-text block editor, not the source viewer's HTML/DOCX renderer.
--
--   VALIDATION: syntax, serializer/parser, storage guards and simulated UI paths
--   tested outside REAPER. Native window rendering and REAPER undo need a host test.
--   API references: https://www.reaper.fm/sdk/reascript/reascripthelp.html
--                   https://cfillion.ca/reaper_imgui_doc.html
--                   https://github.com/cfillion/reaimgui/blob/master/examples/demo.lua

local M = {}
local HEADER = '# Patch34 Project Notes v2'
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
function M.visible(b,hide) return not (hide and (b.kind=='check' or b.kind=='note') and b.checked) end
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
function M.import_text(raw,strip)
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
  local parsed,sequence={},{}
  local has_blank,has_numbers=false,false
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
  local result,part,marker={},{},nil
  local function flush()
    local value=trim(table.concat(part,'\n'));part={}
    if value=='' and marker then value=marker end
    marker=nil
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
    else
      if not has_blank and not has_numbers then flush() end
      part[#part+1]=line
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
function M.plain(raw) return {tabs={M.tab('Notes', raw)}} end
function M.serialize(doc)
  local out = {HEADER}
  for _,tab in ipairs(doc.tabs) do
    out[#out+1] = '@tab ' .. esc(tab.name)
    for _,column in ipairs(tab.columns) do
      out[#out+1] = '@column ' .. esc(column.name)
      for _,b in ipairs(column.blocks) do
      assert(M.valid_marker(b.color),'Invalid color marker.')
      if b.color then out[#out+1]='@color '..b.color end
      if b.kind == 'text' or b.kind == 'note' then
        out[#out+1] = b.kind=='note' and ('@note '..(b.checked and '1' or '0')) or '@text'
        for _,l in ipairs(lines(b.text)) do
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
  if header ~= HEADER and not legacy then
    if normalized:match('^# Patch34 Project Notes v') then
      return nil, 'Unsupported notes format. Original notes were not changed.'
    end
    return M.plain(raw)
  end
  local ok, result = pcall(function()
    local ls, doc, tab, column, i = lines(normalized), {tabs={}}, nil, nil, 2
    local pending_color
    while i <= #ls do
      local l = ls[i]
      local before_blocks=column and #column.blocks or 0
      if l:sub(1,5) == '@tab ' and not tab then
        tab = M.tab(unesc(l:sub(6))); doc.tabs[#doc.tabs+1] = tab
        if legacy then column=tab.columns[1] else tab.columns={} end
      elseif l:sub(1,8) == '@column ' and tab and not column and not legacy then
        column=M.column(unesc(l:sub(9))); tab.columns[#tab.columns+1]=column
      elseif l == '@endcolumn' and column and not legacy then
        assert(not pending_color,'Color marker has no block.');column=nil
      elseif l == '@endtab' and tab then
        assert(not pending_color,'Color marker has no block.')
        assert(legacy or not column, 'Unclosed column.')
        assert(#tab.columns>0, 'Tab has no columns.')
        assert(#tab.columns<=8, 'A tab supports up to 8 columns.')
        tab=nil; column=nil
      elseif l:match('^@color ') and column and not legacy then
        local key=l:sub(8)
        assert(not pending_color and M.valid_marker(key),'Invalid or repeated color marker.')
        pending_color=key
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
        column.blocks[#column.blocks].color=pending_color;pending_color=nil
      end
      i = i + 1
    end
    assert(not pending_color,'Color marker has no block.')
    assert(not tab, 'Unclosed tab.')
    assert(#doc.tabs>0, 'Document has no tabs.')
    return doc
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
  if written==false then session.write_stage='rejected';return false,write_error or 'REAPER could not write these notes.' end
  session.write_stage='verifying'
  local actual = api.read(owner)
  -- Native editors may normalize EOLs or add a newline after @endtab.
  -- Trailing text-block newlines remain inside @text/@end and are significant.
  local same = norm(actual) == norm(next_raw)
  if not same and (next_raw:sub(1,#HEADER)==HEADER or next_raw:sub(1,#LEGACY_HEADER)==LEGACY_HEADER) then
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
  return M.write_raw(session,api,M.serialize(session.doc))
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
    if t.kind=='item' then return r.GetSetMediaItemInfo_String(t.obj,'P_NOTES',value,true) end
    return r.GetSetMediaTrackInfo_String(t.obj,A.track_field,value,true)
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
          '\n\nOptions / Варианты:\n'..table.concat(pending.options,'\n')
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
  s.doc=nil;s.suspended=true;s.input_state=nil
  s.write_attempt=nil;s.write_stage=nil;s.history.key=nil
  return true
end
function M.resume_session(s)
  if not s.suspended then return true end
  local doc,err=M.parse(s.raw)
  if not doc then return false,err end
  s.doc=doc;s.suspended=nil
  s.active=math.min(s.active or 1,#doc.tabs)
  return true
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
local STARTUP_LAYOUT_FRAMES=2
local ctx, font, ui_font, input_callback
local sessions, session, modal, open_modal = {}, nil, nil, nil
local session_sweep={cursor=nil}
local SESSION_CHECKS_PER_FRAME=8
local REPOSITORY_URL='https://github.com/patch-34/reanotepad'
local epoch, changed, undo_boundary, force_tab = 0, false, false, nil
local edit_key, edit_action, history_request
local tab_rename, escape_pressed = nil, false
local bulk_selection
local frame_checkpoint, crashed, recovery_sequence = nil, false, 0
-- Shared layout metrics. Viewer button/slider geometry is retained; spacing
-- between groups is separate from spacing inside a control or between rows.
local UI_METRICS = {
  font_size=13, window_pad_x=12, window_pad_y=10,
  frame_pad_x=6, frame_pad_y=3, item_gap_x=8, item_gap_y=8,
  group_gap=16, inner_gap=8, checkbox_label_gap=6,
  scope_min_width=110, slider_width=140, slider_min_width=64,
  button_pad_x=8, button_pad_y=3, button_min_height=23,
  compact_button_pad_x=10, checkbox_pad_y=1,
  column_name_min_width=60, button_rounding=3,
  slider_row_height=22, slider_knob_radius=6, slider_outline=1.5,
  slider_track_height=3, slider_circle_segments=24, slider_outline_normal=1.2,
  dropdown_width=420,
  confirm_min_width=280, confirm_max_width=520,
  read_line_gap=2, popup_margin=12, popup_footer_gap=8,
  popup_sizes={restore={580,460},name={410,150},select={500,460},import={860,440},about={360,210}},
}
local language=reaper.GetExtState(PREF,'language')=='ru' and 'ru' or 'en'
local pending_language, pending_theme
local RU = {
  ["Select elements..."]="Выделить элементы…",
  ["Selected: %d"]="Выбрано: %d",
  ["All"]="Все", ["Clear selection"]="Снять",
  ["Color..."]="Цвет…", ["Color marker"]="Цветовая метка",
  ["No marker"]="Без метки", ["Red"]="Красная", ["Orange"]="Оранжевая",
  ["Yellow"]="Жёлтая", ["Green"]="Зелёная", ["Blue"]="Синяя", ["Purple"]="Фиолетовая",
  ["Done"]="Готово",
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
  ["Destination column"]="Колонка для импорта",
  ["Paste text to see the resulting notes."]="Вставь текст, чтобы увидеть будущие заметки.",
  ["Undo"]="Отменить",
  ["Redo"]="Повторить",
  ["New tab"]="Новая вкладка",
  ["Rename"]="Переименовать",
  ["Move left"]="Сдвинуть влево",
  ["Move right"]="Сдвинуть вправо",
  ["Delete tab..."]="Удалить вкладку…",
  ["Column"]="Колонка",
  ["Edit mode"]="Режим редактирования",
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
  ["Edit notes"]="Редактировать",
  ["Rename column..."]="Переименовать колонку…",
  ["Move column left"]="Колонку влево",
  ["Move column right"]="Колонку вправо",
  ["Delete column..."]="Удалить колонку…",
  ["Hide completed"]="Скрыть выполненные",
  ["Font"]="Шрифт",
  [" px"]=" пкс",
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
  ["Preview: %d notes"]="Предпросмотр: заметок — %d",
  ["Field name"]="Название поля",
  ["Options (select a circle to set the current value)"]="Варианты (отметь кружком текущее значение)",
  ["Edit dropdown"]="Редактирование списка",
  ["Rename column"]="Название колонки",
  ["Delete item?"]="Удалить элемент?",
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
local size = math.max(12,math.min(32,tonumber(reaper.GetExtState(PREF,'size')) or 16))
local hide_completed=reaper.GetExtState(PREF,'hide_completed')=='1'
local dock_request
local last_docker=tonumber(reaper.GetExtState(PREF,'last_docker')) or -1
if last_docker>-1 or last_docker< -16 then last_docker=-1 end
local editing = reaper.GetExtState(PREF,'editing') ~= '0'
local scope=reaper.GetExtState(PREF,'scope')
if scope~='track' and scope~='item' then scope='project' end
local scope_labels={project='Project',track='Track',item='Item'}
local selection_message
local api=M.storage(reaper)
local function rgba(r,g,b,a) return (r<<24)|(g<<16)|(b<<8)|(a or 255) end
-- Viewer color roles are the only palette definitions. Native tabs/checks
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
      'ReaNotepad 0.5.4 — recovery / аварийная копия',
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
      'pending.txt: unapplied popup or rename text / неприменённый текст окна или переименования.',
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

local function load_notes(s,raw)
  s.raw=raw; s.doc,s.error=M.parse(raw); s.dirty=false; s.conflict=nil; s.undo_due=nil
  s.active=math.min(s.active or 1,s.doc and #s.doc.tabs or 1)
  s.history=M.history_new(); s.pending=nil;s.input_state=nil;s.suspended=nil
  s.recovery=nil;s.write_attempt=nil;s.write_stage=nil
  s.history_readonly=nil;s.restore_pending=nil
  epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; tab_rename=nil
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
  -- The selected/previous owner never waits for the background sweep.
  if session and not api.valid(session.target) then
    discard_removed_session(session);sessions[session.target.key]=nil;session=nil
    epoch=epoch+1; bulk_selection=nil;modal=nil;open_modal=nil;tab_rename=nil;force_tab=nil
  end
  local chosen=target and sessions[target.key]
  if chosen and chosen~=session and not api.valid(chosen.target) then
    discard_removed_session(chosen);sessions[target.key]=nil
  end
  M.sweep_sessions(sessions,session_sweep,session,api.valid,discard_removed_session,SESSION_CHECKS_PER_FRAME)
  if not target then
    if session then
      flush_undo(session);M.suspend_session(session);session=nil
      epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; tab_rename=nil; force_tab=nil
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
    epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; tab_rename=nil; force_tab=nil
  end
  local native=api.read(session.target)
  if not session.dirty and native~=session.raw then load_notes(session,native)
  elseif session.dirty and native~=session.raw then session.conflict=native
  elseif session.suspended then
    local ok,err=M.resume_session(session)
    if not ok then session.error=err end
  end
  return true
end
local function request_modal(m)
  if session then session.history.key=nil;session.input_state=nil end
  tab_rename=nil
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
local function begin_tab_rename(tab)
  session.history.key=nil;session.input_state=nil
  tab_rename={target=tab,value=tab.name,focus=true}
  force_tab=tab.id
end
local function finish_tab_rename(apply)
  local edit=tab_rename
  if apply and edit and edit.value:match('%S') and edit.value~=edit.target.name then
    edit.target.name=edit.value; touch(nil,'rename_tab'); undo_boundary=true
  end
  tab_rename=nil
end
local function draw_tab_rename(rect)
  if not tab_rename then return end
  if escape_pressed then finish_tab_rename(false); return end
  if not rect then return end
  local edit=tab_rename
  local x1,y1,x2,y2=table.unpack(rect)
  if x2-x1<=12 or y2<=y1 then return end
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  ImGui.PushID(ctx,edit.target.id)
  ImGui.PushClipRect(ctx,x1,y1,x2,y2,true)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,3,1)
  ImGui.SetCursorScreenPos(ctx,x1+4,y1+2)
  ImGui.SetNextItemWidth(ctx,x2-x1-8)
  local just_focused=edit.focus
  if just_focused then ImGui.SetKeyboardFocusHere(ctx); edit.focus=nil end
  local enter,value=ImGui.InputText(ctx,'##tab_name_inline',edit.value,
    ImGui.InputTextFlags_AutoSelectAll|ImGui.InputTextFlags_EnterReturnsTrue)
  edit.value=value
  local blurred=not just_focused and ImGui.IsItemDeactivated(ctx)
  ImGui.PopStyleVar(ctx); ImGui.PopClipRect(ctx); ImGui.PopID(ctx)
  ImGui.SetCursorScreenPos(ctx,sx,sy)
  ImGui.Dummy(ctx,0,0) -- Submit restored layout position before End (ReaImGui 0.10).
  if (enter and value:match('%S')) or blurred then finish_tab_rename(true) end
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
    TabSelectedOverline=t.accent,TextSelectedBg=(t.accent & 0xffffff00)|65,
    SliderGrab=t.accent,SliderGrabActive=t.accent}
  local count=0
  for k,v in pairs(colors) do ImGui.PushStyleColor(ctx,ImGui['Col_'..k],v); count=count+1 end
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,UI_METRICS.window_pad_x,UI_METRICS.window_pad_y)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,UI_METRICS.frame_pad_x,UI_METRICS.frame_pad_y)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,UI_METRICS.item_gap_x,UI_METRICS.item_gap_y)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemInnerSpacing,UI_METRICS.checkbox_label_gap,UI_METRICS.item_gap_y)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameRounding,3)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ChildRounding,0)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameBorderSize,1)
  return count
end
local UI={menu_open=nil,info=nil,open_info=nil,slider_state={},read_cache=setmetatable({},{__mode="k"})}
function UI.clamp(v,lo,hi) return math.floor(math.max(lo,math.min(hi,v))+0.5) end
function UI.slider(id, value, min_value, max_value, width, reset_value)
  local sx, sy = ImGui.GetCursorScreenPos(ctx)
  local dl = ImGui.GetWindowDrawList(ctx)

  -- The hit/layout rectangle includes the knob and its outline at both ends.
  local inset=UI_METRICS.slider_knob_radius+UI_METRICS.slider_outline
  local track_width=math.max(1,width-2*inset)
  local track_x1 = sx + inset
  local track_x2 = track_x1 + track_width
  local track_y = sy + UI_METRICS.slider_row_height * 0.5

  ImGui.InvisibleButton(
    ctx,
    "##view_slider_" .. id,
    width,
    UI_METRICS.slider_row_height,
    ImGui.ButtonFlags_MouseButtonLeft
  )

  local changed = false
  local new_value = value
  local is_active = ImGui.IsItemActive(ctx)
  local is_hovered = ImGui.IsItemHovered(ctx, ImGui.HoveredFlags_None)

  local dc_state = UI.slider_state
  local reset_by_double_click = false
  if reset_value ~= nil
     and is_hovered
     and ImGui.IsMouseDoubleClicked(ctx, ImGui.MouseButton_Left) then
    new_value = UI.clamp(reset_value, min_value, max_value)
    changed = (new_value ~= value)
    reset_by_double_click = true
    dc_state.suppress_drag_id = id
    dc_state.suppress_until_mouse_up = true
    dc_state.suppress_frames = 2
  end

  local suppress_drag = false
  if not reset_by_double_click and dc_state.suppress_drag_id == id then
    if dc_state.suppress_until_mouse_up and ImGui.IsMouseDown(ctx, ImGui.MouseButton_Left) then
      suppress_drag = true
    elseif dc_state.suppress_frames and dc_state.suppress_frames > 0 then
      suppress_drag = true
      dc_state.suppress_frames = dc_state.suppress_frames - 1
    else
      dc_state.suppress_drag_id = nil
      dc_state.suppress_until_mouse_up = false
      dc_state.suppress_frames = 0
    end
  end

  if is_active and not reset_by_double_click and not suppress_drag then
    local mouse_x = ImGui.GetMousePos(ctx)
    local t = 0
    if width > 0 and max_value > min_value then
      t = (mouse_x - track_x1) / track_width
    end
    if t < 0 then t = 0 end
    if t > 1 then t = 1 end

    new_value = UI.clamp(min_value + (max_value - min_value) * t, min_value, max_value)
    changed = (new_value ~= value)
  end

  local t = 0
  if max_value > min_value then
    t = (new_value - min_value) / (max_value - min_value)
  end
  if t < 0 then t = 0 end
  if t > 1 then t = 1 end

  local knob_x = track_x1 + track_width * t

  ImGui.DrawList_AddRectFilled(
    dl,
    track_x1,
    track_y - UI_METRICS.slider_track_height * 0.5,
    track_x2,
    track_y + UI_METRICS.slider_track_height * 0.5,
    (ImGui.GetColorEx(ctx,themes[theme].viewer.C_VIEW_SLIDER_TRACK))
  )
  ImGui.DrawList_AddRectFilled(
    dl,
    track_x1,
    track_y - UI_METRICS.slider_track_height * 0.5,
    knob_x,
    track_y + UI_METRICS.slider_track_height * 0.5,
    (ImGui.GetColorEx(ctx,themes[theme].viewer.C_VIEW_SLIDER_FILL))
  )

  ImGui.DrawList_AddCircleFilled(
    dl,
    knob_x,
    track_y,
    UI_METRICS.slider_knob_radius,
    ImGui.GetColorEx(ctx,themes[theme].viewer.C_VIEW_SLIDER_KNOB_FILL),
    UI_METRICS.slider_circle_segments
  )
  ImGui.DrawList_AddCircle(
    dl,
    knob_x,
    track_y,
    UI_METRICS.slider_knob_radius,
    ImGui.GetColorEx(ctx,themes[theme].viewer.C_VIEW_SLIDER_KNOB_OUTLINE),
    UI_METRICS.slider_circle_segments,
    is_hovered and UI_METRICS.slider_outline or UI_METRICS.slider_outline_normal
  )

  return changed, new_value
end

function UI.source_button(id, label, width, height)
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
  if active then
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
    1.0
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
function UI.checkbox_width(caption)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  local w=ImGui.GetTextLineHeight(ctx)+2*UI_METRICS.checkbox_pad_y+
    UI_METRICS.checkbox_label_gap+ImGui.CalcTextSize(ctx,caption)
  ImGui.PopFont(ctx)
  return w
end
function UI.checkbox(caption,value)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,UI_METRICS.frame_pad_x,UI_METRICS.checkbox_pad_y)
  local changed,result=ImGui.Checkbox(ctx,caption,value)
  ImGui.PopStyleVar(ctx)
  ImGui.PopFont(ctx)
  return changed,result
end
function UI.column_header_layout(width,add_caption)
  local aw,ah=UI.button_size(add_caption,true)
  local mw,mh=UI.button_size('...',true)
  local h=math.max(ah,mh)
  local controls_w=aw+UI_METRICS.item_gap_x+mw
  return {inline=width>=controls_w+UI_METRICS.item_gap_x+UI_METRICS.column_name_min_width,
    stacked=width<controls_w,width=controls_w,height=h,
    add_width=aw,menu_width=mw,add_height=ah,menu_height=mh}
end
function UI.quick_access_layout(width)
  local _,side=UI.button_size('',true)
  local menu_w,menu_h=UI.button_size('...',true)
  local controls_w=4*side+4*UI_METRICS.item_gap_x+menu_w
  return {inline=width>=controls_w+UI_METRICS.item_gap_x+UI_METRICS.column_name_min_width,
    width=controls_w,side=side,menu_width=menu_w,menu_height=menu_h}
end
function UI.quick_access_next(row,width)
  if row.used>0 and row.used+UI_METRICS.item_gap_x+width<=row.width then
    ImGui.SameLine(ctx,0,UI_METRICS.item_gap_x)
    row.used=row.used+UI_METRICS.item_gap_x+width
  else row.used=width end
end
--[[
Lucide icons: https://github.com/lucide-icons/lucide
Original paths: type, square-check, list-chevrons-down-up, file-input, palette, trash, x.
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
function UI.quick_access_button(id,caption,kind,side)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local clicked=UI.source_button('quick_'..id,'',side,side)
  UI.quick_icons=UI.quick_icons or {}
  local image=UI.quick_icons[kind]
  if not image then
    image=ImGui.CreateImageFromMem(UI.quick_icon_png[kind])
    ImGui.Attach(ctx,image)
    UI.quick_icons[kind]=image
  end
  local icon_side=math.min(16,side-7)
  local offset=(side-icon_side)*0.5
  local color=ImGui.GetColor(ctx,ImGui.Col_Text)
  ImGui.DrawList_AddImage(ImGui.GetWindowDrawList(ctx),image,
    sx+offset,sy+offset,sx+offset+icon_side,sy+offset+icon_side,
    0,0,1,1,color)
  ImGui.SetItemTooltip(ctx,tr(caption))
  return clicked
end
function UI.document_input(key,caption,value,multiline,height)
  ImGui.Function_SetValue(input_callback,'seen',0)
  local flags=ImGui.InputTextFlags_NoUndoRedo|ImGui.InputTextFlags_CallbackAlways
  local rv,result
  if multiline then
    rv,result=ImGui.InputTextMultiline(ctx,caption,value,-1,height,flags|ImGui.InputTextFlags_AllowTabInput,input_callback)
  else rv,result=ImGui.InputText(ctx,caption,value,flags,input_callback) end
  if ImGui.Function_GetValue(input_callback,'seen')~=0 then
    local current={key=key,cursor=ImGui.Function_GetValue(input_callback,'cursor'),
      first=ImGui.Function_GetValue(input_callback,'first'),last=ImGui.Function_GetValue(input_callback,'last')}
    local previous=session.input_state
    local gesture
    if ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Key_V) or
        ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Shift|ImGui.Key_Insert) then gesture='paste'
    elseif ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Key_X) then gesture='cut' end
    local group,action=M.text_edit(session.history,key,value,result,previous,current,gesture)
    if rv and value~=result then touch(group,action) end
    session.input_state=current
  elseif rv and value~=result then
    -- A committed edit may be reported on the deactivation frame without a callback.
    local group,action=M.text_edit(session.history,key,value,result,session.input_state,nil)
    touch(group,action)
  end
  if ImGui.IsItemDeactivatedAfterEdit(ctx) then
    undo_boundary=true
    if session.input_state and session.input_state.key==key then session.input_state=nil end
  end
  return rv,result
end
function UI.confirm_geometry(title,message)
  local delete_w,delete_h=UI.button_size(tr('Delete'))
  local cancel_w,cancel_h=UI.button_size(tr('Cancel'))
  local content_w=math.max(ImGui.CalcTextSize(ctx,tr(title)),
    ImGui.CalcTextSize(ctx,tr(message)),delete_w+UI_METRICS.item_gap_x+cancel_w)
  local width=math.ceil(math.max(UI_METRICS.confirm_min_width,
    math.min(UI_METRICS.confirm_max_width,content_w+2*UI_METRICS.window_pad_x)))
  local _,title_h=ImGui.CalcTextSize(ctx,tr(title))
  local _,message_h=ImGui.CalcTextSize(ctx,tr(message),nil,nil,false,width-2*UI_METRICS.window_pad_x)
  local height=math.ceil(2*UI_METRICS.window_pad_y+title_h+1+message_h+
    math.max(delete_h,cancel_h)+3*UI_METRICS.item_gap_y)
  return width,height
end
function UI.toolbar_next(row,width)
  if row.used>0 and row.used+UI_METRICS.group_gap+width<=row.width then
    ImGui.SameLine(ctx,0,UI_METRICS.group_gap)
    row.used=row.used+UI_METRICS.group_gap+width
  else row.used=width end
end
-- All authored dialogs use the Viewer's 12px outer margin and centering.
-- Content edits never resize a dialog; only a resized host can constrain it.
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
  -- BeginGroup keeps every wrapped line aligned after a leading checkbox.
  ImGui.BeginGroup(ctx)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,0,UI_METRICS.read_line_gap)
  for _,line in ipairs(cache.lines) do
    if line=='' then ImGui.Dummy(ctx,0,line_h) else ImGui.Text(ctx,line) end
  end
  ImGui.PopStyleVar(ctx)
  ImGui.EndGroup(ctx)
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
        local trigger_pad_x = 8
        local trigger_w = label_w + trigger_pad_x * 2
        local trigger_h = ImGui.GetFrameHeight(ctx)
        if trigger_h < 1 then trigger_h = 38 end

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
          tx1 + math.max(6, math.floor(((tx2 - tx1) - label_w) * 0.5)),
          ty1 + math.max(1, math.floor(((ty2 - ty1) - label_h) * 0.5)),
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
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,4,math.max(0,(38-ImGui.GetTextLineHeight(ctx))*0.5))
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
  local pad_x,pad_y=20,17
  local texts={TITLE,tr('Version: ')..'0.5.4',
    tr('Notes for projects, tracks and items.'),tr('Aleksei Vorobev / Patch34'),
    'https://github.com/patch-34'}
  local content_w=UI.button_size(tr('Close'))
  for _,text in ipairs(texts) do
    local text_w=ImGui.CalcTextSize(ctx,text)
    content_w=math.max(content_w,text_w)
  end
  local host_w=ImGui.GetWindowSize(ctx)
  local width=math.min(math.ceil(content_w+2*pad_x+2),
    math.max(1,host_w-2*UI_METRICS.popup_margin))
  local content_h=0
  for i,text in ipairs(texts) do
    local _,h=ImGui.CalcTextSize(ctx,text,nil,nil,false,
      i==3 and math.max(1,width-2*pad_x) or 0)
    content_h=content_h+h
  end
  local _,button_h=UI.button_size(tr('Close'))
  -- Four inter-line gaps plus the two explicit Spacing items in About.
  local height=math.ceil(2*pad_y+content_h+6*UI_METRICS.item_gap_y+
    button_h+UI_METRICS.popup_footer_gap+2)
  return width,height
end
function UI.info_window()
  if not UI.info then return end
  local kind=UI.info
  if UI.open_info then ImGui.OpenPopup(ctx,'##information');UI.open_info=nil end
  local w,h=table.unpack(UI_METRICS.popup_sizes[kind])
  if kind=='about' then w,h=UI.about_geometry() end
  -- About panel colors, corner radius and inset are from Viewer render_about_overlay.
  ImGui.PushStyleColor(ctx,ImGui.Col_PopupBg,rgba(80,80,80,218))
  ImGui.PushStyleColor(ctx,ImGui.Col_Border,rgba(220,220,220,95))
  ImGui.PushStyleColor(ctx,ImGui.Col_Text,rgba(245,245,245))
  ImGui.PushStyleColor(ctx,ImGui.Col_TextDisabled,rgba(210,210,210))
  ImGui.PushStyleColor(ctx,ImGui.Col_Button,rgba(105,105,105,230))
  ImGui.PushStyleColor(ctx,ImGui.Col_ButtonHovered,rgba(122,122,122,235))
  ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,0)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_PopupRounding,12)
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowPadding,20,17)
  UI.place_popup(w,h)
  local visible=ImGui.BeginPopup(ctx,'##information',ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings)
  if visible then
    if escape_pressed then
      ImGui.CloseCurrentPopup(ctx);UI.info=nil;ImGui.EndPopup(ctx)
      ImGui.PopStyleVar(ctx,2);ImGui.PopStyleColor(ctx,7);return
    end
    if UI.popup_body('information_body',tr('Close')) then
      if kind=='about' then
        ImGui.Text(ctx,TITLE)
        ImGui.TextDisabled(ctx,tr('Version: ')..'0.5.4')
        ImGui.Spacing(ctx)
        ImGui.TextWrapped(ctx,tr('Notes for projects, tracks and items.'))
        ImGui.Text(ctx,tr('Aleksei Vorobev / Patch34'))
        ImGui.Spacing(ctx)
        if ImGui.TextLink(ctx,'https://github.com/patch-34') then
          ImGui.SetClipboardText(ctx,'https://github.com/patch-34')
          UI.open_url('https://github.com/patch-34')
        end
      end
      ImGui.EndChild(ctx)
    end
    -- Same button geometry as other dialogs, with Viewer's About-button skin.
    local close_w,close_h=UI.button_size(tr('Close'))
    local close_x,close_y=ImGui.GetCursorScreenPos(ctx)
    local available_w=ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorScreenPos(ctx,close_x+math.max(0,available_w-close_w),close_y)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameRounding,7)
    ImGui.PushStyleColor(ctx,ImGui.Col_Border,rgba(230,230,230,80))
    if ImGui.Button(ctx,ui_label('Close'),close_w,close_h) then ImGui.CloseCurrentPopup(ctx);UI.info=nil end
    ImGui.PopStyleColor(ctx);ImGui.PopStyleVar(ctx)
    ImGui.EndPopup(ctx)
  elseif not ImGui.IsPopupOpen(ctx,'##information') then UI.info=nil end
  ImGui.PopStyleVar(ctx,2);ImGui.PopStyleColor(ctx,7)
end

local function active_tab() return session.doc.tabs[session.active] end
local function add_block(kind,column)
  local b
  if kind=='text' then b=M.text('')
  elseif kind=='note' then b=M.note('')
  else b={id=uid(),kind='select',label=tr('Status'),options={tr('Not started'),tr('In progress'),tr('Done')},selected=1} end
  column=column or active_tab().columns[1]
  column.blocks[#column.blocks+1]=b
  editing=true; pref('editing','1'); touch(nil,kind=='select' and 'add_dropdown' or 'add_note')
  if kind=='select' then request_modal(clone_select(b)) end
end
local function import_dialog(column)
  request_modal({kind='import',title='Import text',value='',strip=true,preview={},column=column or active_tab().columns[1]})
end
local function add_menu(column)
  if ImGui.MenuItem(ctx,ui_label('Note with checkbox')) then add_block('note',column) end
  if ImGui.MenuItem(ctx,ui_label('Import text...')) then import_dialog(column) end
  if ImGui.MenuItem(ctx,ui_label('Text')) then add_block('text',column) end
  if ImGui.MenuItem(ctx,ui_label('Dropdown')) then add_block('select',column) end
end
local function add_column(tab)
  tab.columns[#tab.columns+1]=M.column(tr('Column')..' '..(#tab.columns+1))
  touch(nil,'add_column'); undo_boundary=true
end
local function can_history(direction)
  if not session or (not session.doc and not session.history_readonly)
      or (session.error and not (session.history_readonly and not session.doc)) or session.conflict or modal or tab_rename or UI.info then return false end
  return #(direction<0 and session.history.undo or session.history.redo)>0
end
local function history_shortcuts()
  if not session or modal or tab_rename or UI.info or (session.error and not (session.history_readonly and not session.doc)) or session.conflict then return end
  if not ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_RootAndChildWindows) then return end
  -- NoUndoRedo on document inputs prevents both histories firing for one chord.
  -- Mod_Ctrl maps to Cmd under ReaImGui's native macOS behavior.
  if ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Key_Z) and can_history(-1) then history_request=-1
  elseif (ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Mod_Shift|ImGui.Key_Z)
      or ImGui.IsKeyChordPressed(ctx,ImGui.Mod_Ctrl|ImGui.Key_Y)) and can_history(1) then history_request=1 end
end
local HISTORY_ACTIONS = {
  color_marker={'color marker','цветовую метку'},delete_selected={'delete selected elements','удаление выделенных элементов'},

  change={'change','изменение'},typing={'typing','ввод текста'},deletion={'text deletion','удаление текста'},
  paste={'paste','вставку текста'},cut={'cut','вырезание текста'},replace={'text replacement','замену текста'},
  line_break={'line break','перевод строки'},checkbox={'checkbox change','отметку'},
  choose_option={'option selection','выбор значения'},edit_dropdown={'dropdown edit','изменение списка'},
  add_note={'add note','добавление заметки'},delete_item={'delete note','удаление заметки'},move_note={'move note','перемещение заметки'},
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
  local padding=math.max(2,math.ceil((label_width-ImGui.CalcTextSize(ctx,caption)+12)/space))
  -- Keep the shortcut beside these rows: long unrelated menu labels must not
  -- force ImGui's shared shortcut column farther to the right.
  return ImGui.MenuItem(ctx,caption..string.rep(' ',padding)..shortcut..'###'..base,nil,false,can_history(direction))
end
local function menu_bar()
  UI.menu_count=0
  if not ImGui.BeginMenuBar(ctx) then return end
  local enabled=session~=nil and session.doc~=nil and session.error==nil and session.conflict==nil
  if UI.begin_menu('Edit') then
    if ImGui.MenuItem(ctx,ui_label('Import text...'),nil,false,enabled) then import_dialog() end
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
  if UI.begin_menu('Tab',enabled) then
    if ImGui.MenuItem(ctx,ui_label('New tab')) then
      request_modal({kind='new_tab',title='New tab',value=tr('New note')})
    end
    if ImGui.MenuItem(ctx,ui_label('Rename')) then
      begin_tab_rename(active_tab())
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx,ui_label('Move left'),nil,false,session.active>1) then
      session.active=M.move(session.doc.tabs,session.active,-1); force_tab=active_tab().id; touch(nil,'move_tab')
    end
    if ImGui.MenuItem(ctx,ui_label('Move right'),nil,false,session.active<#session.doc.tabs) then
      session.active=M.move(session.doc.tabs,session.active,1); force_tab=active_tab().id; touch(nil,'move_tab')
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx,ui_label('Delete tab...'),nil,false,#session.doc.tabs>1) then
      confirm_tab_delete(active_tab())
    end
    ImGui.EndPopup(ctx)
  end
  if UI.begin_menu('Add',enabled) then
    local tab=active_tab()
    if #tab.columns==1 then add_menu(tab.columns[1])
    else
      for _,column in ipairs(tab.columns) do
        if ImGui.BeginMenu(ctx,label(column.name)..'##'..column.id) then add_menu(column); ImGui.EndMenu(ctx) end
      end
    end
    ImGui.Separator(ctx)
    if ImGui.MenuItem(ctx,ui_label('Column'),nil,false,#tab.columns<8) then add_column(tab) end
    ImGui.EndPopup(ctx)
  end
  if UI.begin_menu('View') then
    if ImGui.MenuItem(ctx,ui_label('Edit mode'),nil,editing) then editing=not editing; pref('editing',editing and '1' or '0') end
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
    if ImGui.MenuItem(ctx,ui_label(help_caption),nil,false,REPOSITORY_URL~=nil) then UI.open_url(REPOSITORY_URL) end
    if ImGui.MenuItem(ctx,ui_label('About...')) then UI.show_info('about') end
    ImGui.EndPopup(ctx)
  end
  ImGui.EndMenuBar(ctx)
end
UI.marker_palette={
  light={red=0xc15251ff,orange=0xb5782bff,yellow=0xa29227ff,
    green=0x54816aff,blue=0x527fa1ff,purple=0x8c6ca1ff},
  dark={red=0xe88a85ff,orange=0xe6b767ff,yellow=0xd6c75fff,
    green=0x82b79aff,blue=0x8fb8d6ff,purple=0xbba0cdff},
}
function UI.marker_color(key)
  local palette=UI.marker_palette[theme=='dark' and 'dark' or 'light']
  local color=ImGui.GetColorEx(ctx,palette[key])
  return color
end
local function marker_menu(current,apply)
  if ImGui.MenuItem(ctx,ui_label('No marker'),nil,current==nil) then apply(nil) end
  ImGui.Separator(ctx)
  for _,key in ipairs(M.marker_keys) do
    local name=key:sub(1,1):upper()..key:sub(2)
    local clicked=ImGui.MenuItem(ctx,'   '..tr(name)..'###marker_'..key,nil,current==key)
    local x,y=ImGui.GetItemRectMin(ctx)
    local _,bottom=ImGui.GetItemRectMax(ctx)
    local center=(y+bottom)*0.5
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),x+3,center-4,x+11,center+4,UI.marker_color(key),1)
    if clicked then apply(key) end
  end
end
local function start_selection(tab,column)
  session.history.key=nil;session.input_state=nil
  bulk_selection={owner=session,tab_id=tab.id,column=column,selected={}}
end
local function selection_toolbar(column)
  local current=bulk_selection
  local count,total=M.selection_prune(column,current.selected,hide_completed)
  ImGui.TextWrapped(ctx,column.name..' — '..tr('Selected: %d'):format(count))
  local width=ImGui.GetContentRegionAvail(ctx)
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
  ImGui.Separator(ctx)
end
local function block_actions(tab,column,index)
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  if UI.button(ctx,ui_label('...##actions')) then ImGui.OpenPopup(ctx,'block_actions') end
  if begin_action_popup('block_actions') then
    if ImGui.MenuItem(ctx,ui_label('Move up'),nil,false,index>1) then session.pending=function() M.move(column.blocks,index,-1); touch(nil,'move_note') end end
    if ImGui.MenuItem(ctx,ui_label('Move down'),nil,false,index<#column.blocks) then session.pending=function() M.move(column.blocks,index,1); touch(nil,'move_note') end end
    if ImGui.BeginMenu(ctx,ui_label('Move to column'),#tab.columns>1) then
      for _,target in ipairs(tab.columns) do
        if target~=column and ImGui.MenuItem(ctx,label(target.name)..'##'..target.id) then
          session.pending=function()
            target.blocks[#target.blocks+1]=table.remove(column.blocks,index); touch(nil,'move_note')
          end
        end
      end
      ImGui.EndMenu(ctx)
    end
    if ImGui.BeginMenu(ctx,ui_label('Color marker')) then
      local block=column.blocks[index]
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
local function dropdown_header(tab,column,b,index,width)
  local layout=UI.column_header_layout(width,tr('Edit...'))
  local table_open=layout.inline and ImGui.BeginTable(ctx,'dropdown_header',2,
    ImGui.TableFlags_SizingStretchSame|ImGui.TableFlags_NoSavedSettings,width)
  if not layout.inline or table_open then
    if table_open then
      ImGui.TableSetupColumn(ctx,'Name',ImGui.TableColumnFlags_WidthStretch,1)
      ImGui.TableSetupColumn(ctx,'Controls',ImGui.TableColumnFlags_WidthFixed,layout.width)
      ImGui.TableNextRow(ctx);ImGui.TableNextColumn(ctx)
    end
    UI.read_text(b.label,b)
    if table_open then ImGui.TableNextColumn(ctx) end
    if editing then
      if UI.button(ctx,ui_label('Edit...'),true) then request_modal(clone_select(b)) end
    else
      ImGui.Dummy(ctx,layout.add_width,layout.add_height)
    end
    if not layout.stacked then ImGui.SameLine(ctx,0,UI_METRICS.item_gap_x) end
    block_actions(tab,column,index)
    if table_open then ImGui.EndTable(ctx) end
  end
end
local function draw_block(tab,column,b,index)
  ImGui.PushID(ctx,b.id)
  local block_width=ImGui.GetContentRegionAvail(ctx)
  if b.kind=='select' then dropdown_header(tab,column,b,index,block_width) end
  -- Keep the actions gutter on wide columns; stack it below narrow widgets.
  local wide=block_width>=180
  local table_open=wide and ImGui.BeginTable(ctx,'block',2,
    ImGui.TableFlags_SizingStretchSame|ImGui.TableFlags_NoSavedSettings,block_width)
  if not wide or table_open then
    if table_open then
      ImGui.TableSetupColumn(ctx,'Content',ImGui.TableColumnFlags_WidthStretch,1)
      ImGui.TableSetupColumn(ctx,'Actions',ImGui.TableColumnFlags_WidthFixed,(UI.button_size('...')))
      ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
    end
    local rv,value
    if b.kind=='text' or b.kind=='note' then
      if b.kind=='note' then
        rv,value=UI.checkbox('##checked',b.checked)
        if rv then b.checked=value; touch(nil,'checkbox'); undo_boundary=true end
        if wide then ImGui.SameLine(ctx) end
      end
      if editing then
        local _,n=b.text:gsub('\n','\n')
        local h=math.max(56,math.min(240,(n+2)*ImGui.GetTextLineHeight(ctx)+12))
        rv,value=UI.document_input('text:'..b.id,'##text',b.text,true,h)
        if rv then b.text=value end
      else
        UI.read_text(b.text~='' and b.text or tr('(Empty text block)'),b)
      end
    elseif b.kind=='check' then
      rv,value=UI.checkbox('##checked',b.checked)
      if rv then b.checked=value; touch(nil,'checkbox'); undo_boundary=true end
      if wide then ImGui.SameLine(ctx) end
      if editing then
        ImGui.SetNextItemWidth(ctx,-1)
        rv,value=UI.document_input('label:'..b.id,'##label',b.label,false)
        if rv then b.label=value end
      else UI.read_text(b.label,b) end
    else
      -- Capture ONLY width. Height must never influence the dropdown size.
      -- The 420px preferred width yields to a narrower column, preventing clipping.
      local available_width=ImGui.GetContentRegionAvail(ctx)
      local combo_width=math.max(1,math.min(UI_METRICS.dropdown_width,available_width))
      ImGui.SetNextItemWidth(ctx,combo_width)
      ImGui.SetNextWindowSizeConstraints(ctx,combo_width,0,combo_width,math.min(8,#b.options)*ImGui.GetTextLineHeightWithSpacing(ctx)+16)
      if ImGui.BeginCombo(ctx,'##value',b.options[b.selected]) then
        if escape_pressed then ImGui.CloseCurrentPopup(ctx)
        else
        for i,option in ipairs(b.options) do
          ImGui.PushID(ctx,i)
          if ImGui.Selectable(ctx,label(option)..'##option',i==b.selected) then b.selected=i; touch(nil,'choose_option'); undo_boundary=true end
          if i==b.selected then ImGui.SetItemDefaultFocus(ctx) end
          ImGui.PopID(ctx)
        end
        end
        ImGui.EndCombo(ctx)
      end
    end
    if table_open then ImGui.TableNextColumn(ctx) end
    if b.kind~='select' then block_actions(tab,column,index) end
    if table_open then ImGui.EndTable(ctx) end
  end
  ImGui.PopID(ctx)
end
local function draw_selection_block(column,b,index)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  local width=math.max(1,ImGui.GetContentRegionAvail(ctx))
  local summary=b.text or b.label or ''
  if b.kind=='note' or b.kind=='check' then summary=(b.checked and '[x] ' or '[ ] ')..summary
  elseif b.kind=='select' then summary=summary..'\n'..b.options[b.selected] end
  if summary=='' then summary=tr('(Empty text block)') end
  ImGui.PushID(ctx,b.id)
  ImGui.BeginGroup(ctx)
  UI.read_text(summary,b,math.max(1,width-22))
  ImGui.EndGroup(ctx)
  local _,bottom=ImGui.GetItemRectMax(ctx)
  local height=math.max(23,bottom-sy+4)
  ImGui.SetCursorScreenPos(ctx,sx,sy)
  if ImGui.InvisibleButton(ctx,'##bulk_select_'..index,width,height,
      ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_EnableNav) then
    local selected=bulk_selection.selected
    selected[b.id]=not selected[b.id] or nil
  end
  if bulk_selection.selected[b.id] then
    local color=ImGui.GetColor(ctx,ImGui.Col_CheckMark)
    ImGui.DrawList_AddRect(ImGui.GetWindowDrawList(ctx),sx,sy,sx+width,sy+height,color,2,ImGui.DrawFlags_None,1)
    ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
    ImGui.DrawList_AddText(ImGui.GetWindowDrawList(ctx),sx+math.max(0,width-18),sy+2,color,'✓')
    ImGui.PopFont(ctx)
  end
  ImGui.PopID(ctx)
end
local function draw_marked_block(tab,column,b,index)
  local sx,sy=ImGui.GetCursorScreenPos(ctx)
  ImGui.Indent(ctx,8)
  ImGui.BeginGroup(ctx)
  if bulk_selection and bulk_selection.column==column then draw_selection_block(column,b,index)
  else draw_block(tab,column,b,index) end
  ImGui.EndGroup(ctx)
  local _,bottom=ImGui.GetItemRectMax(ctx)
  ImGui.Unindent(ctx,8)
  if b.color then
    ImGui.DrawList_AddRectFilled(ImGui.GetWindowDrawList(ctx),sx+1,sy+2,sx+4,math.max(sy+10,bottom-2),UI.marker_color(b.color),1)
  end
end
local function column_header(tab,column,index)
  if bulk_selection and bulk_selection.column==column then selection_toolbar(column);return end
  local width=ImGui.GetContentRegionAvail(ctx)
  local layout=UI.quick_access_layout(width)
  -- Both columns have explicit initial sizing. A new table must not infer
  -- its text width from the previous frame's (possibly absent) contents.
  local table_open=layout.inline and ImGui.BeginTable(ctx,'column_header',2,
    ImGui.TableFlags_SizingStretchSame|ImGui.TableFlags_NoSavedSettings,width)
  if not layout.inline or table_open then
    if table_open then
      ImGui.TableSetupColumn(ctx,'Name',ImGui.TableColumnFlags_WidthStretch,1)
      ImGui.TableSetupColumn(ctx,'Controls',ImGui.TableColumnFlags_WidthFixed,layout.width)
      ImGui.TableNextRow(ctx); ImGui.TableNextColumn(ctx)
    end
    ImGui.TextWrapped(ctx,column.name)
    if ImGui.IsItemHovered(ctx) and ImGui.IsMouseDoubleClicked(ctx,0) then
      request_modal({kind='rename_column',title='Rename column',target=column,value=column.name})
    end
    if table_open then ImGui.TableNextColumn(ctx) end
    -- Submit the same controls/placeholders so switching modes preserves layout.
    local row={width=layout.inline and layout.width or width,used=0}
    for _,action in ipairs({
      {id='text',caption='Text',kind='text'},
      {id='note',caption='Note with checkbox',kind='note'},
      {id='dropdown',caption='Dropdown',kind='select'},
      {id='import',caption='Import text...',kind='import'},
    }) do
      UI.quick_access_next(row,layout.side)
      if editing then
        if UI.quick_access_button(action.id,action.caption,action.kind,layout.side) then
          if action.kind=='import' then import_dialog(column)
          else add_block(action.kind,column) end
        end
      else ImGui.Dummy(ctx,layout.side,layout.side) end
    end
    UI.quick_access_next(row,layout.menu_width)
    if editing then
      if UI.button(ctx,ui_label('...##column'),true) then ImGui.OpenPopup(ctx,'column_actions') end
      if begin_action_popup('column_actions') then
        if ImGui.MenuItem(ctx,ui_label('Select elements...'),nil,false,#column.blocks>0) then start_selection(tab,column) end
        ImGui.Separator(ctx)
        if ImGui.MenuItem(ctx,ui_label('Rename column...')) then
          request_modal({kind='rename_column',title='Rename column',target=column,value=column.name})
        end
        if ImGui.MenuItem(ctx,ui_label('Move column left'),nil,false,index>1) then
          session.pending=function() M.move(tab.columns,index,-1); touch(nil,'move_column') end
        end
        if ImGui.MenuItem(ctx,ui_label('Move column right'),nil,false,index<#tab.columns) then
          session.pending=function() M.move(tab.columns,index,1); touch(nil,'move_column') end
        end
        if ImGui.MenuItem(ctx,ui_label('Delete column...'),nil,false,#tab.columns>1) then
          confirm_delete(function() table.remove(tab.columns,index); touch() end,'column')
        end
        ImGui.EndPopup(ctx)
      end
    else
      ImGui.Dummy(ctx,layout.menu_width,layout.menu_height)
    end
    if table_open then ImGui.EndTable(ctx) end
  end
  ImGui.Separator(ctx)
end
local function draw_columns(tab)
  local width,height=ImGui.GetContentRegionAvail(ctx)
  -- Stretch columns share the actual viewport. Native resizers redistribute
  -- neighboring weights; do not force an inner canvas or minimum pixel widths.
  local flags=ImGui.TableFlags_Resizable|ImGui.TableFlags_SizingStretchSame|ImGui.TableFlags_BordersInnerV|ImGui.TableFlags_NoSavedSettings
  local table_height=math.max(120,height-4)
  if ImGui.BeginTable(ctx,'columns'..tab.id,#tab.columns,flags,width,table_height) then
    for _,column in ipairs(tab.columns) do
      ImGui.TableSetupColumn(ctx,'##column'..column.id,ImGui.TableColumnFlags_WidthStretch,1)
    end
    ImGui.TableNextRow(ctx)
    for index,column in ipairs(tab.columns) do
      ImGui.TableNextColumn(ctx)
      ImGui.PushID(ctx,column.id)
      -- A fixed height derived from the outer viewport avoids circular table/child sizing.
      if ImGui.BeginChild(ctx,'column_body',0,math.max(40,table_height-8),ImGui.ChildFlags_Borders) then
        column_header(tab,column,index)
        ImGui.PushFont(ctx,font,size)
        if #column.blocks==0 then ImGui.TextDisabled(ctx,tr('Empty column')) end
        local shown=0
        for i,b in ipairs(column.blocks) do
          if M.visible(b,hide_completed) then
            shown=shown+1
            draw_marked_block(tab,column,b,i)
            -- Keep section boundaries without redundant empty rows.
            ImGui.Separator(ctx)
          end
        end
        if shown==0 and #column.blocks>0 then ImGui.TextDisabled(ctx,tr('Completed items hidden')) end
        ImGui.PopFont(ctx)
        ImGui.EndChild(ctx)
      end
      ImGui.PopID(ctx)
    end
    ImGui.EndTable(ctx)
  end
end
local function draw_document()
  if ImGui.BeginTabBar(ctx,'notes_tabs',ImGui.TabBarFlags_FittingPolicyScroll) then
    for index,tab in ipairs(session.doc.tabs) do
      local flags=force_tab==tab.id and ImGui.TabItemFlags_SetSelected or 0
      local renaming=tab_rename and tab_rename.target==tab
      -- Keep the tab's ID and selection while reserving space for its inline input.
      local caption=renaming and string.rep(' ',40) or label(tab.name)
      local tab_visible=ImGui.BeginTabItem(ctx,caption..'###tab'..tab.id,nil,flags)
      local tab_hovered=ImGui.IsItemHovered(ctx)
      local tab_right_clicked=tab_hovered and ImGui.IsMouseClicked(ctx,1)
      if not renaming and tab_hovered and ImGui.IsMouseDoubleClicked(ctx,0) then
        begin_tab_rename(tab)
      end
      -- Capture the tab rectangle before child widgets replace the last-item data.
      if tab_visible and tab_rename and tab_rename.target==tab and ImGui.IsItemVisible(ctx) then
        local x1,y1=ImGui.GetItemRectMin(ctx)
        local x2,y2=ImGui.GetItemRectMax(ctx)
        -- Submit the overlay while the cursor is still above the columns.
        -- Restoring it after the full-height table extended the parent by a row.
        draw_tab_rename({x1,y1,x2,y2})
      end
      local context_id='tab_context'..tab.id
      if tab_right_clicked then ImGui.OpenPopup(ctx,context_id) end
      if begin_action_popup(context_id) then
        if ImGui.MenuItem(ctx,ui_label('Delete tab...'),nil,false,#session.doc.tabs>1) then
          confirm_tab_delete(tab)
        end
        ImGui.EndPopup(ctx)
      end
      if tab_visible then
        if bulk_selection and bulk_selection.tab_id~=tab.id then bulk_selection=nil end
        session.active=index
        draw_columns(tab)
        ImGui.EndTabItem(ctx)
      end
    end
    ImGui.EndTabBar(ctx)
  end
  force_tab=nil
  if session.pending then local fn=session.pending; session.pending=nil; fn() end
end
local function draw_modal()
  if open_modal then ImGui.OpenPopup(ctx,open_modal);open_modal=nil end
  if not modal then return end
  local m=modal
  local dimensions=UI_METRICS.popup_sizes[m.kind] or UI_METRICS.popup_sizes.name
  local width,height=table.unpack(dimensions)
  if m.kind=='delete' then
    if not m.width then m.width,m.height=UI.confirm_geometry('Confirm deletion',m.message) end
    width,height=m.width,m.height
  end
  UI.place_popup(width,height)
  local visible=ImGui.BeginPopup(ctx,m.title,ImGui.WindowFlags_NoResize|ImGui.WindowFlags_NoSavedSettings)
  if visible then
    if escape_pressed then
      ImGui.CloseCurrentPopup(ctx);modal=nil;ImGui.EndPopup(ctx);return
    end
    ImGui.Text(ctx,tr(m.kind=='delete' and 'Confirm deletion' or m.title));ImGui.Separator(ctx)
    local primary=m.kind=='delete' and 'Delete' or m.kind=='import' and 'Import' or m.kind=='restore' and 'Restore' or 'Apply'
    local enter=false
    if UI.popup_body('editor_body',tr(primary)) then
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
          ImGui.Text(ctx,tr('Destination column'))
          ImGui.SetNextItemWidth(ctx,-1)
          if ImGui.BeginCombo(ctx,'##import_column',m.column.name) then
            for _,column in ipairs(active_tab().columns) do
              if ImGui.Selectable(ctx,label(column.name)..'##destination'..column.id,m.column==column) then m.column=column end
            end
            ImGui.EndCombo(ctx)
          end
          local rv,value=UI.checkbox(ui_label('Remove numbering'),m.strip)
          if rv then m.strip=value;m.preview=M.import_text(m.value,m.strip) end
          -- One extra item gap separates the header from the panel labels.
          ImGui.Dummy(ctx,0,0)
          ImGui.TableNextColumn(ctx)
          ImGui.TextWrapped(ctx,tr('Paste text or a numbered list on the left. The notes to be added appear on the right.'))
          ImGui.TextWrapped(ctx,tr('Separate paragraphs with a blank line. In a numbered list, start each new item on a new line.'))
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
          local pane_h=math.max(56,math.floor(remaining_h-UI_METRICS.item_gap_y))
          if m.focus then ImGui.SetKeyboardFocusHere(ctx);m.focus=nil end
          rv,value=ImGui.InputTextMultiline(ctx,'##import_text',m.value,-1,pane_h,ImGui.InputTextFlags_AllowTabInput)
          if rv then m.value=value;m.preview=M.import_text(value,m.strip) end
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
            ImGui.EndChild(ctx)
          end
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
        if ImGui.BeginChild(ctx,'options',0,math.max(60,available_h-add_h-UI_METRICS.item_gap_y),ImGui.ChildFlags_Borders) then
          local action
          for i,option in ipairs(m.options) do
            ImGui.PushID(ctx,i)
            if ImGui.RadioButton(ctx,'##selected',m.selected==i) then m.selected=i end
            ImGui.SameLine(ctx);ImGui.SetNextItemWidth(ctx,math.max(60,ImGui.GetContentRegionAvail(ctx)-110))
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
          ImGui.EndChild(ctx)
        end
        if UI.button(ctx,ui_label('+ Option')) then m.options[#m.options+1]=tr('New option') end
      end
      ImGui.EndChild(ctx)
    end
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
        for _,text in ipairs(m.preview) do m.column.blocks[#m.column.blocks+1]=M.note(text) end
      elseif m.kind=='delete' then m.action();edit_action=m.history_action
      elseif m.kind=='select' then
        m.target.label=m.label;m.target.options=m.options;m.target.selected=m.selected
      end
      if m.kind~='delete' then touch(nil,({new_tab='add_tab',rename_column='rename_column',import='import',select='edit_dropdown',restore='restore'})[m.kind]) end
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
      session.doc=M.plain(session.raw); session.error=nil; epoch=epoch+1
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
  local function checkbox_width(caption) return UI.checkbox_width(tr(caption)) end
  if session and not switched then
    UI.toolbar_next(row,UI.checkbox_width(language=='ru' and tr('Edit notes') or 'Edit'))
    local rv,value=UI.checkbox((language=='ru' and tr('Edit notes') or 'Edit')..'###Edit',editing)
    if rv then editing=value; pref('editing',editing and '1' or '0') end
  end
  UI.toolbar_next(row,checkbox_width('Hide completed'))
  local rv,value=UI.checkbox(ui_label('Hide completed'),hide_completed)
  if rv then hide_completed=value; pref('hide_completed',value and '1' or '0') end
  -- Move the complete font control to a new row when its measured width will
  -- not fit. Reserve the widest readout so dragging does not reflow the toolbar.
  local label_w=ImGui.CalcTextSize(ctx,tr('Font'))
  local value_w=0
  for n=12,32 do value_w=math.max(value_w,(ImGui.CalcTextSize(ctx,tostring(n)..tr(' px')))) end
  local fixed_w=label_w+value_w+2*UI_METRICS.inner_gap
  local slider_w=math.max(UI_METRICS.slider_min_width,
    math.min(UI_METRICS.slider_width,row.width-fixed_w))
  UI.toolbar_next(row,fixed_w+slider_w)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.Text(ctx,tr('Font'));ImGui.SameLine(ctx,0,UI_METRICS.inner_gap)
  rv,value=UI.slider('font',size,12,32,slider_w,16)
  ImGui.SameLine(ctx,0,UI_METRICS.inner_gap)
  ImGui.AlignTextToFramePadding(ctx)
  ImGui.TextDisabled(ctx,tostring(value)..tr(' px'))
  if rv then size=value; pref('size',size) end
  return switched
end
local function header_context()
  local x,y=ImGui.GetWindowPos(ctx)
  local w=ImGui.GetWindowWidth(ctx)
  local _,bottom=ImGui.GetCursorScreenPos(ctx)
  local mx,my=ImGui.GetMousePos(ctx)
  local dock=ImGui.GetWindowDockID(ctx)
  if dock<0 and dock~=last_docker then last_docker=dock; pref('last_docker',dock) end
  if ImGui.IsWindowHovered(ctx) and ImGui.IsMouseClicked(ctx,1)
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
  if bulk_selection and (bulk_selection.owner~=session or not editing or not session or not session.doc or session.error or session.conflict) then bulk_selection=nil end
  if pending_language then
    language=pending_language;pending_language=nil;pref('language',language)
    modal=nil;open_modal=nil;tab_rename=nil;UI.info=nil;UI.menu_open=nil
  end
  if pending_theme then
    theme=pending_theme;pending_theme=nil;pref('theme',theme)
  end
  local before=session and {raw=session.raw,active=session.active,allow_invalid=session.history_readonly} or nil
  frame_checkpoint=session and {session=session,raw=session.raw} or nil
  if session and not session.error and not session.conflict then
    session.write_attempt=nil;session.write_stage=nil
  end
  if not ctx then
    ctx=ImGui.CreateContext(CONTEXT_NAME,ImGui.ConfigFlags_DockingEnable|ImGui.ConfigFlags_NavEnableKeyboard)
    ImGui.SetConfigVar(ctx,ImGui.ConfigVar_InputTextCursorBlink,1)
    font=ImGui.CreateFont('sans-serif')
    ImGui.Attach(ctx,font)
    input_callback=ImGui.CreateFunctionFromEEL('seen=1; cursor=CursorPos; first=SelectionStart; last=SelectionEnd;')
    ImGui.Attach(ctx,input_callback)
  end
  ui_font=ImGui.GetFont(ctx)
  UI_METRICS.font_size=ImGui.GetFontSize(ctx)
  local warming=startup_layout_frames<STARTUP_LAYOUT_FRAMES
  -- A tiny nonzero alpha quantizes to transparent, but still allows ImGui to
  -- measure children (Alpha==0 may skip their layout). Viewer startup pattern.
  if warming then ImGui.PushStyleVar(ctx,ImGui.StyleVar_Alpha,0.001) end
  local nc=styles()
  ImGui.PushFont(ctx,ui_font,UI_METRICS.font_size)
  ImGui.SetNextWindowSize(ctx,840,560,ImGui.Cond_FirstUseEver)
  ImGui.SetNextWindowSizeConstraints(ctx,540,360,10000,10000)
  if dock_request~=nil then ImGui.SetNextWindowDockID(ctx,dock_request,ImGui.Cond_Always); dock_request=nil end
  local project=reaper.EnumProjects(-1,'')
  local project_name=project and reaper.GetProjectName(project,'') or ''
  local window_title=TITLE..' — '..(project_name~='' and label(project_name) or tr('Untitled project'))
  ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,4,math.max(0,(38-ImGui.GetTextLineHeight(ctx))*0.5))
  local visible,opened=ImGui.Begin(ctx,window_title..'###Patch34ProjectNotes',true,ImGui.WindowFlags_MenuBar)
  ImGui.PopStyleVar(ctx)
  if visible then
    -- Invalidate active text widgets after external reload/project switch.
    ImGui.PushID(ctx,epoch)
    escape_pressed=ImGui.IsKeyPressed(ctx,ImGui.Key_Escape,false)
    if warming then ImGui.BeginDisabled(ctx,true) else history_shortcuts() end
    menu_bar()
    local switching=scope_selector()
    if bulk_selection and not editing then bulk_selection=nil end
    header_context()
    if switching then ImGui.TextDisabled(ctx,tr('Switching note owner...'))
    elseif not session then ImGui.TextWrapped(ctx,UI.message(selection_message or 'Select an object in REAPER.'))
    elseif session.error or session.conflict then problem_view()
    else
      if session.target.kind~='project' then ImGui.TextWrapped(ctx,UI.owner_title(session.target)) end
      draw_document()
    end
    if session and not switching then draw_modal() end
    UI.info_window()
    if warming then ImGui.EndDisabled(ctx) end
    ImGui.PopID(ctx)
    ImGui.End(ctx)
  end
  ImGui.PopFont(ctx); ImGui.PopStyleVar(ctx,7); ImGui.PopStyleColor(ctx,nc)
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
  if session and (undo_boundary or not editing) then session.history.key=nil end
  if session and (undo_boundary or (session.undo_due and reaper.time_precise()>=session.undo_due)) then flush_undo(session) end
  if history_request and can_history(history_request) then
    flush_undo(session)
    local ok,err=M.history_step(session,api,history_request)
    if ok then
      epoch=epoch+1; bulk_selection=nil; modal=nil; open_modal=nil; tab_rename=nil; session.pending=nil
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
  for _,s in pairs(sessions) do
    if s.dirty and not s.recovery then pcall(save_recovery,s,'Closed with an unsaved draft / Закрыто с несохранённым черновиком') end
    pcall(flush_undo,s)
  end
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
      local pending=s==session and (tab_rename or modal) or nil
      pcall(save_recovery,s,keep,baseline,pending)
    end
    recover(session)
    for _,s in pairs(sessions) do if s.dirty then recover(s) end end
    pcall(reaper.ShowConsoleMsg,TITLE..'\n'..tostring(keep)..'\n')
    local message=language=='ru' and
      'Скрипт остановлен. Аварийной записи в заметки не было.\nЕсли сбой произошёл внутри записи REAPER, проверь заметки.\nПути к аварийным копиям или ошибки их сохранения — в консоли.\nПосле перезапуска: Правка → Открыть аварийную копию.' or
      'The script stopped. The error handler did not write to native notes.\nIf REAPER failed during a write, inspect the native notes.\nRecovery paths or export errors are in the console.\nAfter restarting: Edit > Open recovery copy.'
    pcall(reaper.MB,message,TITLE,0)
    return
  end
  if keep then reaper.defer(loop) end
end
reaper.defer(loop)
