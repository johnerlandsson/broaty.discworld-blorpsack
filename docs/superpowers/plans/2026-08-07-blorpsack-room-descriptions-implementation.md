# Blorpsack Room Descriptions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace raw room ids with the room's short description (e.g. "The Mended Drum") everywhere blorpsack displays a blorp's location — the `/blorp` command's output and the panel — while leaving the cross-plugin broadcast payload (`{ room_id, name }`) exactly as it is today.

**Architecture:** This is a modification to an already-shipped, fully-implemented plugin (see `docs/superpowers/specs/2026-08-07-blorpsack-design.md` and its implementation). Every production file already exists; every task below modifies existing files in place, in dependency order (state → blorps → commands → panel → UI → final integration), each with its own updated test file.

**Tech Stack:** Same as the original implementation — Lua (Mallard plugin runtime), plain HTML/CSS/JS, `lua`-interpreter unit tests via `tests/support/fake_host.lua`.

## Global Constraints

- Discworld's GMCP `room.info` package includes a `name` field (the short room description) alongside `identifier` — already available under blorpsack's existing `gmcp_access = ["room.info", ...]` permission. No `plugin.toml` change in this plan.
- Storage shape per blorp entry changes from a plain `room_id` string to `{ room_id, room_name }`. Reading must tolerate BOTH shapes: a plain string is legacy data (written before this change) and is read as `room_id` with `room_name = nil`. No migration, no storage version field.
- `blorps.lua`'s `M.list()` returns `{ room_id, name, room_name }` per entry (decorated shape, used internally by `commands.lua` and `panel.lua`).
- The cross-plugin broadcast (`events.emit("broaty.discworld-blorpsack.blorps", ...)`) stays `{ blorps = { { room_id, name }, ... } }` — **no `room_name`**. The panel post (`panel:post("blorps_list", ...)`) carries the full decorated list including `room_name`.
- Display fallback for a **stored/listed entry** with no `room_name` (legacy data): the literal string `"(unknown room)"`.
- Display fallback for the **`/blorp add` confirmation message** specifically: the raw room id, not `"(unknown room)"` — this is live, fresh data at the moment of a successful add, not a potentially-stale stored entry.
- Panel's "current room" header shows `room_name`, falling back to the raw room id if the name hasn't arrived yet (same event, `room_changed`, gains a `room_name` field alongside its existing `room_id`).
- Panel CSS class/JS variable/HTML element id previously named for "room id" (`#room-id`, `.room-id`, `roomId`) are renamed to `room-name`/`roomName` to match what they now hold.
- No changes to: `plugin.toml`, the cross-plugin event names, blorp name uniqueness/overwrite semantics, or the storage key (`'blorps_' .. char_name` / `'blorps'` fallback).

---

## File Structure

Every file in this list already exists; every task below modifies one production file and its corresponding test file.

```
src/blorpsack/state.lua      -- + current_room_name tracking
src/blorpsack/blorps.lua     -- storage shape change, broadcast/panel payload split
src/blorpsack/commands.lua   -- display room_name with fallbacks
src/blorpsack/panel.lua      -- "ready" handler posts room_name
ui/panel.html                -- id="room-id" -> id="room-name"
ui/panel.css                 -- .room-id/#room-id -> .room-name/#room-name
ui/panel.js                  -- display room_name with fallbacks, renamed selectors
tests/state_test.lua
tests/blorps_init_test.lua
tests/blorps_test.lua
tests/commands_test.lua
tests/panel_test.lua
tests/main_test.lua          -- final integration re-check
README.md                    -- sample output block
```

---

### Task 1: `state.lua` — track `current_room_name`

**Files:**
- Modify: `src/blorpsack/state.lua`
- Modify: `tests/state_test.lua`

**Interfaces:**
- Produces: `M.current_room_name` (string|nil) on `blorpsack.state`, updated in lockstep with `M.current_room` (same change-guard: only updates, and only posts to the panel, when the room identifier actually changes). `post_room_changed()`'s payload becomes `{ room_id = M.current_room, room_name = M.current_room_name }`.

