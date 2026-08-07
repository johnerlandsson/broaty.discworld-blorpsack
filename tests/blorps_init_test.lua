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
