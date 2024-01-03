local M = {}

---@class EmarksOptions
---@field pre_save? fun()
local defaults = {
  dir = vim.fn.expand(vim.fn.stdpath("state") .. "/emarks/"), -- directory where session files are saved
  save_empty = false, -- don't save if there are no open file buffers
}

---@type EmarksOptions
M.options = {}

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", {}, defaults, opts or {})
  vim.fn.mkdir(M.options.dir, "p")
end

return M
