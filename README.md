# Discworld Blorpsack

A [Mallard](https://mallard.vnsf.xyz) plugin for [Discworld MUD](https://discworld.starturtle.net/lpc/) that tracks **blorps** — pieces of jewellery enchanted to remember a location — carried by your character, and broadcasts the list for other plugins (e.g. cowtography) to route to.

Blorpsack has no routing or mapping logic of its own. Its whole job is
registering blorps and telling other plugins where they are.

## Commands

Commands use Mallard's client command prefix — `/` by default. Blorps are
stored per character, so a fresh character starts with an empty list even
on the same account and world.

```
/blorp                  — list all registered blorps
/blorp add <name>       — register a blorp named <name> at your current room
/blorp rm <name>        — remove a blorp
```

Adding a blorp with a name that already exists overwrites its stored room
silently — that's how you re-register a blorp after recasting it
somewhere new.

```
/blorp add market        Registered blorp "market" at The Mended Drum.
/blorp                   Blorps:
                            market               The Mended Drum
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
