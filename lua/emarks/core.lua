local M = {}
---@type string?
M.current = nil

-- ╔════════════════════╗
-- ║ Core functionality ║
-- ╚════════════════════╝
local ns = vim.api.nvim_create_namespace("emarks")

-- With the exception of the occasion of storing them,
-- we don't need to keep track of the positions of the marks
-- (which change as the buffer is modified), only their id's.
local extmarks = {}
local views = {}
local last_visited_label = nil

function M.set(label, bufnr, linenr, colnr, view)
  local id = vim.api.nvim_buf_set_extmark(bufnr, ns, linenr, colnr, {}) -- PS: NW corner: (0, 0)
  extmarks[label] = { bufnr, id }
  views[label] = view
  -- print("Set extmark with label " .. label .. " at " .. linenr .. ":" .. colnr)
end

function M.mark_here(label)
  local pos = vim.api.nvim_win_get_cursor(0) -- PS: NW corner: (1, 0)
  local bufnr = vim.api.nvim_get_current_buf()
  local view = vim.fn.winsaveview()
  M.set(label, bufnr, pos[1] - 1, pos[2], view)
end

M.goto_mark = function(label, opts)
  local options = { restore_view = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  local mark = extmarks[label]
  if mark ~= nil then
    last_visited_label = label
    local buf, id = mark[1], mark[2]
    if type(buf) == "string" then
      -- Need to open buffer (and reload_for_buffer)
      vim.api.nvim_command("e " .. buf)
      M.goto_mark(label)
    else
      local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
      local win_num = vim.fn.bufwinid(buf)
      if win_num ~= -1 then
        vim.api.nvim_set_current_win(win_num)
      else
        -- vim.api.nvim_set_current_buf(buf) -- doesnt get shown in bufferline
        vim.api.nvim_command("e " .. vim.fn.bufname(buf))
      end
      if pos[1] then
        vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
        if options.restore_view then
          if views[label] then
            vim.fn.winrestview(views[label])
          end
        end
      end
    end
  else
    print("Error: No mark with label " .. label)
  end
end

function M.goto_mark_cyclical(inc)
  local labels = vim.tbl_keys(extmarks)
  -- TODO: would like to not do sort, but rather use the order in which marks were set.
  -- However, a dict is not ordered, so we would need to maintain a separate list
  -- (requires more bookkeeping, especially since we allow manual editing of the corresponding file)
  -- or change the data structure extmarks to a list of {label, mark} pairs
  -- (while AI can surely do this, would also need to change hooks for plugins, including mini.map)
  table.sort(labels)

  -- Init
  if not last_visited_label then
    last_visited_label = labels[1]
  end

  -- Check if currently on a line with a mark
  local current_lnum, _ = unpack(vim.api.nvim_win_get_cursor(0))
  local current_buf = vim.api.nvim_get_current_buf()
  for label, mark in pairs(M.marks_for_storage()) do
    local bufname, pos = mark[1], mark[2]
    if vim.fn.bufnr(bufname) == current_buf and pos[1] == current_lnum then
      last_visited_label = label
      break
    end
  end

  -- Goto next/prev
  for i, label in ipairs(labels) do
    if label == last_visited_label then
      local i1 = (i + inc - 1) % #labels + 1
      local l1 = labels[i1]
      M.goto_mark(l1)
      return
    end
  end
end

function M.clear(label)
  if label == nil then
    for lbl, _ in pairs(extmarks) do
      M.clear(lbl)
    end
  else
    extmarks[label] = nil
    views[label] = nil
  end
end

-- ╔════════════════════╗
-- ║ Read/Write storage ║
-- ╚════════════════════╝

function M.set_marks_file()
  local pattern = "/"
  if vim.fn.has("win32") == 1 then
    pattern = "[\\:]"
  end
  local name = vim.fn.getcwd():gsub(pattern, "%%") .. ".emarks"
  name = require("emarks.config").options.dir .. name
  if not vim.uv.fs_stat(name) then
    local file = io.open(name, "w")
    if file then
      file:close()
    else
      print("Error: Unable to open file " .. name .. " for writing")
    end
  end
  M.current = name
end

function M.reload_for_buffer()
  local current_bufr = vim.api.nvim_get_current_buf()
  local current_name = vim.fn.bufname()
  for label, mark in pairs(extmarks) do
    local bufname, pos = mark[1], mark[2]
    if type(bufname) == "string" and bufname == current_name then
      local ok, _ = pcall(M.set, label, current_bufr, pos[1] - 1, pos[2] - 1, views[label])
      if not ok then
        -- Possible causes: manual editing of marks file
        -- or changes to buffer outside of this neovim/emarks session.
        print("Error: Unable to set extmark with label " .. label)
        M.clear(label)
      end
    end
  end
end

function M.load()
  local file = io.open(M.current, "r")
  if file then
    local data = load("return " .. file:read("*all"))() or {}
    extmarks = data.extmarks or {}
    views = data.views or {}
    file:close()
    -- print("Marks loaded")
  else
    print("Error: Unable to open " .. file .. " for reading")
  end
end

local function parse_mark_label(line)
  return line:match('^%s*%[?"?([%w_]+)"?%]?%s*=')
end

local function append_line_contents(txt, marks)
  local lines = vim.split(txt, "\n")
  for i = 1, #lines do
    -- Must extract label from printed text because sorted, unlike `marks`.
    -- The label occurs as `["6"] = ...` or `a = ...`
    local lbl = parse_mark_label(lines[i])
    local mark = marks[lbl]
    if mark ~= nil then
      local bufname, pos = mark[1], mark[2]
      local iLine, iCol = pos[1], pos[2] ---@diagnostic disable-line: unused-local
      local bufnr = vim.fn.bufnr(bufname)
      local line
      if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
        line = vim.api.nvim_buf_get_lines(bufnr, iLine - 1, iLine, false)[1]
        -- Only use for debugging (since it obscures subsequent grepping): indicate column:
        -- line = line:sub(1, iCol) .. "[" .. line:sub(iCol+1, iCol+1) .. "]" .. line:sub(iCol + 2)
        line = line:gsub("^%s*(.-)%s*$", "%1")
      else
        line = "[buffer not loaded]"
      end
      lines[i] = lines[i] .. " -- " .. line
    end
  end
  txt = table.concat(lines, "\n")
  return txt
end

function M.save(line_contents)
  local file = io.open(M.current, "w")
  local marks = M.marks_for_storage()
  local txt = vim.inspect({ extmarks = marks, views = views })
  if line_contents then
    txt = append_line_contents(txt, marks)
  end

  if file then
    file:write(txt)
    file:close()
    -- print("Marks saved")
  else
    print("Error: Unable to open file for writing")
  end
end

-- Return fresh `marks` with any/all bufnr and mark-id converted to name and pos.
function M.marks_for_storage()
  local marks = {}
  for label, mark in pairs(extmarks) do
    local buf, pos = mark[1], mark[2]
    if type(buf) == "number" then
      if vim.api.nvim_buf_is_loaded(buf) then
        -- Convert buffer id's to filenames
        pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, pos, {})
        buf = vim.fn.bufname(buf)
        if pos[1] then
          -- Convert from (0, 0)-based indexing (api) to (1, 1)-based indexing
          pos[1] = pos[1] + 1
          pos[2] = pos[2] + 1
          marks[label] = { buf, pos }
        end
      end
    else
      marks[label] = { buf, pos }
    end
  end
  return marks
