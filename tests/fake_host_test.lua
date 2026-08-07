-- Run from project root: lua tests/fake_host_test.lua
package.path = './src/?.lua;./tests/?.lua;' .. package.path

local fake_host = require('support.fake_host')

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

test('storage set/get round-trips and records the set', function()
  local H = fake_host.install()
  storage.set('k', { a = 1 })
  assert(storage.get('k').a == 1)
  assert(H.storage_data.k.a == 1)
  assert(H.storage_sets[1].key == 'k')
end)

test('storage delete clears the value', function()
  local H = fake_host.install()
  storage.set('k', 'v')
  storage.delete('k')
  assert(storage.get('k') == nil)
  assert(storage.has('k') == false)
end)

test('events.on/emit dispatches to the listener and records the emit', function()
  local H = fake_host.install()
  local seen = nil
  events.on('foo', function(data) seen = data end)
  events.emit('foo', { x = 1 })
  assert(seen.x == 1)
  assert(H.event_emits[1].name == 'foo')
end)

test('gmcp.on fires via fire_gmcp', function()
  local H = fake_host.install()
  local seen
  gmcp.on('room.info', function(_prefix, data) seen = data end)
  H.fire_gmcp('room.info', { identifier = 'r1' })
  assert(seen.identifier == 'r1')
end)

test('gmcp.get returns a seeded value', function()
  local H = fake_host.install()
  H.gmcp_values['char.info.capname'] = 'Dilbo'
  assert(gmcp.get('char.info.capname') == 'Dilbo')
end)

test('world.on fires via fire_world', function()
  local H = fake_host.install()
  local fired = false
  world.on('connect', function() fired = true end)
  H.fire_world('connect')
  assert(fired == true)
end)

test('mud.command registers a callable handler', function()
  local H = fake_host.install()
  mud.command('blorp', function(m) return m.args end, { description = 'x' })
  assert(H.commands.blorp({ args = 'hi' }) == 'hi')
end)

test('mud.note records its call', function()
  local H = fake_host.install()
  mud.note('  hello', { fg = '#fff' })
  assert(H.notes[1][1] == '  hello')
end)

test('mud.panel creates a trackable fake handle', function()
  local H = fake_host.install()
  local p = mud.panel('blorps')
  p:on_message('ready', function(_data) end)
  p:post('blorps_list', { blorps = {} })
  assert(H.panels.blorps.posts[1].name == 'blorps_list')
  H.panels.blorps.handle:fire('ready', {})
end)

test('new_panel produces an independent handle', function()
  local handle, posts = fake_host.new_panel('x')
  handle:post('a', { n = 1 })
  assert(posts[1].name == 'a')
  local received
  handle:on_message('b', function(data) received = data end)
  handle:fire('b', { n = 2 })
  assert(received.n == 2)
end)

print(string.format('\n%d tests passed.', passed))
