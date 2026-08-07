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
