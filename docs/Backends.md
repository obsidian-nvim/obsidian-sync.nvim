- [Backend contract](#backend-contract)
- [Registering a backend](#registering-a-backend)
- [Using built-in infra](#using-built-in-infra)
- [Example: git backend](#example-git-backend)

obsidian.nvim's sync module is **pluggable**.  You can write your own backend that implements the `obsidian.sync.Backend` contract and register it via the public API — no forking required.

## Backend contract

```lua
---@class obsidian.sync.Backend
---@field name              string
---@field caps              table<string, boolean>
---@field is_configured     fun(ws: obsidian.Workspace, cache: any?): boolean
---@field start             fun(dir: string, opts?: { silent?: boolean })
---@field pause             fun(dir: string): boolean
---@field sync_once         fun(dir: string, opts?: { silent?: boolean })
---@field setup             fun(ws: obsidian.Workspace)         -- wizard
---@field disconnect        fun(ws: obsidian.Workspace)
---@field log               fun(dir: string)
---@field ws_formatter?     fun(ws: obsidian.Workspace): string
```

Every method is called by obsidian.nvim's dispatch layer (`lua/obsidian/sync/init.lua`).  The dispatch handles triggers, debouncing, and workspace switching — your backend only needs the sync primitives.

| Method | Called when | Must do |
|---|---|---|
| `is_configured(ws)` | Before any sync action | Return `true` if this vault has a remote configured |
| `start(dir)` | Continuous trigger activates | Start a long-running sync (e.g. timer loop) |
| `pause(dir)` | Workspace switch / manual pause | Stop the sync; return `true` if successful |
| `sync_once(dir)` | `:Obsidian sync sync` / `on_write` | Run a one-shot sync to completion |
| `setup(ws)` | `:Obsidian sync setup` | Interactive wizard to configure the remote |
| `disconnect(ws)` | `:Obsidian sync disconnect` | Remove the configuration for this vault |
| `log(dir)` | `:Obsidian sync log` | Show the sync log (can reuse `runner.open_log_buf`) |
| `ws_formatter(ws)` | Workspace picker | Return a formatted label (e.g. `"vault → s3:bucket"`) |

## Registering a backend

```lua
local my_backend = {
  name = "my-backend",
  caps = {},
  is_configured = function(ws) return true end,
  start = function(dir) end,
  pause = function(dir) return true end,
  sync_once = function(dir) end,
  setup = function(ws) end,
  disconnect = function(ws) end,
  log = function(dir) end,
}

require("obsidian.sync").register("my-backend", my_backend)
```

Then in obsidian.nvim config:

```lua
require("obsidian").setup {
  sync = { enabled = true, backend = "my-backend" },
}
```

The dispatcher will call `get_backend()` which returns your registered module.  Put your `register()` call in your plugin's `setup()` — **after** obsidian.nvim is on the runtimepath.

## Using built-in infra

Your backend can reuse obsidian.nvim's existing sync infrastructure:

```lua
-- Async process management
local runner = require "obsidian.sync.runner"
local handler = runner.make_handler(dir)   -- stderr/stdout → log buffer + status
runner.append_log(dir, "message")          -- write to log buffer
runner.open_log_buf(dir)                   -- open log in a buffer
runner.clear_notify_state(dir)             -- reset error dedup

-- Statusline component
local status = require "obsidian.sync.status"
status.set("syncing")  -- sync_icons: synced, syncing, paused, error

-- Picker & confirm dialogs
local picker = require "obsidian.picker"
local api = require "obsidian.api"
api.confirm("Start syncing now?")     -- Yes/No dialog
api.input("Remote path:")            -- text input
vim.fn.inputsecret("Password:")      -- masked input
```

This is exactly what both the built-in `"obsidian"` backend and our `"rclone"` backend do — zero code duplication.

## Example: git backend

A minimal backend that syncs via `git push/pull`:

```lua
local M = { name = "git", caps = {} }

function M.is_configured(ws)
  return vim.fn.isdirectory(tostring(ws.root) .. "/.git") == 1
end

function M.sync_once(dir, opts)
  vim.system({ "git", "-C", dir, "pull", "--rebase" }, {}, function(pull)
    vim.system({ "git", "-C", dir, "push" }, {}, function(push)
      if pull.code == 0 and push.code == 0 then
        vim.notify("Git sync complete")
      end
    end)
  end)
end

function M.start(dir)
  -- continuous: no-op, on_write already triggers sync_once
end

function M.pause(dir)
  return true
end

function M.setup(ws)
  vim.notify("Git backend: ensure the vault is a git repo with a remote.")
end

function M.disconnect(ws)
  vim.notify("Git backend: remove the .git directory to disconnect.")
end

function M.log(dir) end

return M
```
