-- Without an explicit fallback, a Python file outside any project -- typically
-- reached by jumping to a definition in site-packages or the stdlib -- resolves
-- to `root_dir = nil`, and Neovim starts a *second* basedpyright plus ruff with
-- their own workspace. Measured 620MB of duplicate basedpyright from exactly
-- this. (The recursive watcher over the CPython stdlib is unrelated: the server
-- registers that itself via an explicit `baseUri`; see lua/config/lsp-watch.lua.)
--
-- Reusing the root of an already-running client makes Neovim reuse the client
-- itself instead (see `:h lsp-root_dir`: a client is reused when name and
-- root_dir match), so the library file gets full LSP from the project's server.
local root_markers = {
  "pyproject.toml",
  "setup.py",
  "setup.cfg",
  "requirements.txt",
  "Pipfile",
  "pyrightconfig.json",
  ".git",
}

-- Paths that must never become a workspace root: rooting a workspace inside a
-- library tree makes the server index and watch the whole thing.
local library_paths = {
  "/site%-packages/",
  "/lib/python%d",
  "/nix/store/",
  "/share/nvim/mason/",
}

local function is_library(path)
  for _, pattern in ipairs(library_paths) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

---@param server string
local function root_dir(server)
  return function(bufnr, on_dir)
    local found = vim.fs.root(bufnr, root_markers)
    if found then
      return on_dir(found)
    end

    for _, client in ipairs(vim.lsp.get_clients({ name = server })) do
      if client.root_dir then
        return on_dir(client.root_dir)
      end
    end

    -- Nothing to reuse. A standalone script can still root at its own
    -- directory, but a library file gets no client rather than a new workspace.
    local path = vim.api.nvim_buf_get_name(bufnr)
    if path == "" or is_library(path) then
      return on_dir(nil)
    end
    return on_dir(vim.fs.dirname(path))
  end
end

return {
  {
    "saghen/blink.cmp",
    opts = {
      sources = {
        providers = {
          lsp = {
            score_offset = 3,
          },
        },
      },
      completion = {
        list = {
          selection = { preselect = true, auto_insert = false },
        },
        accept = {
          auto_brackets = { enabled = true },
          resolve_timeout_ms = 400,
        },
        menu = {
          draw = {
            columns = {
              { "label", "label_description", gap = 1 },
              { "kind_icon", "kind", gap = 1 },
              { "source_name" },
            },
          },
        },
      },
    },
  },
  {
    -- LazyVim never wires blink.cmp's client capabilities into LSP servers, so
    -- they otherwise see only Neovim's defaults
    -- (resolveSupport = additionalTextEdits, command, documentation). blink
    -- advertises a strict superset, adding `detail` and `data`.
    --
    -- This belongs here rather than in blink's own `opts`: `capabilities` is not
    -- a blink config field, and putting it there only produces "Unexpected field
    -- in configuration!" on every startup while being silently discarded.
    -- Passing no arguments returns blink's block alone; Neovim merges its own
    -- defaults underneath at client creation (`vim/lsp/client.lua:437`).
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      local ok, blink = pcall(require, "blink.cmp")
      if not ok then
        return
      end
      opts.servers = opts.servers or {}
      opts.servers["*"] = vim.tbl_deep_extend("force", opts.servers["*"] or {}, {
        capabilities = blink.get_lsp_capabilities(),
      })
    end,
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        basedpyright = {
          root_dir = root_dir("basedpyright"),
          -- Node's default heap limit (4288MB on this machine) is too small for
          -- a torch + transformers dependency chain: the type cache alone runs
          -- 3.1-3.4GB, and at 90% of the limit pyright silently empties the
          -- whole cache and rebuilds it (~15s on the main thread). More heap
          -- also means fewer GC passes, which were costing ~a core on top.
          cmd_env = { NODE_OPTIONS = "--max-old-space-size=6144" },
          capabilities = {
            workspace = {
              didChangeWatchedFiles = {
                dynamicRegistration = true,
              },
            },
          },
          settings = {
            basedpyright = {
              analysis = {
                typeCheckingMode = "basic",
                autoImportCompletions = true,
                diagnosticMode = "openFilesOnly",
                indexing = true,
                autoSearchPaths = true,
                useLibraryCodeForTypes = true,
                diagnosticSeverityOverrides = {
                  reportUnusedImport = "information",
                  reportUnusedFunction = "information",
                  reportUnusedVariable = "information",
                  reportGeneralTypeIssues = "none",
                  reportOptionalMemberAccess = "none",
                  reportOptionalSubscript = "none",
                  reportPrivateImportUsage = "none",
                },
              },
            },
          },
        },
        ruff = {
          root_dir = root_dir("ruff"),
          settings = {
            lint = {
              ignore = { "F401", "F841" },
            },
            organizeImports = true,
          },
        },
      },
    },
  },
}
