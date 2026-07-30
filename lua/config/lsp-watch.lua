-- Hardened backend for LSP `workspace/didChangeWatchedFiles`.
--
-- Verified against Neovim 0.12.4. Three problems with the stock inotify backend
-- (`$VIMRUNTIME/lua/vim/_watch.lua`) that this replaces:
--
--  1. It watches the workspace recursively excluding only `.git`
--     (`_watch.lua:300`). In this project `.venv` alone is 793 of 1031
--     directories: 893 inotify descriptors, versus 98 with the exclusions below.
--  2. Its `node_modules` filter runs in Lua on the main loop *after* every event
--     has crossed the pipe (`_watchfiles.lua:81-83`, applied at :187). Excluding
--     at the inotifywait level means those events are never generated.
--  3. `vim.system()` is called with no `on_exit` handler, and cancelling is just
--     `obj:kill(2)` (`_watch.lua:326-334`). If inotifywait dies -- inotify
--     instance limit, OOM kill, a stray pkill -- watching stops permanently and
--     silently. That is worse than not having it, because you keep believing
--     your files are watched. `:LspWatchStatus` and auto-restart fix that.
--
-- basedpyright registers `globPattern = "**"` with no `baseUri`: it asks about
-- everything in the workspace and has no specific interest in `.venv`, it just
-- inherits it because `.venv` sits inside the root. So that package installs
-- stay visible despite the tree being excluded, a second *non-recursive* watch
-- is placed on site-packages -- one descriptor, and it still reports
-- `CREATE,ISDIR` / `DELETE,ISDIR` when a package appears or is removed.
--
-- `vim.lsp._watchfiles` is a private API. Installation is feature-detected and
-- wrapped in pcall: if a field disappears after a Neovim upgrade the stock
-- backend is left alone, so the worst case is current behaviour, never broken
-- LSP. `_poll_exclude_pattern` is deliberately NOT touched -- excluding at the
-- source makes it redundant, and adding `.venv` there would filter out the very
-- site-packages events collected above.

local M = {}

-- Directories not worth watching recursively. Order does not matter.
M.exclude_dirs = {
  ".git",
  ".venv",
  "venv",
  ".direnv",
  "__pycache__",
  "node_modules",
  ".mypy_cache",
  ".pytest_cache",
  ".ruff_cache",
  ".tox",
  ".nox",
  "target",
  "dist",
  "build",
  ".next",
}

-- Virtualenv directory names probed for a site-packages to keep watching.
M.venv_dirs = { ".venv", "venv", ".env" }

-- Watch roots that get one non-recursive watch instead of a recursive sweep.
-- basedpyright registers a second watcher over its resolved interpreter path
-- (`{ baseUri = ".../lib/python3.13", pattern = "**" }`), which cost 166
-- descriptors for a tree that only changes when Python itself is upgraded. A
-- shallow watch still reports top-level modules appearing or vanishing.
M.shallow_roots = {
  "/lib/python%d",
  "/site%-packages$",
  "/nix/store/",
  "/share/nvim/mason/",
}

local function is_shallow(path)
  for _, pattern in ipairs(M.shallow_roots) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

M.restart = {
  base_ms = 1000, -- first retry delay; doubles each consecutive failure
  max_ms = 30000,
  max_attempts = 5, -- consecutive failures before giving up
  healthy_ms = 60000, -- run at least this long to reset the failure count
}

local FileChangeType = (vim._watch and vim._watch.FileChangeType)
  or { Created = 1, Changed = 2, Deleted = 3 }

local EVENTS = {
  CREATE = FileChangeType.Created,
  DELETE = FileChangeType.Deleted,
  MODIFY = FileChangeType.Changed,
  MOVED_FROM = FileChangeType.Deleted,
  MOVED_TO = FileChangeType.Created,
}

-- Live supervisors, for :LspWatchStatus.
---@type table<table, true>
local supervisors = setmetatable({}, { __mode = "k" })

