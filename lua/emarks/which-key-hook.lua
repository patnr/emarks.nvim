-- ╔═══════════════════════════╗
-- ║ Hook into which-key marks ║
-- ╚═══════════════════════════╝
local wk = require('which-key.plugins.marks')
local em = require('emarks.core')

-- Format as vim.fn.getmarklist
local function getmarklist()
  local marks = em.marks_for_storage()
  local out = {}
  for label, mark in pairs(marks) do
    local bufname, pos = mark[1], mark[2]
    local bufnr = vim.fn.bufnr(bufname)
    local m = {file=bufname, mark="'" .. label, pos={bufnr, pos[1], pos[2]}}
    out[#out+1] = m
  end
  return out
end

local labels = {
  ["^"] = "Last position of cursor in insert mode",
  ["."] = "Last change in current buffer",
  ['"'] = "Last exited current buffer",
  ["0"] = "In last file edited",
  ["'"] = "Back to line in current buffer where jumped from",
  ["`"] = "Back to position in current buffer where jumped from",
  ["["] = "To beginning of previously changed or yanked text",
  ["]"] = "To end of previously changed or yanked text",
  ["<lt>"] = "To beginning of last visual selection",
  [">"] = "To end of last visual selection",
}

-- Copy-paste from plugin, except for 1 change (see below)
function wk.run(_trigger, _mode, buf)
  local items = {}

  -- NOTE: here is the only change made to the plugin
  local marks = {}
  -- vim.list_extend(marks, vim.fn.getmarklist(buf))
  -- vim.list_extend(marks, vim.fn.getmarklist())
  -- local filtered = {}
  -- for _, mark in ipairs(marks) do
  --   if not mark.mark:match("["..em.labelS.."]") then
  --     filtered[#filtered+1] = mark
  --   end
  -- end
  -- marks = filtered
  vim.list_extend(marks, getmarklist())

  for _, mark in pairs(marks) do
    local key = mark.mark:sub(2, 2)
    if key == "<" then
      key = "<lt>"
    end
    local lnum = mark.pos[2]

    local line
    if mark.pos[1] and mark.pos[1] ~= 0 then
      local lines = vim.fn.getbufline(mark.pos[1], lnum)
      if lines and lines[1] then
        line = lines[1]
      end
    end

    local file = mark.file and vim.fn.fnamemodify(mark.file, ":p:~:.")

    local value = string.format("%4d  ", lnum)
    value = value .. (line or file or "")

    table.insert(items, {
      key = key,
      label = labels[key] or file and ("file: " .. file) or "",
      value = value,
      highlights = { { 1, 5, "Number" } },
    })
  end
  return items
end
