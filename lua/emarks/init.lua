local Config = require("emarks.config")
vim.api.nvim_create_augroup("mygroup", { clear = true })
local emarks = require("emarks.core")
require("emarks.which-key-hook")

local M = {}

function M.setup(opts)
  Config.setup(opts)
  M.start()
end

-- Inspired by persistence.nvim
function M.start()
  emarks.set_marks_file()
  emarks.load()

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = "mygroup",
    callback = function()
      if Config.options.pre_save then
        Config.options.pre_save()
      end

      if not Config.options.save_empty then
        local bufs = vim.tbl_filter(function(b)
          if vim.bo[b].buftype ~= "" then
            return false
          end
          if vim.bo[b].filetype == "gitcommit" then
            return false
          end
          return vim.api.nvim_buf_get_name(b) ~= ""
        end, vim.api.nvim_list_bufs())
        if #bufs == 0 then
          return
        end
      end

      M.save()
    end,
  })
end

function M.stop()
  pcall(vim.api.nvim_del_augroup_by_name, "mygroup")
end

function M.save()
  emarks.save()
end

function M.load(opt)
  emarks.load()
end

return M
