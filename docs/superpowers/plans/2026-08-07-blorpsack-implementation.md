# Blorpsack Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the blorpsack Mallard plugin: track blorps (location-remembering jewellery) per Discworld character via `/blorp` commands and an optional panel, and broadcast the list over `events.on`/`events.emit` for other plugins (e.g. cowtography) to consume.

**Architecture:** A handful of small Lua modules under `src/blorpsack/`, required exactly once each from a thin `src/main.lua` entry point and wired together via `init(deps)` calls (Mallard's plugin `require()` has no caching, so every module is required from exactly one place — see cowtography's `src/main.lua` for the precedent this follows). `state.lua` tracks the current room/character from GMCP; `blorps.lua` owns storage, the cross-plugin broadcast, and the `.request` listener; `commands.lua` and `panel.lua` are two thin, equivalent front ends onto `blorps.lua`'s functions — neither duplicates the CRUD logic. A custom iframe panel (`ui/panel.*`) talks to `panel.lua` via `panel:post`/`panel:on_message`.

**Tech Stack:** Lua (Mallard plugin runtime), plain HTML/CSS/JS for the panel iframe, plain `lua`-interpreter unit tests (no test framework — matches cowtography's `tests/*.lua` convention), zero npm dependencies.

## Global Constraints

- Plugin id: `broaty.discworld-blorpsack` (exact string, used in manifest and in both event names below).
- `mallard_api_version = "1.0"`, `minimum_app_version = "0.24.0"` (plugin.toml).
- Worlds: `match = ["discworld.starturtle.net:*"]`.
- Permissions: `gmcp_access = ["room.info", "char.info", "char.info.capname"]` only — no `sends`, `database`, `keychain`, or `notifications`.
- Command word: `/blorp`, verbs `add <name>` / `rm <name>` / bare (list). `add` silently overwrites an existing name's room id — that overwrite *is* the update case, no separate rename.
- Cross-plugin broadcast event: `broaty.discworld-blorpsack.blorps`, payload `{ blorps = { { room_id = "...", name = "..." }, ... } }`. Emitted only after a successful `add`/`rm`, or in response to the request event below — **never** at plugin load.
- Request event: `broaty.discworld-blorpsack.blorps.request` — blorpsack listens and re-emits the broadcast above; payload ignored.
- Storage key: `'blorps_' .. char_name`, falling back to `'blorps'` before `char_name` is known (mirrors cowtography's `bm_<char_name>` bookmark keying).
- Panel id: `"blorps"` (`mud.panel("blorps")`), manifest panel key `[panels.blorps]`, entry `ui/panel.html`.
- The panel is a pure convenience layer: every panel action (list/add/remove) has an equivalent command, and vice versa. No functionality in this plan requires opening the panel.
- Spec: `docs/superpowers/specs/2026-08-07-blorpsack-design.md` — this plan implements it in full; consult it for rationale, not just this plan.

---

## File Structure

```
plugin.toml
.gitignore
package.json
README.md
src/main.lua                    -- entry point: require + wire init(deps)
src/blorpsack/colors.lua        -- note colours + mud.note wrapper
src/blorpsack/state.lua         -- current_room, char_name, GMCP handlers
src/blorpsack/blorps.lua        -- storage CRUD, broadcast, .request listener
src/blorpsack/commands.lua      -- /blorp command
src/blorpsack/panel.lua         -- mud.panel("blorps") handle + message dispatch
ui/panel.html
ui/panel.css
ui/panel.js
tests/support/fake_host.lua     -- fakes for storage/events/gmcp/world/mud globals
tests/fake_host_test.lua
tests/state_test.lua
tests/blorps_init_test.lua
tests/blorps_test.lua
tests/commands_test.lua
tests/panel_test.lua
tests/main_test.lua
```

---

### Task 1: Scaffold plugin metadata and directories

**Files:**
- Create: `plugin.toml`
- Create: `.gitignore`

**Interfaces:**
- Produces: the manifest every later task's code must satisfy (id, permissions, panel declaration — see Global Constraints above). No Lua interfaces yet.

- [ ] **Step 1: Create `plugin.toml`**

```toml
id                  = "broaty.discworld-blorpsack"
name                = "Discworld Blorpsack"
version             = "0.1.0"
description         = "Tracks blorps (location-remembering jewellery) in your inventory and broadcasts the list for other plugins to route to."
language            = "lua"
entry               = "src/main.lua"
mallard_api_version = "1.0"
minimum_app_version = "0.24.0"
authors             = ["John Erlandsson"]
license             = "MIT"

[worlds]
match = ["discworld.starturtle.net:*"]

[permissions]
gmcp_access = ["room.info", "char.info", "char.info.capname"]

[panels.blorps]
title        = "Blorpsack"
entry        = "ui/panel.html"
default_dock = "right"
default_size = { width = 280, height = 320 }
```

- [ ] **Step 2: Create `.gitignore`**

```
node_modules/
*.mallardx
.superpowers/
```

- [ ] **Step 3: Verify the files exist**

Run: `cat plugin.toml && cat .gitignore`
Expected: both files print with the exact content above.

- [ ] **Step 4: Commit**

```bash
git add plugin.toml .gitignore
git commit -m "$(cat <<'EOF'
Scaffold blorpsack plugin manifest

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Test harness — `fake_host.lua`

**Files:**
- Create: `tests/support/fake_host.lua`
- Test: `tests/fake_host_test.lua`

**Interfaces:**
- Produces:
  - `fake_host.install() -> H`, where `H` is a table with:
    - `H.storage_data` — raw table backing `storage.get/set` (string key → JSON-serializable Lua value), for direct seeding/assertion.
    - `H.storage_sets` — array of `{ key, value }` recording every `storage.set` call in order.
    - `H.event_emits` — array of `{ name, data }` recording every `events.emit` call in order.
    - `H.commands` — table mapping command name (string) → the registered handler function, so tests can call e.g. `H.commands.blorp({ args = "add market" })` directly.
    - `H.notes` — array of argument-lists from every `mud.note(...)` call (each entry is itself an array/table of the positional args passed).
    - `H.panels` — table mapping panel id (string) → `{ handle = <panel handle>, posts = <array> }` for every `mud.panel(id)` call made while this `H` is installed.
    - `H.gmcp_values` — settable table mapping GMCP path (string) → the raw string `gmcp.get(path)` should return; tests write into it before triggering code that calls `gmcp.get`.
    - `H.fire_gmcp(prefix, data)` — invokes every `gmcp.on(prefix, fn)` handler registered for that exact `prefix`, calling `fn(prefix, data)`.
    - `H.fire_world(event)` — invokes every `world.on(event, fn)` handler registered for that event, calling `fn()`.
    - `H.fire_event(name, data)` — invokes every `events.on(name, fn)` handler registered for that name, calling `fn(data)` (same dispatch `events.emit` itself uses).
  - `fake_host.new_panel(id) -> handle, posts` — a standalone fake panel handle (same shape `mud.panel(id)` produces internally), for tests that need to hand a `deps.panel = { panel = handle }`-shaped stand-in to a module under test without going through the global `mud.panel` factory. `handle:post(name, data)` appends `{ name, data }` to `posts`. `handle:on_message(name, fn)` records `fn` under `name`. `handle:fire(name, data)` invokes the recorded handler for `name` (no-op if none registered).
  - Calling `fake_host.install()` replaces the globals `storage`, `events`, `gmcp`, `world`, and `mud` (with `.command`, `.command_prefix`, `.note`, `.span`, `.panel`) for the remainder of the process. Each call installs **fresh** tables — see the note in Step 1 about calling it exactly once per test file, before requiring any `blorpsack.*` module.

- [ ] **Step 1: Write `tests/support/fake_host.lua`**

```lua
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
```

- [ ] **Step 2: Write `tests/fake_host_test.lua`**

```lua
-- Run from project root: lua tests/fake_host_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('storage set/get round-trips and records the set', function()
  local H = fake_host.install()
  storage.set('k', { a = 1 })
  assert(storage.get('k').a == 1)
  assert(H.storage_data.k.a == 1)
  assert(H.storage_sets[1].key == 'k')
end)

test('storage delete clears the value', function()
  local H = fake_host.install()
  storage.set('k', 'v')
  storage.delete('k')
  assert(storage.get('k') == nil)
  assert(storage.has('k') == false)
end)

test('events.on/emit dispatches to the listener and records the emit', function()
  local H = fake_host.install()
  local seen = nil
  events.on('foo', function(data) seen = data end)
  events.emit('foo', { x = 1 })
  assert(seen.x == 1)
  assert(H.event_emits[1].name == 'foo')
end)

test('gmcp.on fires via fire_gmcp', function()
  local H = fake_host.install()
  local seen
  gmcp.on('room.info', function(_prefix, data) seen = data end)
  H.fire_gmcp('room.info', { identifier = 'r1' })
  assert(seen.identifier == 'r1')
end)

test('gmcp.get returns a seeded value', function()
  local H = fake_host.install()
  H.gmcp_values['char.info.capname'] = 'Dilbo'
  assert(gmcp.get('char.info.capname') == 'Dilbo')
end)

test('world.on fires via fire_world', function()
  local H = fake_host.install()
  local fired = false
  world.on('connect', function() fired = true end)
  H.fire_world('connect')
  assert(fired == true)
end)

test('mud.command registers a callable handler', function()
  local H = fake_host.install()
  mud.command('blorp', function(m) return m.args end, { description = 'x' })
  assert(H.commands.blorp({ args = 'hi' }) == 'hi')
end)

test('mud.note records its call', function()
  local H = fake_host.install()
  mud.note('  hello', { fg = '#fff' })
  assert(H.notes[1][1] == '  hello')
end)

test('mud.panel creates a trackable fake handle', function()
  local H = fake_host.install()
  local p = mud.panel('blorps')
  p:on_message('ready', function(_data) end)
  p:post('blorps_list', { blorps = {} })
  assert(H.panels.blorps.posts[1].name == 'blorps_list')
  H.panels.blorps.handle:fire('ready', {})
end)

test('new_panel produces an independent handle', function()
  local handle, posts = fake_host.new_panel('x')
  handle:post('a', { n = 1 })
  assert(posts[1].name == 'a')
  local received
  handle:on_message('b', function(data) received = data end)
  handle:fire('b', { n = 2 })
  assert(received.n == 2)
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 3: Run the test and verify it passes**

Run: `lua tests/fake_host_test.lua`
Expected: every line prints `PASS: ...`, ending with `10 tests passed.`

- [ ] **Step 4: Commit**

```bash
git add tests/support/fake_host.lua tests/fake_host_test.lua
git commit -m "$(cat <<'EOF'
Add fake_host test harness for blorpsack's Lua modules

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `state.lua` — room and character tracking

**Files:**
- Create: `src/blorpsack/state.lua`
- Test: `tests/state_test.lua`

**Interfaces:**
- Consumes: `fake_host` (Task 2) in its test only. In production, consumes `deps.panel` passed to `M.init`, expected to be a table with a `.panel` field (the `mud.panel(...)` handle from Task 6, exposing `:post(name, data)`).
- Produces: module `blorpsack.state` (`require('blorpsack.state')`) with:
  - `M.current_room` — string or `nil`. Set from GMCP `room.info`'s `identifier` field (both live events and hydration via `gmcp.get`).
  - `M.char_name` — string or `nil`. Set from GMCP `char.info`'s `capname` field (both live events and hydration via `gmcp.get('char.info.capname')`).
  - `M.init(deps)` — `deps.panel.panel` must support `:post(name, data)`. Hydrates `current_room`/`char_name` and registers `world.on("connect", ...)` for reconnect re-hydration.
  - Side effect on `require`: registers `gmcp.on('room.info', ...)` and `gmcp.on('char.info', ...)` at module load time (top-level, mirroring cowtography's `gmcp.lua`). These reference `panel` via an upvalue set later in `M.init` — safe because no GMCP event fires between `require` and `M.init` during normal plugin load (see Task 7).
  - Posts `panel:post("room_changed", { room_id = M.current_room })` whenever `current_room` actually changes (not on every GMCP `room.info` frame — only when the identifier differs from the previous value).

- [ ] **Step 1: Write the failing test — `tests/state_test.lua`**

```lua
-- Run from project root: lua tests/state_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local panel_handle, panel_posts = fake_host.new_panel('blorps')

H.gmcp_values['char.info.capname'] = 'Dilbo'

local state = require('blorpsack.state')
state.init({ panel = { panel = panel_handle } })

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('init hydrates char_name from gmcp.get', function()
  assert(state.char_name == 'Dilbo')
end)

test('room.info gmcp event sets current_room and posts room_changed', function()
  H.fire_gmcp('room.info', { identifier = 'r1' })
  assert(state.current_room == 'r1')
  assert(panel_posts[#panel_posts].name == 'room_changed')
  assert(panel_posts[#panel_posts].data.room_id == 'r1')
end)

test('room.info gmcp event with the same id does not re-post', function()
  local before = #panel_posts
  H.fire_gmcp('room.info', { identifier = 'r1' })
  assert(#panel_posts == before)
end)

test('room.info gmcp event with a new id updates and posts again', function()
  H.fire_gmcp('room.info', { identifier = 'r2' })
  assert(state.current_room == 'r2')
  assert(panel_posts[#panel_posts].data.room_id == 'r2')
end)

test('char.info gmcp event updates char_name', function()
  H.fire_gmcp('char.info', { capname = 'Rincewind' })
  assert(state.char_name == 'Rincewind')
end)

test('world connect reseeds current_room from gmcp.get', function()
  H.gmcp_values['room.info'] = '{"identifier":"r9","name":"Somewhere"}'
  H.fire_world('connect')
  assert(state.current_room == 'r9')
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/state_test.lua`
Expected: FAIL (or a Lua error) — `blorpsack.state` doesn't exist yet.

- [ ] **Step 3: Write `src/blorpsack/state.lua`**

```lua
-- src/blorpsack/state.lua
-- Current room and character name, tracked the same way cowtography's own
-- gmcp.lua does: gmcp.on(...) handlers registered at module load time,
-- closing over a `panel` upvalue that M.init() fills in before any GMCP
-- event can actually fire.

local M = {
  current_room = nil,
  char_name    = nil,
}

-- injected via M.init(); panel is panel_mod.panel — the mud.panel() handle
local panel

local function post_room_changed()
  if panel then panel:post("room_changed", { room_id = M.current_room }) end
end

local function apply_room(identifier)
  if identifier and identifier ~= M.current_room then
    M.current_room = identifier
    post_room_changed()
  end
end

local function apply_char_name(name)
  if type(name) == 'string' and name ~= '' then
    M.char_name = name
  end
end

local function seed_room()
  local raw = gmcp.get("room.info")
  if raw then
    apply_room(raw:match('"identifier"%s*:%s*"([^"]+)"'))
  end
end

function M.init(deps)
  panel = deps.panel.panel
  seed_room()
  world.on("connect", seed_room)
  apply_char_name(gmcp.get('char.info.capname'))
end

gmcp.on('room.info', function(_, data)
  if type(data) == 'table' then apply_room(data.identifier) end
end)

gmcp.on('char.info', function(_, data)
  if type(data) == 'table' then apply_char_name(data.capname) end
end)

return M
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `lua tests/state_test.lua`
Expected: `6 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/blorpsack/state.lua tests/state_test.lua
git commit -m "$(cat <<'EOF'
Add blorpsack.state: room and character tracking

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `blorps.lua` — storage CRUD, broadcast, and `.request`

**Files:**
- Create: `src/blorpsack/blorps.lua`
- Test: `tests/blorps_init_test.lua`
- Test: `tests/blorps_test.lua`

**Interfaces:**
- Consumes: `deps.state` — a table with readable `.current_room` (string|nil) and `.char_name` (string|nil) fields. `deps.panel` — a table with a `.panel` field supporting `:post(name, data)`.
- Produces: module `blorpsack.blorps` with:
  - `M.init(deps)` — stores `state`/`panel` references. Performs **no** storage read/broadcast itself (there is no in-memory cache — every call below reads `storage.get(...)` fresh, so "hydration" is simply that the data is already there to read).
  - `M.list() -> array` of `{ room_id = <string>, name = <string> }`, sorted by `name`. Pure read, no side effects.
  - `M.add(name) -> ok:boolean, err:string|nil`. Fails (no storage write, no broadcast) if `name` isn't a non-empty string, or if `state.current_room == nil`. On success, sets `name -> state.current_room` in storage (overwriting if `name` already existed) and broadcasts.
  - `M.remove(name) -> ok:boolean, err:string|nil`. Fails if `name` isn't currently registered. On success, deletes it from storage and broadcasts.
  - Broadcast (on every successful `add`/`remove`, and on `broaty.discworld-blorpsack.blorps.request`): `events.emit("broaty.discworld-blorpsack.blorps", { blorps = M.list() })` and `panel:post("blorps_list", { blorps = M.list() })`.
  - Storage key: `'blorps_' .. state.char_name` if `state.char_name` is set, else `'blorps'`.

- [ ] **Step 1: Write the failing tests**

`tests/blorps_init_test.lua`:

```lua
-- Run from project root: lua tests/blorps_init_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

-- Seed storage as if a previous session already registered a blorp, before
-- blorpsack.blorps is ever required. blorps.lua keeps no in-memory cache —
-- it reads storage.get() fresh on every list()/add()/remove() call — so
-- "hydration" is just: the data is already there to read. This test's job
-- is to confirm requiring + initing the module does NOT itself broadcast.
H.storage_data['blorps'] = { armoury = 'r0' }

local panel_handle, panel_posts = fake_host.new_panel('blorps')
local state  = { current_room = nil, char_name = nil }
local blorps = require('blorpsack.blorps')
blorps.init({ state = state, panel = { panel = panel_handle } })

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('requiring and initing blorps performs no broadcast', function()
  assert(#H.event_emits == 0)
  assert(#panel_posts == 0)
end)

test('list reflects pre-existing storage data', function()
  local list = blorps.list()
  assert(#list == 1)
  assert(list[1].name == 'armoury')
  assert(list[1].room_id == 'r0')
end)

print(string.format('\n%d tests passed.', passed))
```

`tests/blorps_test.lua`:

```lua
-- Run from project root: lua tests/blorps_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local panel_handle, panel_posts = fake_host.new_panel('blorps')
local state  = { current_room = nil, char_name = nil }
local blorps = require('blorpsack.blorps')
blorps.init({ state = state, panel = { panel = panel_handle } })

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('add with unknown current_room errors and does not broadcast', function()
  state.current_room = nil
  local ok, err = blorps.add('market')
  assert(ok == false)
  assert(err:match('room unknown'))
  assert(#H.event_emits == 0)
  assert(#panel_posts == 0)
end)

test('add with an empty name errors', function()
  state.current_room = 'r1'
  local ok, err = blorps.add('')
  assert(ok == false)
  assert(err:match('name required'))
end)

test('add on a fresh name creates an entry and broadcasts once', function()
  state.current_room = 'r1'
  local ok = blorps.add('market')
  assert(ok == true)
  assert(#H.event_emits == 1)
  assert(H.event_emits[1].name == 'broaty.discworld-blorpsack.blorps')
  assert(#H.event_emits[1].data.blorps == 1)
  assert(H.event_emits[1].data.blorps[1].name == 'market')
  assert(H.event_emits[1].data.blorps[1].room_id == 'r1')
  assert(#panel_posts == 1)
  assert(panel_posts[1].name == 'blorps_list')
  assert(panel_posts[1].data.blorps[1].room_id == 'r1')
end)

test('add on an existing name overwrites the room id and broadcasts', function()
  state.current_room = 'r2'
  local ok = blorps.add('market')
  assert(ok == true)
  assert(#H.event_emits == 2)
  local list = blorps.list()
  assert(#list == 1)
  assert(list[1].room_id == 'r2')
end)

test('list returns entries sorted by name', function()
  state.current_room = 'r3'
  blorps.add('bank')
  local list = blorps.list()
  assert(#list == 2)
  assert(list[1].name == 'bank')
  assert(list[2].name == 'market')
end)

test('rm on an existing name removes it and broadcasts', function()
  local before = #H.event_emits
  local ok = blorps.remove('bank')
  assert(ok == true)
  assert(#H.event_emits == before + 1)
  local list = blorps.list()
  assert(#list == 1)
  assert(list[1].name == 'market')
end)

test('rm on an unknown name errors and does not broadcast', function()
  local before = #H.event_emits
  local ok, err = blorps.remove('nope')
  assert(ok == false)
  assert(err:match('No blorp named'))
  assert(#H.event_emits == before)
end)

test('storage keying changes when char_name becomes known', function()
  state.char_name = 'Dilbo'
  state.current_room = 'r4'
  blorps.add('bank2')
  assert(H.storage_data['blorps_Dilbo'] ~= nil)
  assert(H.storage_data['blorps_Dilbo'].bank2 == 'r4')
  -- the earlier, pre-char_name entry is untouched under the fallback key
  assert(H.storage_data['blorps'].market == 'r2')
end)

test('.request event triggers a broadcast reflecting the current key, without mutating storage', function()
  local before_emits = #H.event_emits
  local before_data  = H.storage_data['blorps_Dilbo']
  H.fire_event('broaty.discworld-blorpsack.blorps.request', {})
  assert(#H.event_emits == before_emits + 1)
  local emitted = H.event_emits[#H.event_emits]
  assert(emitted.data.blorps[1].name == 'bank2')
  assert(H.storage_data['blorps_Dilbo'] == before_data)
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `lua tests/blorps_init_test.lua && lua tests/blorps_test.lua`
Expected: FAIL — `blorpsack.blorps` doesn't exist yet.

- [ ] **Step 3: Write `src/blorpsack/blorps.lua`**

```lua
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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua tests/blorps_init_test.lua && lua tests/blorps_test.lua`
Expected: `2 tests passed.` then `9 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/blorpsack/blorps.lua tests/blorps_init_test.lua tests/blorps_test.lua
git commit -m "$(cat <<'EOF'
Add blorpsack.blorps: storage CRUD, broadcast, and .request listener

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: `colors.lua` + `commands.lua` — `/blorp` command

**Files:**
- Create: `src/blorpsack/colors.lua`
- Create: `src/blorpsack/commands.lua`
- Test: `tests/commands_test.lua`

**Interfaces:**
- Consumes: `blorpsack.state` (Task 3) — reads `state.current_room` for the confirmation message. `blorpsack.blorps` (Task 4) — calls `blorps.list()`, `blorps.add(name)`, `blorps.remove(name)`.
- Produces:
  - Module `blorpsack.colors` with `M.C` (table: `header`, `alt`, `err`, `ok`, `muted` — hex colour strings) and `M.note(text, colour)` (wraps `mud.note(text, { fg = colour or M.C.alt })`).
  - Module `blorpsack.commands` with `M.init(deps)` where `deps = { colors = <blorpsack.colors>, state = <blorpsack.state>, blorps = <blorpsack.blorps> }`. Registers `mud.command("blorp", fn, { description = ..., usage = ... })` at module load time.

- [ ] **Step 1: Write the failing test — `tests/commands_test.lua`**

```lua
-- Run from project root: lua tests/commands_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local colors = require('blorpsack.colors')
local panel_handle = fake_host.new_panel('blorps')
local state  = { current_room = nil, char_name = nil }
local blorps = require('blorpsack.blorps')
blorps.init({ state = state, panel = { panel = panel_handle } })

local commands = require('blorpsack.commands')
commands.init({ colors = colors, state = state, blorps = blorps })

local function invoke(args)
  H.commands.blorp({ args = args })
end

local function last_note()
  return H.notes[#H.notes][1]
end

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('bare /blorp with no blorps prints a message', function()
  invoke('')
  assert(last_note():match('No blorps registered'))
end)

test('/blorp add <name> with no known room errors', function()
  invoke('add market')
  assert(last_note():match('room unknown'))
  assert(#blorps.list() == 0)
end)

test('/blorp add with no name prints usage', function()
  invoke('add')
  assert(last_note():match('Usage: /blorp'))
end)

test('/blorp add <name> registers a blorp at the current room', function()
  state.current_room = 'r1'
  invoke('add market')
  assert(last_note():match('Registered blorp "market" at r1'))
  assert(#blorps.list() == 1)
end)

test('bare /blorp lists registered blorps', function()
  invoke('')
  assert(last_note():match('market'))
end)

test('/blorp rm <name> removes a blorp', function()
  invoke('rm market')
  assert(last_note():match('Removed blorp "market"'))
  assert(#blorps.list() == 0)
end)

test('/blorp rm <name> on an unknown name errors', function()
  invoke('rm market')
  assert(last_note():match('No blorp named "market"'))
end)

test('unrecognized args print usage', function()
  invoke('bogus')
  assert(last_note():match('Usage: /blorp'))
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/commands_test.lua`
Expected: FAIL — neither module exists yet.

- [ ] **Step 3: Write `src/blorpsack/colors.lua`**

```lua
-- src/blorpsack/colors.lua
-- Shared note colours and the mud.note wrapper, matching cowtography's own
-- colors.lua styling conventions.

local M = {}

M.C = {
  header = '#ffcc88',
  alt    = '#cccccc',
  err    = '#ff6666',
  ok     = '#aaffaa',
  muted  = '#888888',
}

function M.note(text, colour)
  mud.note(text, { fg = colour or M.C.alt })
end

return M
```

- [ ] **Step 4: Write `src/blorpsack/commands.lua`**

```lua
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `lua tests/commands_test.lua`
Expected: `8 tests passed.`

- [ ] **Step 6: Commit**

```bash
git add src/blorpsack/colors.lua src/blorpsack/commands.lua tests/commands_test.lua
git commit -m "$(cat <<'EOF'
Add blorpsack.colors and blorpsack.commands: /blorp command

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: `panel.lua` — panel message dispatch

**Files:**
- Create: `src/blorpsack/panel.lua`
- Test: `tests/panel_test.lua`

**Interfaces:**
- Consumes: `blorpsack.colors` (Task 5) — `colors.C`, `colors.note`. `blorpsack.state` (Task 3) — reads `state.current_room`. `blorpsack.blorps` (Task 4) — calls `blorps.list()`, `blorps.add(name)`, `blorps.remove(name)`.
- Produces: module `blorpsack.panel` with:
  - `M.panel` — the `mud.panel("blorps")` handle, created at module load time (this is what `state.lua`'s and `blorps.lua`'s `deps.panel = <this module>` argument exposes as `.panel`).
  - `M.init(deps)` where `deps = { colors = ..., state = ..., blorps = ... }`.
  - On message `"ready"` (no payload): posts `blorps_list` (`{ blorps = blorps.list() }`) then `room_changed` (`{ room_id = state.current_room }`).
  - On message `"add"` (`{ name = <string> }`): calls `blorps.add(data.name)`; on failure, prints an error note (same colour/style as the command path) — success needs no note, since the `blorps_list`/`room_changed` posts blorps.lua already emits are what update the panel's own display.
  - On message `"remove"` (`{ name = <string> }`): calls `blorps.remove(data.name)`; same error-note-only-on-failure behavior.

- [ ] **Step 1: Write the failing test — `tests/panel_test.lua`**

```lua
-- Run from project root: lua tests/panel_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local colors = require('blorpsack.colors')
local state  = { current_room = 'r1', char_name = nil }

-- Stub blorps: panel.lua's job is dispatching to blorps.add/blorps.remove
-- and formatting blorps.list() for the "ready" handshake, not re-testing
-- blorps.lua's own CRUD logic (that's covered in blorps_test.lua). A stub
-- lets these tests assert panel.lua calls the right function with the
-- right argument, independent of the real storage/broadcast machinery.
-- (Task 7's main_test.lua wires the REAL blorps.lua and proves commands
-- and the panel share one instance, not two divergent code paths.)
local blorps_calls = {}
local blorps = {
  list = function() return { { name = 'market', room_id = 'r1' } } end,
  add = function(name)
    blorps_calls[#blorps_calls + 1] = { fn = 'add', name = name }
    if name == 'fail' then return false, 'boom' end
    return true
  end,
  remove = function(name)
    blorps_calls[#blorps_calls + 1] = { fn = 'remove', name = name }
    if name == 'fail' then return false, 'boom' end
    return true
  end,
}

local panel = require('blorpsack.panel')
panel.init({ colors = colors, state = state, blorps = blorps })

local handle = H.panels.blorps.handle
local posts  = H.panels.blorps.posts

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('ready posts the current blorp list and current room', function()
  handle:fire('ready', {})
  assert(posts[1].name == 'blorps_list')
  assert(posts[1].data.blorps[1].name == 'market')
  assert(posts[2].name == 'room_changed')
  assert(posts[2].data.room_id == 'r1')
end)

test('add message calls blorps.add with the given name', function()
  handle:fire('add', { name = 'bank' })
  assert(blorps_calls[#blorps_calls].fn == 'add')
  assert(blorps_calls[#blorps_calls].name == 'bank')
end)

test('add message failure surfaces an error note', function()
  local before = #H.notes
  handle:fire('add', { name = 'fail' })
  assert(#H.notes == before + 1)
  assert(H.notes[#H.notes][1]:match('boom'))
end)

test('remove message calls blorps.remove with the given name', function()
  handle:fire('remove', { name = 'bank' })
  assert(blorps_calls[#blorps_calls].fn == 'remove')
  assert(blorps_calls[#blorps_calls].name == 'bank')
end)

test('remove message failure surfaces an error note', function()
  local before = #H.notes
  handle:fire('remove', { name = 'fail' })
  assert(#H.notes == before + 1)
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/panel_test.lua`
Expected: FAIL — `blorpsack.panel` doesn't exist yet.

- [ ] **Step 3: Write `src/blorpsack/panel.lua`**

```lua
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `lua tests/panel_test.lua`
Expected: `5 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/blorpsack/panel.lua tests/panel_test.lua
git commit -m "$(cat <<'EOF'
Add blorpsack.panel: panel message dispatch onto blorps.lua

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: `main.lua` — wire everything together

**Files:**
- Create: `src/main.lua`
- Test: `tests/main_test.lua`

**Interfaces:**
- Consumes: every module and `init(deps)` signature from Tasks 3–6.
- Produces: `src/main.lua`, the file `plugin.toml`'s `entry` points at. Requires every `blorpsack.*` module exactly once, then calls every module's `init(deps)`, in an order where each `deps` table is fully assembled from already-required (but not-yet-initialized) module tables — matching cowtography's own `main.lua` discipline: "every module's init() only stores references and/or registers deferred closures... call order here doesn't matter beyond every require above has already completed."

- [ ] **Step 1: Write the failing test — `tests/main_test.lua`**

```lua
-- Run from project root: lua tests/main_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

require('main')

local passed = 0
local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    print('PASS: ' .. name)
  else
    print('FAIL: ' .. name .. ' — ' .. tostring(err))
    os.exit(1)
  end
end

test('main wires a room.info GMCP event through to a successful /blorp add', function()
  H.fire_gmcp('room.info', { identifier = 'r1' })
  H.commands.blorp({ args = 'add market' })

  assert(#H.event_emits == 1)
  assert(H.event_emits[1].name == 'broaty.discworld-blorpsack.blorps')
  assert(H.event_emits[1].data.blorps[1].name == 'market')

  local panel_posts = H.panels.blorps.posts
  assert(panel_posts[#panel_posts].name == 'blorps_list')
  assert(panel_posts[#panel_posts].data.blorps[1].room_id == 'r1')

  assert(H.notes[#H.notes][1]:match('Registered blorp "market" at r1'))
end)

test('a panel "ready" message reflects the room the command already saw', function()
  H.panels.blorps.handle:fire('ready', {})
  local panel_posts = H.panels.blorps.posts
  assert(panel_posts[#panel_posts].name == 'room_changed')
  assert(panel_posts[#panel_posts].data.room_id == 'r1')
end)

test('a panel "add" message reaches the same blorps list a command would see', function()
  H.panels.blorps.handle:fire('add', { name = 'bank' })
  H.commands.blorp({ args = '' })
  assert(H.notes[#H.notes][1]:match('bank') or H.notes[#H.notes - 1][1]:match('bank'))
end)

test('.request event re-broadcasts the current list', function()
  local before = #H.event_emits
  H.fire_event('broaty.discworld-blorpsack.blorps.request', {})
  assert(#H.event_emits == before + 1)
  local emitted = H.event_emits[#H.event_emits]
  local names = {}
  for _, b in ipairs(emitted.data.blorps) do names[b.name] = true end
  assert(names.market == true)
  assert(names.bank == true)
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/main_test.lua`
Expected: FAIL — `src/main.lua` doesn't exist yet.

- [ ] **Step 3: Write `src/main.lua`**

```lua
-- src/main.lua
-- Discworld Blorpsack — mallard plugin entry point.
--
-- Thin facade: requires every blorpsack.* module exactly once and wires
-- cross-module access via each module's init(deps) function, matching
-- cowtography's src/main.lua discipline (see that file's header comment
-- for why: Mallard's plugin sandbox require() has no caching).

local colors   = require('blorpsack.colors')
local state    = require('blorpsack.state')
local panel    = require('blorpsack.panel')
local blorps   = require('blorpsack.blorps')
local commands = require('blorpsack.commands')

state.init({ panel = panel })
blorps.init({ state = state, panel = panel })
panel.init({ colors = colors, state = state, blorps = blorps })
commands.init({ colors = colors, state = state, blorps = blorps })
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `lua tests/main_test.lua`
Expected: `4 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/main.lua tests/main_test.lua
git commit -m "$(cat <<'EOF'
Add src/main.lua: wire all blorpsack modules together

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Panel UI — `ui/panel.html`, `ui/panel.css`, `ui/panel.js`

**Files:**
- Create: `ui/panel.html`
- Create: `ui/panel.css`
- Create: `ui/panel.js`

**Interfaces:**
- Consumes the wire contract Task 6 established: `panel.on("blorps_list", { blorps: [{ name, room_id }, ...] })`, `panel.on("room_changed", { room_id })`, and posts `panel.post("add", { name })` / `panel.post("remove", { name })`. The `"ready"` handshake that triggers the first `blorps_list`/`room_changed` posts is sent automatically by Mallard's injected panel SDK when the iframe loads — no explicit `panel.post("ready", ...)` call is needed on the JS side (confirmed by cowtography's own `ascii_map.js`/`mapper.js`, neither of which sends one, yet both receive their Lua-side `on_message("ready", ...)` callbacks).
- Produces: the panel's rendered UI. No automated test — DOM rendering isn't unit-tested elsewhere in this codebase either (cowtography's panels aren't), so this is verified manually in Step 4.

- [ ] **Step 1: Write `ui/panel.html`**

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Blorpsack</title>
  <link rel="stylesheet" href="panel.css">
</head>
<body>
  <div class="room">Room: <span id="room-id" class="unknown">unknown</span></div>
  <ul id="list"></ul>
  <div id="empty" class="empty" hidden>No blorps registered.</div>
  <form id="add-form" class="add-form">
    <input id="add-name" type="text" placeholder="Blorp name" autocomplete="off">
    <button id="add-button" type="submit" disabled>Add</button>
  </form>
  <script type="module" src="panel.js"></script>
</body>
</html>
```

- [ ] **Step 2: Write `ui/panel.css`**

```css
body {
  margin: 0;
  padding: 8px;
  font-family: system-ui, sans-serif;
  font-size: 13px;
  color: #ddd;
  background: #1e1e1e;
}

.room {
  margin-bottom: 8px;
  color: #888;
}

#room-id.unknown {
  color: #ff6666;
}

ul#list {
  list-style: none;
  margin: 0 0 8px 0;
  padding: 0;
}

ul#list li {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 4px 0;
  border-bottom: 1px solid #333;
}

ul#list li .name {
  font-weight: 600;
}

ul#list li .room-id {
  color: #888;
  margin-left: 8px;
  flex: 1;
}

ul#list li button.remove {
  background: none;
  border: 1px solid #663333;
  color: #ff9999;
  border-radius: 3px;
  cursor: pointer;
  padding: 2px 6px;
}

.empty {
  color: #888;
  margin-bottom: 8px;
}

.add-form {
  display: flex;
  gap: 4px;
}

.add-form input {
  flex: 1;
  background: #2a2a2a;
  border: 1px solid #444;
  color: #ddd;
  padding: 4px 6px;
  border-radius: 3px;
}

.add-form button {
  background: #335533;
  border: 1px solid #557755;
  color: #aaffaa;
  border-radius: 3px;
  cursor: pointer;
  padding: 4px 10px;
}

.add-form button:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}
```

- [ ] **Step 3: Write `ui/panel.js`**

```js
const $roomId    = document.getElementById("room-id");
const $list      = document.getElementById("list");
const $empty     = document.getElementById("empty");
const $addForm   = document.getElementById("add-form");
const $addName   = document.getElementById("add-name");
const $addButton = document.getElementById("add-button");

let currentRoomId = null;

function renderRoom() {
  if (currentRoomId) {
    $roomId.textContent = currentRoomId;
    $roomId.classList.remove("unknown");
    $addButton.disabled = false;
  } else {
    $roomId.textContent = "unknown";
    $roomId.classList.add("unknown");
    $addButton.disabled = true;
  }
}

function renderList(blorps) {
  $list.innerHTML = "";
  if (!blorps || blorps.length === 0) {
    $empty.hidden = false;
    return;
  }
  $empty.hidden = true;
  for (const b of blorps) {
    const li = document.createElement("li");

    const name = document.createElement("span");
    name.className = "name";
    name.textContent = b.name;

    const roomId = document.createElement("span");
    roomId.className = "room-id";
    roomId.textContent = b.room_id;

    const remove = document.createElement("button");
    remove.className = "remove";
    remove.type = "button";
    remove.textContent = "×";
    remove.addEventListener("click", () => panel.post("remove", { name: b.name }));

    li.appendChild(name);
    li.appendChild(roomId);
    li.appendChild(remove);
    $list.appendChild(li);
  }
}

panel.on("blorps_list", (frame) => renderList(frame.blorps || []));

panel.on("room_changed", (frame) => {
  currentRoomId = frame.room_id || null;
  renderRoom();
});

$addForm.addEventListener("submit", (e) => {
  e.preventDefault();
  const name = $addName.value.trim();
  if (!name || !currentRoomId) return;
  panel.post("add", { name });
  $addName.value = "";
});

renderRoom();
```

- [ ] **Step 4: Manual verification**

This isn't automatable without a real Mallard client. Once Task 9's `npm test` passes (confirming the Lua side is correct), use the `run` skill to launch Mallard against Discworld, connect a character, and in the client:
1. Open the "Blorpsack" panel (via the panels tray). It should show "Room: unknown" and a disabled "Add" button before any `room.info` GMCP frame has arrived.
2. Move to any mapped room. The room id should appear and "Add" should enable.
3. Type a name and click "Add". Run `/blorp` in the main window — the new blorp should be listed there too.
4. Click the row's "×" button. Run `/blorp` again — it should be gone.
5. Run `/blorp add <name>` from the command line instead — the panel list should update live, without reopening the panel.

- [ ] **Step 5: Commit**

```bash
git add ui/panel.html ui/panel.css ui/panel.js
git commit -m "$(cat <<'EOF'
Add blorpsack panel UI: list, add form, remove buttons

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: Package scripts, README, final verification

**Files:**
- Create: `package.json`
- Create: `README.md`

**Interfaces:**
- Consumes: the full test file list from Tasks 2–7.
- Produces: `npm test` running every Lua test file in order; `npm run pack` zipping the plugin for distribution (mirrors cowtography's own `pack` script).

- [ ] **Step 1: Write `package.json`**

```json
{
  "name": "discworld-blorpsack",
  "version": "0.1.0",
  "private": true,
  "description": "Mallard plugin: tracks Discworld blorps and broadcasts the list for other plugins to route to.",
  "scripts": {
    "test": "lua tests/fake_host_test.lua && lua tests/state_test.lua && lua tests/blorps_init_test.lua && lua tests/blorps_test.lua && lua tests/commands_test.lua && lua tests/panel_test.lua && lua tests/main_test.lua",
    "pack": "rm -f discworld-blorpsack-0.1.0.mallardx && zip -r discworld-blorpsack-0.1.0.mallardx plugin.toml README.md src/ ui/"
  }
}
```

- [ ] **Step 2: Write `README.md`**

```markdown
# Discworld Blorpsack

A [Mallard](https://mallard.vnsf.xyz) plugin for [Discworld MUD](https://discworld.starturtle.net/lpc/) that tracks **blorps** — pieces of jewellery enchanted to remember a location — carried by your character, and broadcasts the list for other plugins (e.g. cowtography) to route to.

Blorpsack has no routing or mapping logic of its own. Its whole job is
registering blorps and telling other plugins where they are.

## Commands

Commands use Mallard's client command prefix — `/` by default.

```
/blorp                  — list all registered blorps
/blorp add <name>       — register a blorp named <name> at your current room
/blorp rm <name>        — remove a blorp
```

Adding a blorp with a name that already exists overwrites its stored room
silently — that's how you re-register a blorp after recasting it
somewhere new.

```
/blorp add market        Registered blorp "market" at r12345.
/blorp                   Blorps:
                            market               r12345
/blorp rm market          Removed blorp "market".
```

## Panel

An optional "Blorpsack" panel shows the same list with Add/Remove
controls. It's a pure convenience layer over the commands above — nothing
in this plugin requires opening it.

## For plugin authors: subscribing to the blorp list

Blorpsack broadcasts over Mallard's cross-plugin `events` bus:

- `broaty.discworld-blorpsack.blorps` — emitted after every successful
  `add`/`rm`, and in response to the request event below. Payload:
  `{ blorps = { { room_id = "...", name = "..." }, ... } }`.
- `broaty.discworld-blorpsack.blorps.request` — emit this once after your
  own plugin's load (e.g. after a short delay, to give blorpsack a chance
  to load too) to get the current list regardless of which plugin loaded
  first. Blorpsack never broadcasts unprompted at load.

```lua
events.on("broaty.discworld-blorpsack.blorps", function(data)
  -- data.blorps is an array of { room_id, name }
end)

events.emit("broaty.discworld-blorpsack.blorps.request", {})
```

## Installation

Install from the Mallard marketplace.

## AI disclosure

Much of this plugin's code was written with the help of an LLM (Claude).
Design decisions, testing, and review are the author's own.
```

- [ ] **Step 3: Run the full test suite**

Run: `npm test`
Expected: all 7 Lua test files print their `PASS`/count lines with no `FAIL`, and the command exits 0.

- [ ] **Step 4: Commit**

```bash
git add package.json README.md
git commit -m "$(cat <<'EOF'
Add package scripts and README

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 5: Manual smoke test in the running client**

Follow Task 8 Step 4's manual verification checklist end-to-end (panel + commands) if not already done. Additionally verify the cross-plugin contract with a throwaway script or a second toy plugin: subscribe to `broaty.discworld-blorpsack.blorps`, emit `broaty.discworld-blorpsack.blorps.request`, and confirm the current list arrives. (Full cowtography integration is out of scope for this plan — see the design spec's Overview.)
