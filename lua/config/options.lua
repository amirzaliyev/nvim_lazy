-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.lazyvim_python_lsp = "basedpyright"

-- Installed here because this file loads before lazy.nvim, so the backend is
-- swapped in before any LSP client can register a watcher. Fails open: if the
-- private API it patches has moved, the stock backend stays in place.
local ok, reason = require("config.lsp-watch").setup()
if not ok then
  vim.notify("lsp-watch: using stock watcher (" .. reason .. ")", vim.log.levels.WARN)
end
