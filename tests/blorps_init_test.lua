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
  assert(#list == 2)
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
