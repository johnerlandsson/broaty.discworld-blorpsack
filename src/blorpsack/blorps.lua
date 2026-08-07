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

local function to_wire(data)
  local list = {}
  for name, room_id in pairs(data) do
    list[#list + 1] = { room_id = room_id, name = name }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

local function broadcast()
  local payload = { blorps = to_wire(load_data()) }
  events.emit(EVENT_BLORPS, payload)
  panel:post("blorps_list", payload)
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
  data[name] = state.current_room
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