end

function M.show()
  vim.api.nvim_command("e " .. vim.fn.fnameescape(M.current))
end

vim.api.nvim_create_autocmd("BufReadPost", {
  group = "mygroup",
  callback = M.reload_for_buffer,
})

-- ╔════════╗
-- ║Mappings║
-- ╚════════╝
local function setmap(mode, lhs, rhs, opts)
  local options = { noremap = true, silent = true }
  if opts then
    options = vim.tbl_extend("force", options, opts)
  end
  vim.keymap.set(mode, lhs, rhs, options)
end

-- Shift-opt-n/p (h/l also available?)
-- stylua: ignore start
setmap("n", "<M-N>", function() M.goto_mark_cyclical(1) end)
setmap("n", "<M-P>", function() M.goto_mark_cyclical(-1) end)

local labels = {}
for i = 1, 9 do labels[#labels + 1] = tostring(i) end
for charCode = string.byte("A"), string.byte("Z") do labels[#labels + 1] = string.char(charCode) end
for charCode = string.byte("a"), string.byte("z") do labels[#labels + 1] = string.char(charCode) end
M.labelS = table.concat(labels, "")

for _, lbl in ipairs(labels) do
  setmap("n", "m" .. lbl, function() M.mark_here(lbl) end)
  setmap("n", "'" .. lbl, function() M.goto_mark(lbl) end)
  setmap("v", "'" .. lbl, function() M.goto_mark(lbl) end)
  -- For the above labels, shadow § (which I map to backtick, i.e. built-in marks)
  setmap("n", "§" .. lbl, function() M.goto_mark(lbl, { restore_view = false }) end)
  setmap("v", "§" .. lbl, function() M.goto_mark(lbl, { restore_view = false }) end)
end
setmap("n", "<leader>'", M.show)
-- stylua: ignore end

-- Function to get the lowest available label
function M.get_lowest_available_label()
  local possible_lables = "123456789qwertyuipasdfghjkl"
  for i = 1, #possible_lables do
    local label = possible_lables:sub(i, i)
    if not extmarks[label] then
      return label
    end
  end
  return nil -- In case all possible_lables are used
end

-- Function to set a mark with the lowest available label
function M.mark_here_auto()
  local label = M.get_lowest_available_label()
  if label then
    M.mark_here(label)
  else
    print("Error: No more available labels")
  end
end

-- Map "mm" to set a mark with the lowest available label
setmap("n", "mm", M.mark_here_auto)

-- ╔════════════════════════════════╗
-- ║ Hook into lazyvim statuscolumn ║
-- ╚════════════════════════════════╝
---@diagnostic disable-next-line: duplicate-set-field
require("lazyvim.util.ui").get_mark = function(buf, lnum)
  for label, mark in pairs(M.marks_for_storage()) do
    local bufname, pos = mark[1], mark[2]
    if vim.fn.bufnr(bufname) == buf and pos[1] == lnum then
      return { text = label:sub(1, 2), texthl = "Identifier" }
    end
  end

  -- Show built-in marks not used by us
  local marks = vim.fn.getmarklist(buf)
  vim.list_extend(marks, vim.fn.getmarklist())
  for _, mark in ipairs(marks) do
    if mark.pos[1] == buf and mark.pos[2] == lnum and not mark.mark:match("[" .. M.labelS .. "]") then
      return { text = mark.mark:sub(2), texthl = "Identifier" }
    end
  end
end

-- ╔═══════════════════════════╗
-- ║autocommands for marks file║
-- ╚═══════════════════════════╝
vim.api.nvim_create_autocmd("BufWritePost", {
  group = "mygroup",
  pattern = "*/emarks/*.emarks",
  callback = function()
    extmarks = {}
    views = {}
    M.load()
  end,
})

vim.api.nvim_create_autocmd("BufEnter", {
  group = "mygroup",
  pattern = "*/emarks/*.emarks",
  callback = function()
    M.save(true)
    vim.api.nvim_command("e " .. vim.fn.fnameescape(M.current))
    vim.api.nvim_set_option_value("syntax", "lua", { buf = 0 })
    -- Go to mark on enter
    setmap("n", "<CR>", function()
      local line = vim.api.nvim_get_current_line()
      local lbl = parse_mark_label(line)
      if lbl then
        M.goto_mark(lbl)
      end
    end, { buffer = true })
  end,
})

return M
