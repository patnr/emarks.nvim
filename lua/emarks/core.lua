local M = {}

-- ╔═════════════════════════════════════════════════════╗
-- ║ Core (in-memory) functionality (set/get/goto/clear) ║
-- ╚═════════════════════════════════════════════════════╝

-- We only keep track of the extmark id's.
local extmarks = {}
-- The actual mark locations are kept track of by `ns`,
-- and change continuously as the buffer is modified.
local ns = vim.api.nvim_create_namespace("emarks")

-- The following converts id to filename and pos.
function M.extmark_locations()
  local marks = {}
  for label, mark in pairs(extmarks) do
    local buf, pos = mark[1], mark[2]
    if type(buf) == "number" then
      if vim.api.nvim_buf_is_loaded(buf) then
        -- Convert bufnr to filenames
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

-- Aux info
local views = {}
local last_visited_label = nil

function M.set(label, bufnr, linenr, colnr, view)
  pcall(M.clear,label) -- clear mark with this label (if exists)
  local id = vim.api.nvim_buf_set_extmark(bufnr, ns, linenr, colnr, -- PS: NW corner: (0, 0)
    -- Padding ⇒ right-align (o/w sign automatically get right-padded to width 2)
    -- Use lower priority than nvim-dap (21)
    {sign_text=" " .. label, sign_hl_group="DiagnosticHint", priority=10,
      -- If char at mark is replaced (using `r`) the mark should not move. Seems to require:
    right_gravity=false
    })
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
  if mark == nil then
    print("Error: No mark with label " .. label)
    return
  end

  last_visited_label = label
  local buf, id = mark[1], mark[2]
  if type(buf) == "string" then
    -- Buffer not loaded, so open it (triggers `reload_for_buffer`,
    -- converting `buf` to a number) and then try again
    vim.api.nvim_command("e " .. buf)
    M.goto_mark(label)

  else
    -- Buffer is loaded, but not necessarily in a window
    local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, id, {})
    local win_num = vim.fn.bufwinid(buf)
    if win_num ~= -1 then
      vim.api.nvim_set_current_win(win_num)
    else
      -- vim.api.nvim_set_current_buf(buf) -- doesnt get shown in bufferline
      vim.api.nvim_command("e " .. vim.fn.bufname(buf))
    end

    -- Set cursor
    if pos[1] then
      vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })

      -- Set view
      if options.restore_view then
        local view = views[label]
        if view then
          -- Compensate for the fact that views dont update like extmarks
          local diff = pos[1] +1 - view.lnum
          view.lnum = view.lnum + diff
          view.topline = view.topline + diff
          view.col = pos[2]
          vim.fn.winrestview(view)
        end
      end
    end
  end
end

function M.clear(label)
  if label == nil then
    for lbl, _ in pairs(extmarks) do
      M.clear(lbl)
    end
  else
    local buf, id = unpack(extmarks[label])
    -- Ignore errors (e.g. if file changed outside of this session)
    local _, _ = pcall(vim.api.nvim_buf_del_extmark, buf, ns, id)
    extmarks[label] = nil
    views[label] = nil
  end
end

function M.get_mark_label(bufnr, lnum)
  for label, mark in pairs(M.extmark_locations()) do
    local bufname, pos = mark[1], mark[2]
    if vim.fn.bufnr(bufname) == bufnr and pos[1] == lnum then
      return label
    end
  end
end

function M.get_mark_label_here()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  local bufnr = vim.api.nvim_get_current_buf()
  return M.get_mark_label(bufnr, lnum)
end

function M.clear_mark_here()
  local lbl = M.get_mark_label_here()
  if lbl then
    M.clear(lbl)
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
  last_visited_label= M.get_mark_label_here() or last_visited_label

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
setmap("n", "<M-N>", function() M.goto_mark_cyclical(1) end, {desc="Next emark"})
setmap("n", "<M-P>", function() M.goto_mark_cyclical(-1) end, {desc="Prev. emark"})

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
setmap("n", "<leader>'", function () M.show() end, {desc="Edit emarks"})
setmap("n", "dm", M.clear_mark_here, {desc="Del/Clear emark"})
-- stylua: ignore end

-- Map "mm" to set a mark with the lowest available label
setmap("n", "mm", M.mark_here_auto, {desc="Emark here"})


-- ╔════════════════════╗
-- ║ Read/Write storage ║
-- ╚════════════════════╝
---@type string?
M.current = nil

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

-- Merely a visual aid. Defined below
local append_line_contents

function M.save(line_contents)
  local file = io.open(M.current, "w")
  local marks = M.extmark_locations()
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

-- Load entire emarks file (also used after manual edits)
function M.load()
  extmarks = {}
  views = {}
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

-- *Set* (not merely load) emarks in current buffer.
-- PS: dont want to set all project emarks coz would necessitate loading respective buffers.
function M.reload_for_buffer()
  local current_bufr = vim.api.nvim_get_current_buf()
  local current_name = vim.fn.fnamemodify(vim.fn.bufname(), ":p")
  for label, mark in pairs(extmarks) do
    local bufname, pos = mark[1], mark[2]
    bufname = vim.fn.fnamemodify(bufname, ":p")
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

vim.api.nvim_create_autocmd("BufReadPost", {
  group = "aug_emarks",
  callback = M.reload_for_buffer,
})


-- ╔══════════════════════════════════════╗
-- ║ Facilitate view/edit of storage file ║
-- ╚══════════════════════════════════════╝

-- Parse label from emarks file
local function parse_mark_label(line)
  return line:match('^%s*%[?"?([%w_]+)"?%]?%s*=')
end

-- Add (in comments) the line contents of a mark
function append_line_contents(txt, marks)
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

-- Edit raw emarks file
function M.show()
  vim.api.nvim_command("e " .. vim.fn.fnameescape(M.current))
end

-- Trigger load
vim.api.nvim_create_autocmd("BufWritePost", {
  group = "aug_emarks",
  pattern = "*/emarks/*.emarks",
  callback = M.load,
})

-- <CR> to goto mark from emarks file
vim.api.nvim_create_autocmd("BufEnter", {
  group = "aug_emarks",
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
    end, { buffer = true, desc="Goto emark" })
  end,
})


return M
