# Blorpsack — design

## Overview

Blorpsack is a Mallard plugin for Discworld MUD that tracks **blorps** —
pieces of jewellery enchanted to remember a location — carried by the
player. The player registers a blorp by standing in the room it was cast
in and running a command; blorpsack records `{room_id, name}` for it.

Blorpsack has no routing or mapping logic of its own. Its sole job is to
maintain this list and broadcast it, so other plugins — specifically
cowtography (maintained separately, in `mallardx-discworld-cowtography`)
— can subscribe and use blorp locations when building routes.
Cowtography's own changes to consume this broadcast are out of scope for
this spec and will be made in that project.

## Plugin ID

`broaty.discworld-blorpsack`.

Mallard's plugin id rule is just "lowercase alphanumerics, dots, hyphens,
underscores" — reverse-DNS is a suggested convention, not a requirement.
Since the author doesn't reverse a domain they don't own, the scheme here
is `<author-handle>.<plugin-slug>`, using `broaty` (the author's own
domain, broaty.se) as a stable identity across all their plugins,
independent of any one Discworld character. Cowtography currently uses
`net.mallard.discworld-cowtography`; renaming it to
`broaty.discworld-cowtography` to match is a separate, later change in
that project, not part of this spec.

## Manifest (`plugin.toml`)

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

No `sends`, `database`, `keychain`, or `notifications` permission is
needed: blorpsack never sends anything to the MUD, ships no bundled
database, and `storage`/`events`/`mud.command` are ungated in Mallard's
permission model (only `sends`, `notifications`, `keychain`, `database`,
and `gmcp_access` require declaration).

## Room tracking

Mirrors cowtography's own `room.info` handling exactly, since blorp room
ids must live in the same identifier space cowtography already uses for
routing (both read the same GMCP `room.info.identifier` field from the
same MUD):

- `gmcp.on('room.info', function(_, data) ... end)` updates
  `state.current_room = data.identifier` whenever it's present.
- `world.on("connect", seed_room)` hydrates `state.current_room` from
  `gmcp.get("room.info")` on (re)connect, matching cowtography's
  `seed_room` pattern for plugin-reload survival.
- `gmcp.on('char.info', ...)` plus a startup `gmcp.get('char.info.capname')`
  call track `state.char_name`, used to namespace storage (see below).
  Cowtography's `char.info` handler is the direct template for this.

## Storage & data model

Mallard's `storage` API is per-plugin, per-world key/value — not
per-character — so, exactly like cowtography's bookmarks, blorpsack keys
its storage entry by character name:

```lua
local function blorps_key()
  return state.char_name and ('blorps_' .. state.char_name) or 'blorps'
end
```

Stored value is a table keyed by blorp name → room id:

```lua
{ market = "r123", bank = "r456" }
```

Name is the natural unique key: registering a blorp under an existing
name overwrites its room id (see "update" below), and removal is a
single table field clear. This differs from the wire/broadcast shape
(see Event contract), which is an array of `{room_id, name}` objects —
the storage shape optimizes for uniqueness-by-name and O(1)
add/overwrite/remove; the wire shape is what was asked for and is simple
for a consumer to iterate.

## Commands

Command word: `/blorp` (Mallard's configurable client prefix, default
`/`).

- **`/blorp`** — bare, with no arguments. Lists all registered blorps
  for the current character, sorted by name, printed via `mud.note` /
  `mud.span` in the same style as cowtography's `/bm` bookmark list. If
  none are registered, prints a short "no blorps registered" message.
- **`/blorp add <name>`** — registers (or re-registers) a blorp named
  `<name>` at `state.current_room`. Requires `state.current_room` to be
  known; if not (e.g. plugin just loaded and no `room.info` has arrived
  yet, or the room is dark), prints an error and does nothing. If
  `<name>` already exists, its room id is silently overwritten — this
  overwrite **is** the "update" case; there is no separate rename
  command. Triggers a broadcast (see below) on success.
- **`/blorp rm <name>`** — removes the blorp named `<name>`. If
  `<name>` isn't registered, prints an error and does **not** broadcast
  (no actual change occurred). Triggers a broadcast on success.

## Panel

