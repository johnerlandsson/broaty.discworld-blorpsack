-- src/blorpsack/state.lua
-- Current room and character name, tracked the same way cowtography's own
-- gmcp.lua does: gmcp.on(...) handlers registered at module load time,
-- closing over a `panel` upvalue that M.init() fills in before any GMCP
-- event can actually fire.

local M = {
  current_room      = nil,
  current_room_name = nil,
  char_name         = nil,
}

-- injected via M.init(); panel is panel_mod.panel — the mud.panel() handle
local panel, blorps

local function post_room_changed()
  if panel then
    panel:post("room_changed", { room_id = M.current_room, room_name = M.current_room_name })
  end
end

local function apply_room(identifier, name)
  if name == '' then name = nil end
  if not identifier then return end
  if identifier ~= M.current_room then
    M.current_room, M.current_room_name = identifier, name
    post_room_changed()
  elseif name and name ~= M.current_room_name then
    M.current_room_name = name
    post_room_changed()
  end
end

-- blorps.lua's storage key is derived from char_name (see its `key()`),
-- which only resolves once Discworld's char.info GMCP frame arrives —
-- sometime after connect, not synchronously at plugin load. If anything
-- already read blorps.list()/broadcast() before that (e.g. the panel's
-- one-time "ready" handshake), it saw the wrong (fallback) key's data
-- and nothing would ever correct it without this refresh.
local function apply_char_name(name)
  if type(name) ~= 'string' or name == '' then return end
  if name ~= M.char_name then
    M.char_name = name
    if blorps then blorps.refresh() end
  end
end

local function seed_room()
  local raw = gmcp.get("room.info")
  if raw then
    apply_room(raw:match('"identifier"%s*:%s*"([^"]+)"'), raw:match('"name"%s*:%s*"([^"]*)"'))
  end
end

function M.init(deps)
  panel = deps.panel.panel
  blorps = deps.blorps
  seed_room()
  world.on("connect", seed_room)
  apply_char_name(gmcp.get('char.info.capname'))
end

gmcp.on('room.info', function(_, data)
  if type(data) == 'table' then apply_room(data.identifier, data.name) end
end)

gmcp.on('char.info', function(_, data)
  if type(data) == 'table' then apply_char_name(data.capname) end
end)

return M
