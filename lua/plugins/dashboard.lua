local lines = {
  " ▄▄██▄▄ ▄▄▄▄▄▄▄    ▄▄▄▄     ▄▄▄▄     ▄▄▄▄",
  "████▀▀▀ ▀▀▀▀████ ▄██████▄ ▄██████▄ ▄██████▄",
  "▀████▄    ▄▄██▀  ███  ███ ███  ███ ███  ███",
  "  ▀████     ███▄ ███▄▄███ ███▄▄███ ███▄▄███",
  "██████▀ ███████▀  ▀████▀   ▀████▀   ▀████▀",
  "   ▀▀",
}

-- snacks centres each header line independently, so ragged lines drift apart.
-- Pad to a common width to keep the block aligned. Done here rather than with
-- literal trailing spaces, which editors and formatters strip.
local width = 0
for _, line in ipairs(lines) do
  width = math.max(width, vim.fn.strdisplaywidth(line))
end
for i, line in ipairs(lines) do
  lines[i] = line .. string.rep(" ", width - vim.fn.strdisplaywidth(line))
end

return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        sections = {
          { header = table.concat(lines, "\n"), padding = 2 },
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
  },
}
