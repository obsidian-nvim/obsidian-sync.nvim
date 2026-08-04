--- rclone backend for obsidian.nvim's sync module.
---
--- Implements the `obsidian.sync.Backend` contract (see
--- `lua/obsidian/sync/init.lua` in obsidian.nvim) so it plugs into the
--- existing `:Obsidian sync` menu, `on_write` trigger, continuous mode,
--- log buffer and statusline component with zero changes to obsidian.nvim.
---
--- Configuration is set by `require("obsidian-sync").setup()` through
--- `M.setup(cfg)`; `cfg.remotes` maps a vault root to an rclone target
--- (e.g. "mys3:vault/main" or an absolute local path).

local rclone = require "obsidian-sync.rclone"

local M = {
  name = "rclone",
  caps = { remote_catalog = false },
}

---@type { remotes: table<string,string>, check_interval: integer, auto_resync: boolean, bisync: { exclude: string[], args: string[] }, persist: (fun(cfg: any)|nil) }
local config = {
  remotes = {},
  check_interval = 300,
  auto_resync = true,
  bisync = { exclude = {}, args = {} },
  persist = nil,
}

---@type table<string, uv.uv_timer_t>
local timers = {}

---@type table<string, vim.SystemObj>
local running = {}

---@type table<string, boolean>
local initialized = {}

---Set plugin config (called by `obsidian-sync.setup()`).
---This is NOT the Backend wizard — that one is `M.setup(ws)` below,
---so it is named `configure` to avoid the definition being overwritten.
---@param cfg any
function M.configure(cfg)
  config = vim.tbl_deep_extend("force", config, cfg or {})
end

local function norm(dir)
  return vim.uv.fs_realpath(tostring(dir)) or vim.fs.normalize(vim.fn.fnamemodify(tostring(dir), ":p"))
end

---@param dir string
---@return string?
local function remote_for(dir)
  return config.remotes[norm(dir)]
end

---@param msg string
local function notify(msg)
  vim.notify("[obsidian-sync] " .. msg, vim.log.levels.INFO)
end

---@param ws obsidian.Workspace
---@return boolean
function M.is_configured(ws)
  return remote_for(tostring(ws.root)) ~= nil
end

---@param dir string
---@param opts { silent?: boolean }?
function M.sync_once(dir, opts)
  opts = opts or {}
  local cwd = norm(dir)
  local remote = remote_for(dir)
  if not remote then
    if not opts.silent then
      notify(string.format("No remote configured for %s (run `:Obsidian sync setup`)", dir))
    end
    return
  end

  if running[cwd] then
    if not opts.silent then
      notify(string.format("Sync already running for %s", dir))
    end
    return
  end

  local runner = require "obsidian.sync.runner"
  local handler = runner.make_handler(cwd)
  local args = rclone.bisync_args(cwd, remote, config.bisync)
  local resynced = false

  local on_exit
  on_exit = function(out)
    running[cwd] = nil
    if out.code == 0 then
      initialized[cwd] = true
      runner.append_log(cwd, "Fully synced")
      return
    end

    -- bisync refuses to run after a stale lock / interrupted state and asks
    -- for --resync; retry once automatically, like the Obsidian app's
    -- "resync" does. Only ever done once per vault (until a clean sync).
    if config.auto_resync and not initialized[cwd] and not resynced then
      resynced = true
      runner.append_log(cwd, "Initial bisync failed; retrying with --resync", { error = true })
      local retry = vim.list_extend({}, args)
      vim.list_extend(retry, { "--resync" })
      running[cwd] = rclone.run_async(retry, { cwd = cwd, handler = handler }, on_exit)
      return
    end

    runner.append_log(
      cwd,
      string.format("rclone bisync exited with code %s: %s", out.code, vim.trim(out.stderr or "")),
      { error = true }
    )
  end

  running[cwd] = rclone.run_async(args, { cwd = cwd, handler = handler }, on_exit)
end

---Continuous mode: run a one-shot bisync now, then every `check_interval`.
---@param dir string
---@param opts { silent?: boolean }?
function M.start(dir, opts)
  opts = opts or {}
  local cwd = norm(dir)

  if timers[cwd] then
    if not opts.silent then
      notify(string.format("Sync already running for %s", dir))
    end
    return
  end

  M.sync_once(cwd, { silent = opts.silent })

  local interval_ms = math.max(10, config.check_interval) * 1000
  local t = assert(vim.uv.new_timer(), "failed to spawn timer")
  timers[cwd] = t
  t:start(
    interval_ms,
    interval_ms,
    vim.schedule_wrap(function()
      M.sync_once(cwd, { silent = true })
    end)
  )
end

