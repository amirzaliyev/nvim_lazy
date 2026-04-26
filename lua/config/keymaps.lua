-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

vim.keymap.set("n", "<leader>bC", "<cmd>%bd<cr>", { desc = "Close all buffers" })

vim.keymap.set("n", "<F9>", function() require("dap").toggle_breakpoint() end, { desc = "Debug: Toggle Breakpoint" })
vim.keymap.set("n", "<F5>", function() require("dap").continue() end, { desc = "Debug: Continue / Start" })
vim.keymap.set({ "n", "t" }, "<F7>", function() Snacks.terminal() end, { desc = "Toggle Terminal" })

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
