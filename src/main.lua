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
