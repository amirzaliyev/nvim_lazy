-- Spinning donut dashboard.
-- Math by Andy Sloane (https://www.a1k0n.net/2011/07/20/donut-math.html).
-- Lua port adapted from Andrew Li's donut.lua
-- (https://github.com/Zeyu-Li/spinning-donuts/blob/master/donut.lua).

local theta_spacing = 0.07
local phi_spacing = 0.02
local chars = { ".", ",", "-", "~", ":", ";", "=", "!", "*", "#", "$", "@" }

local a, ba = 0, 0
local frame_str = ""

local function compute()
  local z, b = {}, {}
  for l = 1, 1760 do
    z[l] = 0
    b[l] = " "
  end

  local j = 0
  while j < 6.28 do
    j = j + theta_spacing
    local i = 0
    while i < 6.28 do
      i = i + phi_spacing
      local c = math.sin(i)
      local l = math.cos(i)
      local d = math.cos(j)
      local f = math.sin(j)
      local e = math.sin(a)
      local g = math.cos(a)
      local h = d + 2
      local D = 1 / (c * h * e + f * g + 5)
      local m = math.cos(ba)
      local n = math.sin(ba)
      local t = c * h * g - f * e
      local x = math.floor(40 + 30 * D * (l * h * m - t * n))
      local y = math.floor(12 + 15 * D * (l * h * n + t * m))
      local o = math.floor(x + 80 * y)
      local N = math.floor(8 * ((f * e - c * d * g) * m - c * d * e - f * g - l * d * n))
      if 22 > y and y > 0 and 80 > x and x > 0 and D > z[o + 1] then
        z[o + 1] = D
        b[o + 1] = N > 0 and chars[N + 1] or "."
      end
    end
  end

  local lines = {}
  for row = 0, 21 do
    lines[row + 1] = table.concat(b, "", row * 80 + 1, (row + 1) * 80)
  end
  frame_str = table.concat(lines, "\n")
end

compute()

local timer

local function tick()
  a = a + 0.07
  ba = ba + 0.03
  compute()
  if _G.Snacks and Snacks.dashboard then
    pcall(Snacks.dashboard.update)
  end
end

local function stop_timer()
  if timer then
    timer:stop()
    timer:close()
    timer = nil
  end
end

vim.api.nvim_create_autocmd("User", {
  pattern = "SnacksDashboardOpened",
  callback = function()
    stop_timer()
    timer = (vim.uv or vim.loop).new_timer()
    timer:start(50, 50, vim.schedule_wrap(tick))
  end,
})

vim.api.nvim_create_autocmd("User", {
  pattern = "SnacksDashboardClosed",
  callback = stop_timer,
})

return {
  {
    "folke/snacks.nvim",
    opts = {
      dashboard = {
        sections = {
          function()
            return { header = frame_str, padding = 2 }
          end,
          { section = "keys", gap = 1, padding = 1 },
          { section = "startup" },
        },
      },
    },
  },
}
