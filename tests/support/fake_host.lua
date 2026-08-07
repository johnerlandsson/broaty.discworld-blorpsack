-- tests/support/fake_host.lua
-- Minimal fakes for the Mallard host globals (storage, events, gmcp, world,
-- mud) so blorpsack's Lua modules can be required and driven under a plain
-- `lua` interpreter, without a real Mallard runtime.
--
-- IMPORTANT: call fake_host.install() exactly once per test file, BEFORE
-- requiring any blorpsack.* module. Standard Lua's require() (unlike
-- Mallard's own no-cache plugin sandbox) caches modules, so a module's
-- top-level gmcp.on/world.on/events.on/mud.command/mud.panel calls bind to
-- whichever _G.gmcp/_G.world/_G.events/_G.mud table existed at require
-- time. A second install() later in the same file creates new tables the
-- already-required module never registered against.

local M = {}

local function new_panel(id)
  local posts = {}
  local handlers = {}
  local handle = {}
  function handle:post(name, data)
    posts[#posts + 1] = { name = name, data = data }
  end
  function handle:on_message(name, fn)
    handlers[name] = fn
  end
  function handle:fire(name, data)
    if handlers[name] then handlers[name](data) end
  end
  return handle, posts
end
M.new_panel = new_panel

function M.install()
  local storage_data    = {}
  local storage_sets    = {}
  local event_listeners = {}
  local event_emits     = {}
  local gmcp_listeners  = {}
  local gmcp_values     = {}
  local world_listeners = {}
  local commands        = {}
  local notes           = {}
  local panels          = {}

  _G.storage = {
    get = function(k) return storage_data[k] end,
    set = function(k, v)
      storage_data[k] = v
      storage_sets[#storage_sets + 1] = { key = k, value = v }
    end,
    has = function(k) return storage_data[k] ~= nil end,
    delete = function(k) storage_data[k] = nil end,
    keys = function()
      local ks = {}
      for k in pairs(storage_data) do ks[#ks + 1] = k end
      return ks
    end,
  }

  _G.events = {
    on = function(name, fn)
      event_listeners[name] = event_listeners[name] or {}
      event_listeners[name][#event_listeners[name] + 1] = fn
      return { remove = function() end }
    end,
    emit = function(name, data)
      event_emits[#event_emits + 1] = { name = name, data = data }
      for _, fn in ipairs(event_listeners[name] or {}) do fn(data) end
    end,
  }

  _G.gmcp = {
    on = function(prefix, fn)
      gmcp_listeners[prefix] = gmcp_listeners[prefix] or {}
      gmcp_listeners[prefix][#gmcp_listeners[prefix] + 1] = fn
      return { remove = function() end }
    end,
    get = function(path) return gmcp_values[path] end,
  }

  _G.world = {
    on = function(event, fn)
      world_listeners[event] = world_listeners[event] or {}
      world_listeners[event][#world_listeners[event] + 1] = fn
    end,
  }

  _G.mud = {
    command = function(name, fn, _opts)
      commands[name] = fn
      return { remove = function() end }
    end,
    command_prefix = function() return '/' end,
    note = function(...)
      notes[#notes + 1] = { ... }
    end,
    span = function(text, _opts) return text end,
    panel = function(id)
      local handle, posts = new_panel(id)
      panels[id] = { handle = handle, posts = posts }
      return handle
    end,
  }

  return {
    storage_data = storage_data,
    storage_sets = storage_sets,
    event_emits  = event_emits,
    commands     = commands,
    notes        = notes,
    panels       = panels,
    gmcp_values  = gmcp_values,
    fire_gmcp = function(prefix, data)
      for _, fn in ipairs(gmcp_listeners[prefix] or {}) do fn(prefix, data) end
    end,
    fire_world = function(event)
      for _, fn in ipairs(world_listeners[event] or {}) do fn() end
    end,
    fire_event = function(name, data)
      for _, fn in ipairs(event_listeners[name] or {}) do fn(data) end
    end,
  }
end

return M
