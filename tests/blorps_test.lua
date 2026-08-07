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