A dockable panel, titled "Blorpsack", showing the same list the commands
operate on, with buttons for add/remove. It is a **pure convenience
layer** for the functionality in this spec: every action available on
the panel (list, add, remove) has an equivalent command and vice versa,
and no workflow described here requires opening it. (Future blorpsack
features may end up panel-only if they need a UI commands can't express
— that's fine going forward, but doesn't apply to anything in this
version.)

Mallard offers two panel styles: a declarative `mud.panel(id):layout()`
grid framework (cells of kind `stat`/`bar`/`button`/`header`/`indicator`
— built for fixed dashboards like vitals displays), and custom iframe
panels that ship their own HTML/CSS/JS and talk to Lua via
`panel:post`/`panel:on_message` (JS side: `panel.post`/`panel.on`, no
direct host API access — everything routes through the owning Lua
state). A dynamic, variable-length list with a per-row remove button and
a free-text add field doesn't fit the grid framework's fixed cell kinds,
so this is a custom iframe panel; cowtography's structurally simplest
one (`ascii_map`) is the closest template: a single `<pre>`/list element
driven entirely by posted state, no click-to-route complexity.

**Lua side** (`src/blorpsack/panel.lua`):
- `M.panel = mud.panel("blorps")`.
- `M.panel:on_message("ready", ...)` — posts the current list
  (`blorps_list`, same `{ blorps = {...} }` shape as the cross-plugin
  broadcast payload) and the current room id (`room_changed`, see
  below), so a freshly opened panel is in sync immediately.
- `M.panel:on_message("add", function(data) ... end)` — calls the same
  `blorps.add(data.name)` function `/blorp add` uses. The panel never
  sends a room id; the current room is always read server-side from
  `state.current_room`, exactly like the command path, so the panel
  can't desync from or spoof the tracked room.
- `M.panel:on_message("remove", function(data) ... end)` — calls
  `blorps.remove(data.name)`.
- Errors (unknown room, unknown name on remove) surface the same way
  they do for commands — via `mud.note` to the main MUD window — rather
  than inventing a second, panel-only notification channel.
- `blorps.lua`'s mutate functions, in addition to `events.emit`-ing the
  cross-plugin broadcast, post the updated list to the panel
  (`M.panel:post("blorps_list", {...})`) so it stays live without a
  manual refresh. `state.lua`'s room-tracking handler likewise posts
  `room_changed` to the panel whenever `state.current_room` changes.

**UI side** (`ui/panel.html`, `ui/panel.css`, `ui/panel.js`): renders
the list (name + room id per row, a remove button per row) and an
add-form (text input + "Add" button) that posts `{name}` to Lua on
submit. Shows the current room id (or an "unknown room" state) and
disables the "Add" button while it's unknown, mirroring the command
path's own guard rather than letting the user submit a doomed request.
No client-side unit tests are added for this file — consistent with
cowtography, which doesn't unit-test its panel JS either; verification
is manual, in the running client (see Testing).

## Cross-plugin event contract

Mallard's `events.on`/`events.emit` bus is per-world and shared by every
plugin on that world — it is not scoped to a specific pair of plugins —
so event names are namespaced with the plugin id to avoid colliding with
other plugins' event names, following the precedent set by
`discworld-group-shields`' `net.mallard.discworld.shield.up` events.

- **`broaty.discworld-blorpsack.blorps`** — the broadcast. Emitted only
  after every successful `/blorp add` or `/blorp rm`, and in response to
  a `.request` (below). Blorpsack does **not** broadcast on its own
  plugin load — it still hydrates its in-memory list from `storage` at
  load, for its own commands to use, but emits nothing until asked or
  until a mutation happens.

  Payload:
  ```lua
  { blorps = { { room_id = "r123", name = "market" }, ... } }
  ```