---@param dir string
---@return boolean
function M.pause(dir)
  local cwd = norm(dir)

  local t = timers[cwd]
  if t then
    pcall(function()
      t:stop()
      t:close()
    end)
    timers[cwd] = nil
  end

  local proc = running[cwd]
  if proc then
    pcall(function()
      proc:kill(15)
    end)
  end

  local runner = require "obsidian.sync.runner"
  runner.clear_notify_state(cwd)
  require("obsidian.sync.status").set "paused"
  return true
end

---@param dir string
function M.log(dir)
  local runner = require "obsidian.sync.runner"
  runner.open_log_buf(norm(dir))
end

----------------
--- Wizard ---
----------------

local function link(ws, dir, target)
  config.remotes[dir] = target
  if config.persist then
    config.persist(config)
  end
  notify(string.format("Linked %s <-> %s", ws.name, target))
  local api = require "obsidian.api"
  if api.confirm("Start syncing now?") == "Yes" then
    M.sync_once(dir)
  end
end

---@param ws obsidian.Workspace
---@param dir string
local function prompt_path(ws, dir, remote)
  local api = require "obsidian.api"
  local sub = api.input("Remote path (e.g. vault/main, <CR> for root): ")
  sub = (sub or ""):gsub("^/+", ""):gsub("/+$", "")
  local target = remote
  if sub ~= "" then
    target = remote .. sub
  end
  link(ws, dir, target)
end

---@param ws obsidian.Workspace
---@param dir string
local function run_rclone_config(ws, dir)
  vim.cmd "tabnew | terminal rclone config"
  vim.api.nvim_create_autocmd("TermClose", {
    once = true,
    callback = function()
      M.setup(ws)
    end,
  })
end

---@param ws obsidian.Workspace
---@param dir string
local function existing_flow(ws, dir)
  local picker = require "obsidian.picker"
  local api = require "obsidian.api"

  local remotes = rclone.listremotes()
  if not remotes then
    vim.notify("[obsidian-sync] `rclone listremotes` failed. Is rclone installed and configured?", vim.log.levels.ERROR)
    return
  end

  if #remotes == 0 then
    if api.confirm("No rclone remotes found. Run `rclone config` now?") == "Yes" then
      run_rclone_config(ws, dir)
    end
    return
  end

  picker.select(remotes, {
    prompt = "Select rclone remote",
    format_item = function(r)
      return r
    end,
  }, function(choices)
    local remote = choices[1]
    if remote then
      prompt_path(ws, dir, remote)
    end
  end)
end

---@param ws obsidian.Workspace
---@param dir string
local function local_flow(ws, dir)
  local api = require "obsidian.api"
  local p = api.input "Local folder to two-way sync with (absolute path): "
  if not p or p == "" then
    return
  end
  p = vim.fn.simplify(vim.fn.expand(p))
  if vim.fn.isdirectory(p) == 0 then
    if api.confirm("Folder does not exist: " .. p .. ". Create it?") == "Yes" then
      vim.fn.mkdir(p, "p")
    else
      return
    end
  end
  link(ws, dir, p)
end

---@param ws obsidian.Workspace
function M.setup(ws)
  local dir = norm(tostring(ws.root))
  local picker = require "obsidian.picker"

  local USE_EXISTING = "Use an existing rclone remote"
  local ADD_NEW = "Add a new remote (rclone config)"
  local LOCAL_FOLDER = "Sync with a local folder (two-way)"

  picker.select({ USE_EXISTING, ADD_NEW, LOCAL_FOLDER }, {
    prompt = "Configure rclone sync for " .. tostring(ws.name),
    format_item = function(item)
      return item
    end,
  }, function(choices)
    local choice = choices[1]
    if not choice then
      return
    end
    if choice == USE_EXISTING then
      existing_flow(ws, dir)
    elseif choice == ADD_NEW then
      run_rclone_config(ws, dir)
    else
      local_flow(ws, dir)
    end
  end)
end

---@param ws obsidian.Workspace
function M.disconnect(ws)
  local dir = norm(tostring(ws.root))
  M.pause(dir)
  config.remotes[dir] = nil
  if config.persist then
    config.persist(config)
  end
  notify(string.format("Unlinked %s from sync", ws.name))
end

---@param ws obsidian.Workspace
---@return string
function M.ws_formatter(ws)
  local root = tostring(ws.root)
  local remote = remote_for(root)
  if remote then
    return string.format("%s (%s) -> %s", ws.name, root, remote)
  end
  return string.format("%s (%s)", ws.name, root)
end

---Cleanup all timers on exit.
vim.api.nvim_create_autocmd("VimLeavePre", {
  once = true,
  callback = function()
    for _, t in pairs(timers) do
      pcall(function()
        t:stop()
        t:close()
      end)
    end
  end,
})

return M
