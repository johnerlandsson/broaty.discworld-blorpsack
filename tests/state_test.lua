-- Run from project root: lua tests/state_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

local panel_handle, panel_posts = fake_host.new_panel('blorps')

H.gmcp_values['char.info.capname'] = 'Dilbo'

local state = require('blorpsack.state')
state.init({ panel = { panel = panel_handle } })

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

test('init hydrates char_name from gmcp.get', function()
  assert(state.char_name == 'Dilbo')
end)

test('room.info gmcp event sets current_room/current_room_name and posts room_changed', function()
  H.fire_gmcp('room.info', { identifier = 'r1', name = 'Market Square' })
  assert(state.current_room == 'r1')
  assert(state.current_room_name == 'Market Square')
  assert(panel_posts[#panel_posts].name == 'room_changed')
  assert(panel_posts[#panel_posts].data.room_id == 'r1')
  assert(panel_posts[#panel_posts].data.room_name == 'Market Square')
end)

test('room.info gmcp event with the same id does not re-post', function()
  local before = #panel_posts
  H.fire_gmcp('room.info', { identifier = 'r1', name = 'Market Square' })
  assert(#panel_posts == before)
end)

test('room.info gmcp event with a new id updates and posts again', function()
  H.fire_gmcp('room.info', { identifier = 'r2', name = 'The Mended Drum' })
  assert(state.current_room == 'r2')
  assert(state.current_room_name == 'The Mended Drum')
  assert(panel_posts[#panel_posts].data.room_id == 'r2')
  assert(panel_posts[#panel_posts].data.room_name == 'The Mended Drum')
end)

test('char.info gmcp event updates char_name', function()
  H.fire_gmcp('char.info', { capname = 'Rincewind' })
  assert(state.char_name == 'Rincewind')
end)

test('world connect reseeds current_room/current_room_name from gmcp.get', function()
  H.gmcp_values['room.info'] = '{"identifier":"r9","name":"Somewhere"}'
  H.fire_world('connect')
  assert(state.current_room == 'r9')
  assert(state.current_room_name == 'Somewhere')
end)

print(string.format('\n%d tests passed.', passed))
