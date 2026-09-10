-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- When a snacks sidebar split opens (explorer, terminal), 'equalalways' first
-- re-fits ALL windows around it and the follow-up resize hands the excess to
-- one neighbor only, leaving the main vsplits unequal. Snacks pins the sidebar
-- with 'winfixwidth' in the same tick it creates the window, so one scheduled
-- width-only equalize ('horizontal wincmd =' honors winfix*) rebalances the
-- main splits around the sidebar. Delete this block to restore stock behavior.
vim.api.nvim_create_autocmd("WinNew", {
  group = vim.api.nvim_create_augroup("sidebar_equalize", { clear = true }),
  callback = function()
    local win = vim.api.nvim_get_current_win()
    vim.schedule(function()
      if not vim.api.nvim_win_is_valid(win) then
        return
      end
      local sw = vim.w[win].snacks_win
      local floating = vim.api.nvim_win_get_config(win).relative ~= ""
      if not sw or floating or sw.relative ~= "editor" then
        return
      end
      if sw.position == "left" or sw.position == "right" then
        vim.api.nvim_win_call(win, function()
          vim.cmd("horizontal wincmd =")
        end)
      end
    end)
  end,
})
