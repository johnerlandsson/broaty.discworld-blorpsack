-- Run from project root: lua tests/main_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')
local H = fake_host.install()

require('main')

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

test('main wires a room.info GMCP event through to a successful /blorp add', function()
  H.fire_gmcp('room.info', { identifier = 'r1' })
  H.commands.blorp({ args = 'add market' })

  assert(#H.event_emits == 1)
  assert(H.event_emits[1].name == 'broaty.discworld-blorpsack.blorps')
  assert(H.event_emits[1].data.blorps[1].name == 'market')

  local panel_posts = H.panels.blorps.posts
  assert(panel_posts[#panel_posts].name == 'blorps_list')
  assert(panel_posts[#panel_posts].data.blorps[1].room_id == 'r1')

  assert(H.notes[#H.notes][1]:match('Registered blorp "market" at r1'))
end)

test('a panel "ready" message reflects the room the command already saw', function()
  H.panels.blorps.handle:fire('ready', {})
  local panel_posts = H.panels.blorps.posts
  assert(panel_posts[#panel_posts].name == 'room_changed')
  assert(panel_posts[#panel_posts].data.room_id == 'r1')
end)

test('a panel "add" message reaches the same blorps list a command would see', function()
  H.panels.blorps.handle:fire('add', { name = 'bank' })
  H.commands.blorp({ args = '' })
  local found = false
  for _, n in ipairs(H.notes) do
    if n[1]:match('bank') then found = true end
  end
  assert(found)
end)

test('.request event re-broadcasts the current list', function()
  local before = #H.event_emits
  H.fire_event('broaty.discworld-blorpsack.blorps.request', {})
  assert(#H.event_emits == before + 1)
  local emitted = H.event_emits[#H.event_emits]
  local names = {}
  for _, b in ipairs(emitted.data.blorps) do names[b.name] = true end
  assert(names.market == true)
  assert(names.bank == true)
end)

print(string.format('\n%d tests passed.', passed))
