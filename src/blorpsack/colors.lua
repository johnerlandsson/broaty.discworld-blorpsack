-- src/blorpsack/colors.lua
-- Shared note colours and the mud.note wrapper, matching cowtography's own
-- colors.lua styling conventions.

local M = {}

M.C = {
  header = '#ffcc88',
  alt    = '#cccccc',
  err    = '#ff6666',
  ok     = '#aaffaa',
  muted  = '#888888',
}

function M.note(text, colour)
  mud.note(text, { fg = colour or M.C.alt })
end

return M
