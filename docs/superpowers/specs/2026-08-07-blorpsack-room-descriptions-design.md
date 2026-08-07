# Blorpsack — room descriptions in the UI — design

## Overview

Blorpsack currently displays a blorp's raw room id (e.g. `r12345`) everywhere
it lists blorps: the `/blorp` command's output and the panel. This is
unfriendly — nobody remembers what a room id means. This change displays
the room's short description (e.g. "The Mended Drum") instead, in both
front ends, while leaving the cross-plugin broadcast contract
(`broaty.discworld-blorpsack.blorps` → `{ blorps = { { room_id, name },
... } }`) exactly as it is today. Consumers like cowtography have no
reason to want a room's display name over its id (they route by id), and
changing the wire contract would be an unrequested, unrelated change to a
contract already documented for external consumption.

This is an addendum to the original design
(`docs/superpowers/specs/2026-08-07-blorpsack-design.md`), not a
replacement — everything there still holds except where noted below.

## Source of the room name

Discworld's GMCP `room.info` package already includes a `name` field
alongside `identifier` — confirmed against cowtography's own `gmcp.lua`,
which already reads `data.name` from the same live payload for its own
purposes. This is available under blorpsack's existing `gmcp_access =
["room.info", ...]` permission — no manifest change needed.

## `state.lua`: track `current_room_name`

A new field, `M.current_room_name`, tracked in lockstep with the existing
`M.current_room` — same lifecycle, same update guard (only changes, and
only posts to the panel, when the room identifier actually changes, not
on every GMCP frame):

- The live `gmcp.on('room.info', ...)` handler passes `data.name` through
  alongside `data.identifier`.
- The `gmcp.get("room.info")` hydration path (`seed_room`, used at
  `M.init` and on `world.on("connect", ...)`) additionally regex-extracts
  `"name"` from the raw JSON string, the same way it already extracts
  `"identifier"`: `raw:match('"name"%s*:%s*"([^"]*)"')`.
- `apply_room(identifier, name)` now takes both and sets both fields
  together when the identifier changes.
- `post_room_changed()`'s payload to the panel becomes `{ room_id =
  M.current_room, room_name = M.current_room_name }` (previously
  `room_id` only) — this feeds both the blorp-list display and, per the
  approved bonus, the panel's own "current room" header.

## `blorps.lua`: storage shape and the broadcast/panel split

**Storage.** Each entry's stored value changes from a plain `room_id`
string to a table: `{ room_id = ..., room_name = ... }`, written by
`M.add` from `state.current_room` / `state.current_room_name` at
registration time.

**Backward compatibility, no migration.** Reading tolerates both shapes:
if a stored entry is still a plain string (written before this change),
it's treated as `room_id` with `room_name = nil`. No migration step, no
storage version field — matches the precedent already set by this
project's storage design (per-character key fallback with no migration,
accepted in the original design).

**`M.list()`** (the single function both `commands.lua` and `panel.lua`
already call) now returns `{ room_id, name, room_name }` per entry —
`name` is the blorp's own name (the map key), unrelated to `room_name`,
which is the room's description and may be `nil` for legacy entries.

**The broadcast stays `{ room_id, name }` only.** `broadcast()` builds
the cross-plugin wire payload by mapping `M.list()`'s decorated entries
down to just `{ room_id, name }` before `events.emit`, so the documented
external contract is byte-for-byte unchanged. The **panel** post
(`panel:post("blorps_list", ...)`) carries the full decorated list
(`room_id`, `name`, `room_name`) — it needs `room_name` to render.

## Display changes

- **`/blorp` list rows** (`commands.lua`): show `room_name`, falling back
  to the literal string `"(unknown room)"` when absent (per your answer —
  never show a raw room id for a stale/legacy entry).
- **`/blorp add` confirmation** (`commands.lua`): shows
  `state.current_room_name`, falling back to the raw `state.current_room`
  id if somehow absent. This is deliberately a different fallback than
  the list rows: at the moment of a successful `add`, the room id is
  live, fresh data (not a stale stored entry), so showing it beats a
  generic placeholder here specifically.
- **Panel blorp list** (`ui/panel.js`): each row shows `b.room_name ||
  "(unknown room)"` instead of `b.room_id`. The CSS class and JS variable
  named `room-id`/`roomId` for this row element are renamed to
  `room-name`/`roomName` for clarity, since that's now what they hold.
- **Panel header** (approved bonus): currently shows the raw current-room
  id (`"Room: r12345"`). Changes to show `currentRoomName ||
  currentRoomId` — falls back to the id only if the name hasn't arrived
  yet. The Add-button-enabled logic is unchanged (still gated on
  `currentRoomId` truthiness — that's the real precondition for adding a
  blorp, independent of whether a friendly name is available to display).

## Testing

All 7 existing test files need updates for the new storage/list shape and
the `current_room_name` plumbing. New coverage to add:

- `state_test.lua`: `current_room_name` is set alongside `current_room`
  from both the live GMCP event and the `gmcp.get` hydration/regex path;
  `room_changed` posts include `room_name`.
- `blorps_test.lua`: `M.add` stores `{ room_id, room_name }`; `M.list()`
  returns the decorated shape; a blorp added when `state.current_room_name`
  happens to be `nil` still stores/lists correctly with `room_name = nil`.
- `blorps_init_test.lua`: a **legacy plain-string** pre-seeded storage
  entry loads correctly via `M.list()` with `room_name = nil` — the
  concrete backward-compatibility proof.
- `commands_test.lua`: list output shows room names; a legacy/nameless
  entry shows `"(unknown room)"`; the add confirmation shows the room
  name.
- `panel_test.lua`: the `"ready"` handler's `room_changed` post includes
  `room_name` from the (now three-field) stub `state` table.
- `main_test.lua`: end-to-end proof that `events.emit`'s payload excludes
  `room_name` while the panel's `blorps_list` post includes it, from the
  same underlying `add`.

No changes to `plugin.toml` (no new permission needed) and no changes to
the cross-plugin event names or the broadcast payload shape.