--- POSIX ERE handed to `--exclude`. Only the *last* `--exclude` is honoured by
--- inotifywait, so every alternative goes in one pattern. Note this filters
--- events only; `@path` below is what actually prevents a watch being set.
local function exclude_regex()
  local alts = {}
  for _, dir in ipairs(M.exclude_dirs) do
    alts[#alts + 1] = dir:gsub("%.", "\\.")
  end
  return "(^|/)(" .. table.concat(alts, "|") .. ")(/|$)|\\.py[co]$"
end

--- Same semantics as the local `skip()` in `_watch.lua:37`.
local function skip(path, opts)
  if not opts then
    return false
  end
  if opts.include_pattern and opts.include_pattern:match(path) == nil then
    return true
  end
  if opts.exclude_pattern and opts.exclude_pattern:match(path) ~= nil then
    return true
  end
  return false
end

--- inotifywait reports directory events as `CREATE,ISDIR`. The stock backend
--- compares the whole field and so drops them; the site-packages watch depends
--- on them, so each comma-separated flag is checked.
local function classify(event)
  for flag in vim.gsplit(event or "", ",", { plain = true, trimempty = true }) do
    if EVENTS[flag] then
      return EVENTS[flag]
    end
  end
end

local function on_output(line, opts, callback)
  local d = vim.split(line, "%s+")
  local dir, event, file = d[1], d[2], d[#d]
  if not dir or not event then
    return
  end
  local fullpath = vim.fs.joinpath(dir, file or "")
  if skip(fullpath, opts) then
    return
  end
  local change = classify(event)
  if change then
    callback(fullpath, change)
  end
end

--- Run `argv` and keep it running: restart with exponential backoff if it exits
--- unexpectedly, and surface stderr instead of degrading quietly.
---@param argv string[]
---@param label string
---@param on_line fun(line: string)
---@return fun() cancel
local function supervise(argv, label, on_line)
  local state = { stopped = false, attempt = 0, alive = false, label = label, path = argv[#argv] }
  supervisors[state] = true

  local function notify(msg, level)
    vim.schedule(function()
      vim.notify(("lsp-watch [%s]: %s"):format(label, msg), level)
    end)
  end

  local start
  start = function()
    if state.stopped then
      return
    end
    local started_at = vim.uv.now()
    state.alive = true
    state.obj = vim.system(argv, {
      -- --latency is locale dependent but tostring() always uses '.'
      env = { LC_NUMERIC = "C" },
      stderr = function(err, data)
        if err or not data or #vim.trim(data) == 0 then
          return
        end
        local msg = vim.trim(data)
        if vim.startswith(msg, "Failed to watch") then
          msg = "inotify(7) limit reached, see :h inotify-limitations"
        end
        notify(msg, vim.log.levels.ERROR)
      end,
      stdout = function(err, data)
        if err or not data then
          return
        end
        for line in vim.gsplit(data, "\n", { plain = true, trimempty = true }) do
          on_line(line)
        end
      end,
    }, function(res)
      state.alive = false
      if state.stopped then
        return
      end
      if vim.uv.now() - started_at >= M.restart.healthy_ms then
        state.attempt = 0
      end
      state.attempt = state.attempt + 1
      if state.attempt > M.restart.max_attempts then
        notify(
          ("exited %d times in a row; not restarting. Run :LspWatchResync to retry."):format(
            state.attempt - 1
          ),
          vim.log.levels.ERROR
        )
        return
      end
      local delay = math.min(M.restart.base_ms * 2 ^ (state.attempt - 1), M.restart.max_ms)
      notify(
        ("watcher exited (code %s); restarting in %dms"):format(tostring(res.code), delay),
        vim.log.levels.WARN
      )
      vim.schedule(function()
        vim.defer_fn(start, delay)
      end)
    end)
  end

  start()

  return function()
    state.stopped = true
    supervisors[state] = nil
    if state.obj then
      pcall(function()
        state.obj:kill(2)
      end)
    end
  end
end

--- site-packages directories inside `root`'s virtualenv, if any.
local function site_packages(root)
  local found = {}
  for _, venv in ipairs(M.venv_dirs) do
    local lib = vim.fs.joinpath(root, venv, "lib")
    local st = vim.uv.fs_stat(lib)
    if st and st.type == "directory" then
      for name, kind in vim.fs.dir(lib) do
        if kind == "directory" and name:match("^python") then
          local sp = vim.fs.joinpath(lib, name, "site-packages")
          if vim.uv.fs_stat(sp) then
            found[#found + 1] = sp
          end
        end
      end
    end
  end
  return found
end

--- Drop-in replacement for `vim.lsp._watchfiles._watchfunc`.
---@param path string
---@param opts table?
---@param callback fun(path: string, change: integer)
---@return fun() cancel
function M.watchfunc(path, opts, callback)
  local shallow = is_shallow(path)

  local argv = {
    "inotifywait",
    "--quiet",
    "--no-dereference",
    "--monitor",
    "--event",
    "create",
    "--event",
    "delete",
    "--event",
    "modify",
    "--event",
    "move",
  }

  if not shallow then
    argv[#argv + 1] = "--recursive"
    argv[#argv + 1] = "--exclude"
    argv[#argv + 1] = exclude_regex()

    -- `@path` prevents the watch being established at all, which is what saves
    -- the descriptors; the regex above only filters events already read.
    for _, dir in ipairs(M.exclude_dirs) do
      local p = vim.fs.joinpath(path, dir)
      if vim.uv.fs_stat(p) then
        argv[#argv + 1] = "@" .. p
      end
    end
  end

  argv[#argv + 1] = path

  local cancels = {
    supervise(argv, vim.fs.basename(path), function(line)
      on_output(line, opts, callback)
    end),
  }

  -- One extra descriptor each, so `uv add`/`pip install` is still reported even
  -- though the venv tree itself is excluded above.
  for _, sp in ipairs(site_packages(path)) do
    cancels[#cancels + 1] = supervise({
      "inotifywait",
      "--quiet",
      "--no-dereference",
      "--monitor",
      "--event",
      "create",
      "--event",
      "delete",
      "--event",
      "move",
      sp,
    }, "site-packages", function(line)
      on_output(line, opts, callback)
    end)
  end

  return function()
    for _, cancel in ipairs(cancels) do
      cancel()
    end
  end
end

--- Swap in the backend. Returns false plus a reason if anything is missing, in
--- which case the stock backend is left untouched.
---@return boolean ok, string? reason
function M.setup()
  if vim.fn.has("linux") ~= 1 then
    return false, "not Linux; stock backend is appropriate"
  end
  if vim.fn.executable("inotifywait") ~= 1 then
    return false, "inotifywait not found (install inotify-tools)"
  end
  local ok, watchfiles = pcall(require, "vim.lsp._watchfiles")
  if not ok or type(watchfiles) ~= "table" or type(watchfiles._watchfunc) ~= "function" then
    return false, "vim.lsp._watchfiles._watchfunc missing (Neovim internals changed)"
  end
  if not (vim._watch and vim._watch.FileChangeType) then
    return false, "vim._watch.FileChangeType missing (Neovim internals changed)"
  end

  M._stock_watchfunc = watchfiles._watchfunc
  watchfiles._watchfunc = M.watchfunc

  vim.api.nvim_create_user_command("LspWatchStatus", function()
    local lines = {}
    for state in pairs(supervisors) do
      lines[#lines + 1] = ("%s  %s  %s"):format(
        state.alive and "alive" or "DEAD ",
        state.label,
        state.path
      )
    end
    table.sort(lines)
    if #lines == 0 then
      lines[1] = "no file watchers running"
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end, { desc = "Show LSP file watchers and whether they are alive" })

  vim.api.nvim_create_user_command("LspWatchResync", function()
    local clients = vim.lsp.get_clients()
    if #clients == 0 then
      vim.notify("lsp-watch: no active clients", vim.log.levels.WARN)
      return
    end
    local names = {}
    for _, client in ipairs(clients) do
      names[#names + 1] = client.name
      client:stop()
    end
    vim.defer_fn(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == "" then
          vim.api.nvim_exec_autocmds("FileType", { buffer = buf, modeline = false })
        end
      end
      vim.notify("lsp-watch: restarted " .. table.concat(names, ", "), vim.log.levels.INFO)
    end, 500)
  end, { desc = "Restart LSP clients and re-register their file watchers" })

  return true
end

return M