- [ ] **Step 1: Update the test — `tests/state_test.lua`**

Replace the file's contents with:

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

test('room.info gmcp event sets current_room/current_room_name and posts room_changed', function()
  H.fire_gmcp('room.info', { identifier = 'r1', name = 'Market Square' })
  assert(state.current_room == 'r1')
  assert(state.current_room_name == 'Market Square')
  assert(panel_posts[#panel_posts].name == 'room_changed')
  assert(panel_posts[#panel_posts].data.room_id == 'r1')
  assert(panel_posts[#panel_posts].data.room_name == 'Market Square')
end)

test('room.info gmcp event with the same id does not re-post', function()
  local before = #panel_posts
  H.fire_gmcp('room.info', { identifier = 'r1', name = 'Market Square' })
  assert(#panel_posts == before)
end)

test('room.info gmcp event with a new id updates and posts again', function()
  H.fire_gmcp('room.info', { identifier = 'r2', name = 'The Mended Drum' })
  assert(state.current_room == 'r2')
  assert(state.current_room_name == 'The Mended Drum')
  assert(panel_posts[#panel_posts].data.room_id == 'r2')
  assert(panel_posts[#panel_posts].data.room_name == 'The Mended Drum')
end)

test('char.info gmcp event updates char_name', function()
  H.fire_gmcp('char.info', { capname = 'Rincewind' })
  assert(state.char_name == 'Rincewind')
end)

test('world connect reseeds current_room/current_room_name from gmcp.get', function()
  H.gmcp_values['room.info'] = '{"identifier":"r9","name":"Somewhere"}'
  H.fire_world('connect')
  assert(state.current_room == 'r9')
  assert(state.current_room_name == 'Somewhere')
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `lua tests/state_test.lua`
Expected: FAIL — `state.lua` doesn't set `current_room_name` yet, so the new assertions fail.

- [ ] **Step 3: Update `src/blorpsack/state.lua`**

Replace the file's contents with:

```lua
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
local panel

local function post_room_changed()
  if panel then
    panel:post("room_changed", { room_id = M.current_room, room_name = M.current_room_name })
  end
end

local function apply_room(identifier, name)
  if identifier and identifier ~= M.current_room then
    M.current_room = identifier
    M.current_room_name = name
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
    apply_room(raw:match('"identifier"%s*:%s*"([^"]+)"'), raw:match('"name"%s*:%s*"([^"]*)"'))
  end
end

function M.init(deps)
  panel = deps.panel.panel
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `lua tests/state_test.lua`
Expected: `6 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/blorpsack/state.lua tests/state_test.lua
git commit -m "$(cat <<'EOF'
state.lua: track current_room_name from GMCP room.info

Sourced from the same room.info payload as current_room (both the live
gmcp.on event and the gmcp.get hydration/regex path), updated together
under the same change-only guard.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: `blorps.lua` — storage shape and the broadcast/panel split

**Files:**
- Modify: `src/blorpsack/blorps.lua`
- Modify: `tests/blorps_init_test.lua`
- Modify: `tests/blorps_test.lua`

**Interfaces:**
- Consumes: `state.current_room_name` (Task 1).
- Produces: `M.list()` now returns `{ room_id, name, room_name }` per entry (`room_name` may be `nil`). `M.add(name)` stores `{ room_id = state.current_room, room_name = state.current_room_name }` per entry (was a plain `room_id` string). Reading (`to_wire`) tolerates a plain-string legacy entry, treating it as `room_id` with `room_name = nil`. The cross-plugin broadcast payload (`events.emit`) stays `{ blorps = { { room_id, name }, ... } }` with no `room_name`; the panel post (`panel:post("blorps_list", ...)`) carries the full `{ room_id, name, room_name }` list.

- [ ] **Step 1: Update the tests**

Replace `tests/blorps_init_test.lua`'s contents with:

```lua
-- Run from project root: lua tests/blorps_init_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

-- Seed storage as if a previous session already registered blorps, before
-- blorpsack.blorps is ever required. blorps.lua keeps no in-memory cache —
-- it reads storage.get() fresh on every list()/add()/remove() call — so
-- "hydration" is just: the data is already there to read. This test's job
-- is to confirm requiring + initing the module does NOT itself broadcast,
-- and that both storage shapes it might find are read correctly:
-- "armoury" is the legacy plain-room_id-string shape (written before
-- room_name existed); "market" is the current { room_id, room_name } shape.
H.storage_data['blorps'] = {
  armoury = 'r0',
  market  = { room_id = 'r1', room_name = 'Market Square' },
}

local panel_handle, panel_posts = fake_host.new_panel('blorps')
local state  = { current_room = nil, current_room_name = nil, char_name = nil }
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

test('list reflects a legacy plain-room_id entry with room_name nil', function()
  local list = blorps.list()
  assert(list[1].name == 'armoury')
  assert(list[1].room_id == 'r0')
  assert(list[1].room_name == nil)
end)

test('list reflects a current-shape entry with room_name set', function()
  local list = blorps.list()
  assert(list[2].name == 'market')
  assert(list[2].room_id == 'r1')
  assert(list[2].room_name == 'Market Square')
end)

print(string.format('\n%d tests passed.', passed))
```

Replace `tests/blorps_test.lua`'s contents with:

```lua
-- Run from project root: lua tests/blorps_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local panel_handle, panel_posts = fake_host.new_panel('blorps')
local state  = { current_room = nil, current_room_name = nil, char_name = nil }
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
  state.current_room_name = 'Market Square'
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
  assert(panel_posts[1].data.blorps[1].room_name == 'Market Square')
end)

test('the cross-plugin broadcast excludes room_name; the panel post includes it', function()
  local emitted_blorp = H.event_emits[#H.event_emits].data.blorps[1]
  assert(emitted_blorp.room_id ~= nil)
  assert(emitted_blorp.name ~= nil)
  assert(emitted_blorp.room_name == nil)

  local posted_blorp = panel_posts[#panel_posts].data.blorps[1]
  assert(posted_blorp.room_name == 'Market Square')
end)

test('add on an existing name overwrites the room id/name and broadcasts', function()
  state.current_room = 'r2'
  state.current_room_name = 'The Mended Drum'
  local ok = blorps.add('market')
  assert(ok == true)
  assert(#H.event_emits == 2)
  local list = blorps.list()
  assert(#list == 1)
  assert(list[1].room_id == 'r2')
  assert(list[1].room_name == 'The Mended Drum')
end)

test('list returns entries sorted by name', function()
  state.current_room = 'r3'
  state.current_room_name = 'The Bank'
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
  state.current_room_name = 'The Armoury'
  blorps.add('bank2')
  assert(H.storage_data['blorps_Dilbo'] ~= nil)
  assert(H.storage_data['blorps_Dilbo'].bank2.room_id == 'r4')
  assert(H.storage_data['blorps_Dilbo'].bank2.room_name == 'The Armoury')
  -- the earlier, pre-char_name entry is untouched under the fallback key
  assert(H.storage_data['blorps'].market.room_id == 'r2')
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
Expected: FAIL — `blorps.lua` still stores/reads a plain `room_id` string and doesn't split the broadcast/panel payloads.

- [ ] **Step 3: Update `src/blorpsack/blorps.lua`**

Replace the file's contents with:

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
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `lua tests/blorps_init_test.lua && lua tests/blorps_test.lua`
Expected: `3 tests passed.` then `10 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/blorpsack/blorps.lua tests/blorps_init_test.lua tests/blorps_test.lua
git commit -m "$(cat <<'EOF'
blorps.lua: store room_name per entry, keep the broadcast wire-only

Storage shape per blorp changes from a plain room_id string to
{ room_id, room_name }; reading tolerates both shapes (legacy strings
read as room_name = nil, no migration). M.list() returns the decorated
shape for internal consumers; the cross-plugin broadcast payload strips
room_name back out so the documented external contract is unchanged.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: `commands.lua` — display `room_name` with fallbacks

**Files:**
- Modify: `src/blorpsack/commands.lua`
- Modify: `tests/commands_test.lua`

**Interfaces:**
- Consumes: `blorps.list()` entries now carry `room_name` (Task 2); `state.current_room_name` (Task 1).
- Produces: `/blorp` list rows show `b.room_name or '(unknown room)'`. `/blorp add`'s confirmation shows `state.current_room_name or tostring(state.current_room)`.

- [ ] **Step 1: Update the test — `tests/commands_test.lua`**

Replace the file's contents with:

```lua
-- Run from project root: lua tests/commands_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local colors = require('blorpsack.colors')
local panel_handle = fake_host.new_panel('blorps')
local state  = { current_room = nil, current_room_name = nil, char_name = nil }
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

test('/blorp add <name> registers a blorp and shows the room name', function()
  state.current_room = 'r1'
  state.current_room_name = 'Market Square'
  invoke('add market')
  assert(last_note():match('Registered blorp "market" at Market Square'))
  assert(#blorps.list() == 1)
end)

test('/blorp add falls back to the raw room id when the room name is unknown', function()
  state.current_room = 'r5'
  state.current_room_name = nil
  invoke('add bank')
  assert(last_note():match('Registered blorp "bank" at r5'))
  state.current_room = 'r1'
  state.current_room_name = 'Market Square'
end)

test('bare /blorp lists registered blorps by room name', function()
  invoke('')
  local found_market = false
  for _, n in ipairs(H.notes) do
    if n[1]:match('market') and n[1]:match('Market Square') then found_market = true end
  end
  assert(found_market)
end)

test('bare /blorp shows "(unknown room)" for a legacy entry with no stored name', function()
  local data = H.storage_data['blorps']
  data['old'] = 'r99'  -- legacy plain-room_id shape, no room_name
  invoke('')
  local found = false
  for _, n in ipairs(H.notes) do
    if n[1]:match('old') and n[1]:match('%(unknown room%)') then found = true end
  end
  assert(found)
end)

test('/blorp rm <name> removes a blorp', function()
  invoke('rm market')
  assert(last_note():match('Removed blorp "market"'))
  assert(#blorps.list() == 2)
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
Expected: FAIL — `commands.lua` still displays `b.room_id` and `state.current_room` directly.

- [ ] **Step 3: Update `src/blorpsack/commands.lua`**

Replace the file's contents with:

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
    note(string.format('  %-20s %s', b.name, b.room_name or '(unknown room)'), C.alt)
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
      note(string.format('  Registered blorp "%s" at %s.', add_name, state.current_room_name or tostring(state.current_room)), C.ok)
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

- [ ] **Step 4: Run the test to verify it passes**

Run: `lua tests/commands_test.lua`
Expected: `10 tests passed.`

- [ ] **Step 5: Commit**

```bash
git add src/blorpsack/commands.lua tests/commands_test.lua
git commit -m "$(cat <<'EOF'
commands.lua: display room_name instead of room_id

List rows fall back to "(unknown room)" for legacy entries with no
stored name; the add confirmation falls back to the raw room id
instead, since that's live data rather than a potentially-stale
stored entry.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: `panel.lua` — `"ready"` posts `room_name`

**Files:**
- Modify: `src/blorpsack/panel.lua`
- Modify: `tests/panel_test.lua`

**Interfaces:**
- Consumes: `state.current_room_name` (Task 1); `blorps.list()` entries carrying `room_name` (Task 2, passed through unchanged — `panel.lua` doesn't inspect the field itself).
- Produces: the `"ready"` handler's `room_changed` post becomes `{ room_id = state.current_room, room_name = state.current_room_name }`.

- [ ] **Step 1: Update the test — `tests/panel_test.lua`**

Replace the file's contents with:

```lua
-- Run from project root: lua tests/panel_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local colors = require('blorpsack.colors')
local state  = { current_room = 'r1', current_room_name = 'Market Square', char_name = nil }

-- Stub blorps: panel.lua's job is dispatching to blorps.add/blorps.remove
-- and formatting blorps.list() for the "ready" handshake, not re-testing
-- blorps.lua's own CRUD logic (that's covered in blorps_test.lua). A stub
-- lets these tests assert panel.lua calls the right function with the
-- right argument, independent of the real storage/broadcast machinery.
-- (main_test.lua wires the REAL blorps.lua and proves commands and the
-- panel share one instance, not two divergent code paths.)
local blorps_calls = {}
local blorps = {
  list = function() return { { name = 'market', room_id = 'r1', room_name = 'Market Square' } } end,
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

test('ready posts the current blorp list (with room names) and current room', function()
  handle:fire('ready', {})
  assert(posts[1].name == 'blorps_list')
  assert(posts[1].data.blorps[1].name == 'market')
  assert(posts[1].data.blorps[1].room_name == 'Market Square')
  assert(posts[2].name == 'room_changed')
  assert(posts[2].data.room_id == 'r1')
  assert(posts[2].data.room_name == 'Market Square')
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
Expected: FAIL — the `"ready"` handler doesn't post `room_name` yet.

- [ ] **Step 3: Update `src/blorpsack/panel.lua`**

Replace the file's contents with:

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
  M.panel:post("room_changed", { room_id = state.current_room, room_name = state.current_room_name })
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
panel.lua: include room_name in the "ready" room_changed post

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Panel UI — display `room_name`, rename `room-id` selectors

**Files:**
- Modify: `ui/panel.html`
- Modify: `ui/panel.css`
- Modify: `ui/panel.js`

**Interfaces:**
- Consumes: `panel.on("blorps_list", ...)` entries now carry `room_name` (Task 2); `panel.on("room_changed", ...)` now carries `room_name` (Task 4).
- Produces: the panel header shows `currentRoomName || currentRoomId`, falling back to `"unknown"` when neither is known (Add stays gated on `currentRoomId` alone — that's the real precondition for adding). Each blorp row shows `b.room_name || "(unknown room)"`. The DOM id/class previously `room-id`/`.room-id` is renamed to `room-name`/`.room-name` throughout.

- [ ] **Step 1: Update `ui/panel.html`**

Replace the file's contents with:

```html
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Blorpsack</title>
  <link rel="stylesheet" href="panel.css">
</head>
<body>
  <div class="room">Room: <span id="room-name" class="unknown">unknown</span></div>
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

- [ ] **Step 2: Update `ui/panel.css`**

Replace the file's contents with:

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

#room-name.unknown {
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

ul#list li .room-name {
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

- [ ] **Step 3: Update `ui/panel.js`**

Replace the file's contents with:

```js
const $roomName  = document.getElementById("room-name");
const $list      = document.getElementById("list");
const $empty     = document.getElementById("empty");
const $addForm   = document.getElementById("add-form");
const $addName   = document.getElementById("add-name");
const $addButton = document.getElementById("add-button");

let currentRoomId   = null;
let currentRoomName = null;

function renderRoom() {
  if (currentRoomId) {
    $roomName.textContent = currentRoomName || currentRoomId;
    $roomName.classList.remove("unknown");
    $addButton.disabled = false;
  } else {
    $roomName.textContent = "unknown";
    $roomName.classList.add("unknown");
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

    const roomName = document.createElement("span");
    roomName.className = "room-name";
    roomName.textContent = b.room_name || "(unknown room)";

    const remove = document.createElement("button");
    remove.className = "remove";
    remove.type = "button";
    remove.textContent = "×";
    remove.addEventListener("click", () => panel.post("remove", { name: b.name }));

    li.appendChild(name);
    li.appendChild(roomName);
    li.appendChild(remove);
    $list.appendChild(li);
  }
}

panel.on("blorps_list", (frame) => renderList(frame.blorps || []));

panel.on("room_changed", (frame) => {
  currentRoomId = frame.room_id || null;
  currentRoomName = frame.room_name || null;
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

panel.post("ready", {});
```

- [ ] **Step 4: Commit**

No automated test exists for this file (matches the rest of this codebase — DOM rendering isn't unit-tested elsewhere either). Manual verification happens in Task 6.

```bash
git add ui/panel.html ui/panel.css ui/panel.js
git commit -m "$(cat <<'EOF'
Panel UI: display room_name instead of room_id, rename room-id selectors

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Final integration test, README, full verification

**Files:**
- Modify: `tests/main_test.lua`
- Modify: `README.md`

**Interfaces:**
- Consumes: every change from Tasks 1-5.
- Produces: an end-to-end proof that a GMCP room name flows all the way from `state.lua` through `blorps.lua`'s split payloads to both the command output and the panel, and that `npm test` passes in full.

- [ ] **Step 1: Update the test — `tests/main_test.lua`**

Replace the file's contents with:

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
  H.fire_gmcp('room.info', { identifier = 'r1', name = 'Market Square' })
  H.commands.blorp({ args = 'add market' })

  assert(#H.event_emits == 1)
  assert(H.event_emits[1].name == 'broaty.discworld-blorpsack.blorps')
  assert(H.event_emits[1].data.blorps[1].name == 'market')
  assert(H.event_emits[1].data.blorps[1].room_name == nil)

  local panel_posts = H.panels.blorps.posts
  assert(panel_posts[#panel_posts].name == 'blorps_list')
  assert(panel_posts[#panel_posts].data.blorps[1].room_id == 'r1')
  assert(panel_posts[#panel_posts].data.blorps[1].room_name == 'Market Square')

  assert(H.notes[#H.notes][1]:match('Registered blorp "market" at Market Square'))
end)

test('a panel "ready" message reflects the room the command already saw', function()
  H.panels.blorps.handle:fire('ready', {})
  local panel_posts = H.panels.blorps.posts
  assert(panel_posts[#panel_posts].name == 'room_changed')
  assert(panel_posts[#panel_posts].data.room_id == 'r1')
  assert(panel_posts[#panel_posts].data.room_name == 'Market Square')
end)

test('a panel "add" message reaches the same blorps list a command would see', function()
  H.panels.blorps.handle:fire('add', { name = 'bank' })
  H.commands.blorp({ args = '' })
  local found = false
  for _, n in ipairs(H.notes) do
    if n[1]:match('bank') then found = true end
  end
  assert(found)
end)

test('.request event re-broadcasts the current list, still without room_name', function()
  local before = #H.event_emits
  H.fire_event('broaty.discworld-blorpsack.blorps.request', {})
  assert(#H.event_emits == before + 1)
  local emitted = H.event_emits[#H.event_emits]
  local names = {}
  for _, b in ipairs(emitted.data.blorps) do
    names[b.name] = true
    assert(b.room_name == nil)
  end
  assert(names.market == true)
  assert(names.bank == true)
end)

print(string.format('\n%d tests passed.', passed))
```

- [ ] **Step 2: Run the test and verify it passes**

Run: `lua tests/main_test.lua`
Expected: `4 tests passed.`

- [ ] **Step 3: Update `README.md`'s sample output block**

In the `## Commands` section, find this block:

```
/blorp add market        Registered blorp "market" at r12345.
/blorp                   Blorps:
                            market               r12345
/blorp rm market          Removed blorp "market".
```

Replace it with:

```
/blorp add market        Registered blorp "market" at The Mended Drum.
/blorp                   Blorps:
                            market               The Mended Drum
/blorp rm market          Removed blorp "market".
```

No other README section changes — the "For plugin authors" section's broadcast payload example (`{ room_id = "...", name = "..." }`) is still accurate and unchanged.

- [ ] **Step 4: Run the full suite**

Run: `npm test`
Expected: all 7 Lua test files pass with no FAIL lines, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add tests/main_test.lua README.md
git commit -m "$(cat <<'EOF'
Update integration test and README for room-name display

End-to-end proof that a GMCP room name flows through blorps.lua's
split broadcast/panel payloads to both the command output and the
panel. README's sample output block now shows a room name instead of
a raw room id.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 6: Manual verification (optional, requires a running Mallard client)**

Not achievable in an automated/sandboxed context — requires a live Mallard desktop app connected to Discworld. If available: open the Blorpsack panel, confirm the header shows a room description (not a raw id) once you're in a mapped room, `/blorp add` a test entry and confirm both the command output and the panel list row show the room description, and confirm a pre-existing blorp registered before this change (if any) shows `"(unknown room)"` rather than crashing or showing a raw id.
