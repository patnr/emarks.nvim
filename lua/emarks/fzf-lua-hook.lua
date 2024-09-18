local emarks = require("emarks.core")

local ok, core = pcall(require, "fzf-lua.core")
if not ok then
  return
end

local core = require("fzf-lua.core")
local config = require("fzf-lua.config")
local builtin = require("fzf-lua.previewer.builtin")
local path = require("fzf-lua.path")
local libuv = require("fzf-lua.libuv")
local utils = require("fzf-lua.utils")

local uv = vim.uv or vim.loop

-- ╔══════════╗
-- ║ Populate ║
-- ╚══════════╝
-- Similar to lua/fzf-lua/providers/nvim.lua:marks()

local function read_line_from_file(filepath, line_number)
  local file = io.open(filepath, "r")
  if not file then
    return nil
  end

  local current_line = 0
  for line in file:lines() do
    current_line = current_line + 1
    if current_line == line_number then
      file:close()
      return line
    end
  end

  file:close()
  -- print("Exceeded the number of lines in file")
  return nil
end

local function get_emarks()
  local marks = emarks.marks_for_storage()
  local entries = {}
  for label, data in pairs(marks) do
    local bufname, pos = unpack(data)
    local line, col = unpack(pos)
    if path.is_absolute(bufname) then
      bufname = path.HOME_to_tilde(bufname)
    end

    -- Add line contents
    local ln_content = read_line_from_file(bufname, line)
    ln_content = ln_content:gsub("^%s*(.-)%s*$", "%1") -- de-indent
    -- Only works for loaded buffers:
    -- if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    --   ln_content = vim.api.nvim_buf_get_lines(bufnr, line - 1, line, false)[1]
    -- else
    --   ln_content = "[buffer not loaded]"
    -- end

    table.insert(
      entries,
      string.format(
        " %-15s %15s %15s %-30s %s",
        utils.ansi_codes.yellow(label),
        utils.ansi_codes.blue(tostring(line)),
        utils.ansi_codes.green(tostring(col)),
        bufname .. ":: ",
        utils.ansi_codes.blue(ln_content)
      )
    )
  end

  -- stylua: ignore
  table.sort(entries, function(a, b) return a < b end)
  table.insert(entries, 1, string.format("%-5s %s  %s %s", "mark", "line", "col", "file/text"))
  return entries
end

-- ╔═══════════╗
-- ║ Previewer ║
-- ╚═══════════╝
-- Similar to lua/fzf-lua/previewer/builtin.lua:marks()
-- and https://github.com/ibhagwan/fzf-lua/wiki/Advanced#neovim-builtin-preview
local EmarkPreviewer = builtin.marks:extend()
function EmarkPreviewer:new(o, opts2, fzf_win)
  EmarkPreviewer.super.new(self, o, opts2, fzf_win)
  setmetatable(self, EmarkPreviewer)
  return self
end
function EmarkPreviewer:parse_entry(entry_str)
  -- Assume an arbitrary entry in the format of 'file:line'
  local bufnr = nil
  local mark, lnum, col, filepath, _ = entry_str:match("(.)%s+(%d+)%s+(%d+)%s+(.*):: (.*)")
  if not mark then
    return {}
  end
  if #filepath > 0 then
    local ok, res = pcall(libuv.expand, filepath)
    if not ok then
      filepath = ""
    else
      filepath = res
    end
    filepath = path.relative_to(filepath, uv.cwd())
  end
  return {
    bufnr = bufnr,
    path = filepath,
    line = tonumber(lnum) or 1,
    col = tonumber(col) or 1,
  }
end


-- ╔═══════════════════╗
-- ║ Selection handler ║
-- ╚═══════════════════╝
-- Similar to lua/fzf-lua/actions.lua:goto_mark()
local function goto_emark(selected)
  local mark = selected[1]
  mark = mark:match("[^ ]+")
  emarks.goto_mark(mark)
  vim.cmd("stopinsert")
  vim.cmd("normal! zz")
end


-- ╔═════╗
-- ║ Map ║
-- ╚═════╝
vim.keymap.set("n", "''", function(opts)
  opts = config.normalize_opts(opts, "marks")
  if not opts then return end

  local entries = get_emarks()

  opts.fzf_opts["--header-lines"] = 1
  opts.actions.enter = goto_emark
  -- opts.actions.default = goto_emark -- no effect?

  -- NB: Don't know why tbl_deep_extend necessary, but it is!
  opts = vim.tbl_deep_extend("force", opts, { previewer = EmarkPreviewer })

  core.fzf_exec(entries, opts)
end, { desc = "Emarks" })

