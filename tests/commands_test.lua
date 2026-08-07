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
