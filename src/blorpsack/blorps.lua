-- src/blorpsack/blorps.lua
-- Blorp storage CRUD, the cross-plugin broadcast, and the .request
-- listener. No in-memory cache: every function reads storage.get() fresh,
-- so there's nothing to hydrate or invalidate.

local M = {}

local EVENT_BLORPS  = "broaty.discworld-blorpsack.blorps"
local EVENT_REQUEST = "broaty.discworld-blorpsack.blorps.request"

-- injected via M.init(); panel is panel_mod.panel — the mud.panel() handle
local state, panel

local function key()
  return state.char_name and ('blorps_' .. state.char_name) or 'blorps'
end

local function load_data()
  return storage.get(key()) or {}
end

local function save_data(data)
  storage.set(key(), data)
end

-- Each stored entry is normally { room_id = ..., room_name = ... }. Older
-- entries written before room_name existed are a plain room_id string —
-- read as room_id with room_name = nil rather than migrated.
local function to_wire(data)
  local list = {}
  for name, entry in pairs(data) do
    local room_id, room_name
    if type(entry) == 'table' then
      room_id, room_name = entry.room_id, entry.room_name
    else
      room_id = entry
    end
    list[#list + 1] = { room_id = room_id, name = name, room_name = room_name }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function broadcast()
  if not (state and panel) then return end
  local list = to_wire(load_data())
  local wire = {}
  for _, b in ipairs(list) do
    wire[#wire + 1] = { room_id = b.room_id, name = b.name }
  end
  events.emit(EVENT_BLORPS, { blorps = wire })
  panel:post("blorps_list", { blorps = list })
end

function M.init(deps)
  state = deps.state
  panel = deps.panel.panel
end

function M.list()
  return to_wire(load_data())
end

function M.add(name)
  if type(name) ~= 'string' or name == '' then
    return false, "Blorp name required."
  end
  if state.current_room == nil then
    return false, "Current room unknown. Move through a mapped room first."
  end
  local data = load_data()
  data[name] = { room_id = state.current_room, room_name = state.current_room_name }
  save_data(data)
  broadcast()
  return true
end

function M.remove(name)
  local data = load_data()
  if data[name] == nil then
    return false, string.format('No blorp named "%s".', tostring(name))
  end
  data[name] = nil
  save_data(data)
  broadcast()
  return true
end

events.on(EVENT_REQUEST, broadcast)

return M