- **`broaty.discworld-blorpsack.blorps.request`** — blorpsack listens
  for this and immediately emits the full `...blorps` broadcast above.
  This is how a consumer gets the initial list: since blorpsack and
  cowtography are independent plugins with independent
  install/enable/reload lifecycles, there is no reliable "blorpsack has
  just loaded" moment for a consumer to hook. Instead the consumer is
  responsible for asking — e.g. cowtography waits a short delay after
  its own load (giving blorpsack's own load a chance to finish first)
  and then emits `.request` — rather than blorpsack broadcasting
  unprompted at a time no one may be listening yet. Payload is ignored
  (any table, including `{}`, is fine).

Every `add`/`rm` mutation broadcasts the full current list
unconditionally on success — no diffing against the previous state —
keeping the emit logic trivial; consumers simply replace their in-memory
copy on receipt.

## File layout

Small enough not to need cowtography's dozen-module split, but follows
the same discipline that codebase documents: Mallard's plugin `require()`
has no caching and re-executes the target file from scratch on every
call, and caps a plugin's Lua VM at 32MB. So every module here is
required from exactly one place — `main.lua` — and receives its
collaborators via its own `init(deps)` function, never via its own
`require()`.

```
plugin.toml
src/main.lua               -- thin entry: require + wire init(deps)
src/blorpsack/state.lua    -- current_room, char_name, GMCP handlers, world.on("connect")
src/blorpsack/panel.lua    -- mud.panel("blorps") handle, post/on_message wiring
src/blorpsack/blorps.lua   -- storage CRUD, broadcast emit, .request listener, panel:post
src/blorpsack/commands.lua -- /blorp command, list/add/rm formatting
ui/panel.html
ui/panel.css
ui/panel.js
```

`state.lua` has no cross-module dependencies (mirrors cowtography's
`state.lua`/`colors.lua`, which get no `init()` call), but its
room-tracking handler needs `panel` (to post `room_changed`), taken via
`init(deps)`. `panel.lua` needs `blorps` (to call `add`/`remove` from
its `on_message` handlers), also via `init(deps)` — its
`M.panel:on_message(...)` registrations are set up inside `M.init`, or
reference a module-level local assigned there, the same way
`cowtography.gmcp`'s top-level `gmcp.on(...)` handlers close over
locals set inside its own `M.init`; the closures aren't invoked until
after every module's `init()` has run. `blorps.lua` depends on `state`
(for `current_room`/`char_name`) and `panel` (to push UI updates) via
`init(deps)`. `commands.lua` depends on both `state` and `blorps` via
`init(deps)`. `panel.lua` is required before `blorps.lua` in `main.lua`
so the latter's `init(deps)` can receive it — no module ever calls
`require()` on another `blorpsack.*` module directly, only `main.lua`
does, exactly once each, per the require-caching caveat above.

## Testing

Plain Lua unit tests (`lua tests/*.lua`, run directly, no JS/vitest layer
— blorpsack has no data-build pipeline like cowtography's Quow-DB
import). Add `tests/support/fake_host.lua` providing minimal `storage`,
`events`, `gmcp`, `mud`, and `world` fakes (in the spirit of
cowtography's `tests/support/fake_db.lua` for its DB layer), plus a
minimal `mud.panel(id)` fake (a stub handle recording `:post` calls and
letting tests invoke registered `:on_message` handlers directly) so that
`blorps.lua`'s CRUD/broadcast logic, `commands.lua`'s command handling,
and `panel.lua`'s message dispatch can all be driven and asserted
without a real Mallard runtime.

Coverage to include:
- `add` on a fresh name creates an entry and broadcasts once.
- `add` on an existing name overwrites the room id and broadcasts.
- `add` with no known `current_room` errors and does not broadcast.
- `rm` on an existing name removes it and broadcasts.
- `rm` on an unknown name errors and does not broadcast.
- Storage keying changes correctly when `char_name` becomes known
  (falls back to `'blorps'` before, `'blorps_<name>'` after).
- Plugin load hydrates the in-memory list from storage but emits no
  broadcast.
- `.request` triggers an emit of the current list without mutating
  storage.
- Panel `add`/`remove` messages reach the same `blorps.lua` functions
  as the equivalent commands, and produce the same broadcast/storage
  effects (i.e. the panel isn't a second, divergent code path).
- A successful mutation posts an updated `blorps_list` to the panel, in
  addition to the cross-plugin broadcast.

`ui/panel.js`'s DOM rendering itself is not unit tested, matching
cowtography's own panels; it's verified manually by opening the panel
in a running Mallard client and exercising add/remove/room-unknown
states (see the `run` skill for driving the client).
