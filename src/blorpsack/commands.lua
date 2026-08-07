-- src/blorpsack/commands.lua
-- The /blorp command: list, add, and remove blorps.

local M = {}

-- injected via M.init()
local colors, state, blorps
local C, note

function M.init(deps)
  colors, state, blorps = deps.colors, deps.state, deps.blorps
  C, note = colors.C, colors.note
end

local function print_list()
  local list = blorps.list()
  if #list == 0 then
    note('  No blorps registered.', C.muted)
    return
  end
  note('  Blorps:', C.header)
  for _, b in ipairs(list) do
    note(string.format('  %-20s %s', b.name, b.room_id), C.alt)
  end
end

mud.command("blorp", function(m)
  local args = m.args

  if args == '' then
    print_list()
    return
  end

  local add_name = args:match('^add%s+(.+)$')
  if add_name then
    local ok, err = blorps.add(add_name)
    if ok then
      note(string.format('  Registered blorp "%s" at %s.', add_name, tostring(state.current_room)), C.ok)
    else
      note('  ' .. err, C.err)
    end
    return
  end

  local rm_name = args:match('^rm%s+(.+)$')
  if rm_name then
    local ok, err = blorps.remove(rm_name)
    if ok then
      note(string.format('  Removed blorp "%s".', rm_name), C.ok)
    else
      note('  ' .. err, C.err)
    end
    return
  end

  note(string.format('  Usage: %sblorp [add <name>|rm <name>]', mud.command_prefix()), C.err)
end, {
  description = "List, add, and remove blorps (location-remembering jewellery).",
  usage       = "blorp [add <name>|rm <name>]",
})

return M
