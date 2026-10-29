-- @description ReaNotepad
-- @version 0.5.0
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
--   Each column has an Add widget menu and rename/move/delete actions.
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
    while i <= #ls do
      local l = ls[i]
      if l:sub(1,5) == '@tab ' and not tab then
        tab = M.tab(unesc(l:sub(6))); doc.tabs[#doc.tabs+1] = tab
        if legacy then column=tab.columns[1] else tab.columns={} end
      elseif l:sub(1,8) == '@column ' and tab and not column and not legacy then
        column=M.column(unesc(l:sub(9))); tab.columns[#tab.columns+1]=column
      elseif l == '@endcolumn' and column and not legacy then column=nil
      elseif l == '@endtab' and tab then
        assert(legacy or not column, 'Unclosed column.')
        assert(#tab.columns>0, 'Tab has no columns.')
        assert(#tab.columns<=8, 'A tab supports up to 8 columns.')
        tab=nil; column=nil
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
      i = i + 1
    end
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
      'ReaNotepad 0.5.0 — recovery / аварийная копия',
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
  epoch=epoch+1; modal=nil; open_modal=nil; tab_rename=nil
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
    epoch=epoch+1;modal=nil;open_modal=nil;tab_rename=nil;force_tab=nil
  end
  local chosen=target and sessions[target.key]
  if chosen and chosen~=session and not api.valid(chosen.target) then
    discard_removed_session(chosen);sessions[target.key]=nil
  end
  M.sweep_sessions(sessions,session_sweep,session,api.valid,discard_removed_session,SESSION_CHECKS_PER_FRAME)
  if not target then
    if session then
      flush_undo(session);M.suspend_session(session);session=nil
      epoch=epoch+1; modal=nil; open_modal=nil; tab_rename=nil; force_tab=nil
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
    epoch=epoch+1; modal=nil; open_modal=nil; tab_rename=nil; force_tab=nil
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
function UI.read_text(text,owner)
  local width=ImGui.GetContentRegionAvail(ctx)
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
  local texts={TITLE,tr('Version: ')..'0.5.0',
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
        ImGui.TextDisabled(ctx,tr('Version: ')..'0.5.0')
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
local function column_header(tab,column,index)
  local width=ImGui.GetContentRegionAvail(ctx)
  local layout=UI.column_header_layout(width,tr('Add'))
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
    -- Reserve identical control geometry in both modes, including narrow columns.
    if editing then
      if UI.button(ctx,ui_label('Add'),true) then ImGui.OpenPopup(ctx,'column_add') end
      if begin_action_popup('column_add') then add_menu(column); ImGui.EndPopup(ctx) end
      if not layout.stacked then ImGui.SameLine(ctx,0,UI_METRICS.item_gap_x) end
      if UI.button(ctx,ui_label('...##column'),true) then ImGui.OpenPopup(ctx,'column_actions') end
      if begin_action_popup('column_actions') then
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
      ImGui.Dummy(ctx,layout.add_width,layout.add_height)
      if not layout.stacked then ImGui.SameLine(ctx,0,UI_METRICS.item_gap_x) end
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
            draw_block(tab,column,b,i)
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
      epoch=epoch+1; modal=nil; open_modal=nil; tab_rename=nil; session.pending=nil
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
