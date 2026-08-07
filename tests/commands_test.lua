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
