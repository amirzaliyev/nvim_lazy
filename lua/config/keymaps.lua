-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>bC", "<cmd>%bd<cr>", { desc = "Close all buffers" })

vim.keymap.set("n", "<F9>", function() require("dap").toggle_breakpoint() end, { desc = "Debug: Toggle Breakpoint" })
vim.keymap.set("n", "<F5>", function() require("dap").continue() end, { desc = "Debug: Continue / Start" })
local function toggle_terminal()
  Snacks.terminal(nil, {
    win = {
      position = "bottom",
      height = 0.3,
      border = "rounded",
    },
  })
end

local function focus_or_toggle_terminal()
  local cur_win = vim.api.nvim_get_current_win()
  if vim.bo[vim.api.nvim_win_get_buf(cur_win)].buftype == "terminal" then
    vim.api.nvim_win_close(cur_win, false)
    return
  end
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].buftype == "terminal" then
      vim.api.nvim_set_current_win(win)
      vim.cmd("startinsert")
      return
    end
  end
  toggle_terminal()
end

vim.keymap.set({ "n", "t" }, "<F7>", focus_or_toggle_terminal, { desc = "Focus or toggle terminal" })
vim.keymap.set({ "n", "t" }, "<C-/>", focus_or_toggle_terminal, { desc = "Focus or toggle terminal" })
vim.keymap.set({ "n", "t" }, "<C-_>", focus_or_toggle_terminal, { desc = "Focus or toggle terminal" })

vim.keymap.set("n", "<leader>o", function()
  if vim.bo.filetype == "snacks_picker_list" then
    vim.cmd.wincmd("p")
  else
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
      if ft == "snacks_picker_list" then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
    Snacks.explorer()
  end
end, { desc = "Toggle focus: explorer ↔ editor" })
