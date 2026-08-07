-- src/blorpsack/panel.lua
-- Custom iframe panel: dispatches "ready"/"add"/"remove" messages from
-- ui/panel.js onto blorps.lua's same add/remove/list functions the /blorp
-- command uses. This is a convenience layer, not a second code path.

local M = {}

M.panel = mud.panel("blorps")

-- injected via M.init()
local colors, state, blorps
local C, note

function M.init(deps)
  colors, state, blorps = deps.colors, deps.state, deps.blorps
  C, note = colors.C, colors.note
end

M.panel:on_message("ready", function()
  M.panel:post("blorps_list", { blorps = blorps.list() })
  M.panel:post("room_changed", { room_id = state.current_room })
end)

M.panel:on_message("add", function(data)
  local ok, err = blorps.add(data and data.name)
  if not ok then
    note('  ' .. err, C.err)
  end
end)

M.panel:on_message("remove", function(data)
  local ok, err = blorps.remove(data and data.name)
  if not ok then
    note('  ' .. err, C.err)
  end
end)

return M
