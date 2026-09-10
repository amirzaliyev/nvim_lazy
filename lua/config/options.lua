-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

vim.g.lazyvim_python_lsp = "basedpyright"

-- Write files in place instead of rename-and-recreate. With the default "auto",
-- a save renames foo.py -> foo.py~ and creates a new foo.py, which the LSP file
-- watcher reports as delete + create. pyright then treats it as a workspace
-- change: re-enumerates files, marks everything dirty and re-binds any module
-- with __all__ (5-7s each for transformers/__init__.py) before re-checking.
-- Verified 2026-09-10 on sl_platform: "yes" produces a single change event.
vim.opt.backupcopy = "yes"

-- Installed here because this file loads before lazy.nvim, so the backend is
-- swapped in before any LSP client can register a watcher. Fails open: if the
-- private API it patches has moved, the stock backend stays in place.
local ok, reason = require("config.lsp-watch").setup()
if not ok then
  vim.notify("lsp-watch: using stock watcher (" .. reason .. ")", vim.log.levels.WARN)
end

-- Over SSH, route yanks to the local terminal's clipboard via OSC 52.
if vim.env.SSH_CONNECTION then
  vim.g.clipboard = "osc52"
  vim.opt.clipboard = "unnamedplus"
end
