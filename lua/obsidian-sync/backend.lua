---rclone backend for obsidian.nvim's sync module — WebDAV / S3 / local two-way sync.
---
---Implements the `obsidian.sync.Backend` contract (see
---`lua/obsidian/sync/init.lua` in obsidian.nvim) so it plugs into the
---existing `:Obsidian sync` menu, `on_write` trigger, continuous mode,
---log buffer and statusline component with zero changes to obsidian.nvim.
---
---Wizard supports three flows:
---  1. WebDAV / Nextcloud — enter URL + credentials, rclone remote auto-created
---  2. Existing rclone remote — pick from `rclone listremotes`
---  3. Local folder — two-way sync between two directories (test mode)

local rclone = require "obsidian-sync.rclone"

---@class obsidian-sync.Backend : obsidian.sync.Backend
---@field name string "rclone"
---@field caps table<string,boolean> capability flags
---@field configure fun(cfg: obsidian-sync.Config) apply configuration
---@field persist fun(cfg: obsidian-sync.Config)|nil persist callback set by init.lua
---@field is_configured fun(ws: table):boolean
---@field sync_once fun(dir: string, opts?: table)
---@field start fun(dir: string, opts?: table)
---@field pause fun(dir: string): boolean
---@field log fun(dir: string)
---@field ws_formatter fun(ws: table): string
---@field disconnect fun(ws: table)
---@field setup fun(ws: table)
local M = {
  name = "rclone",
  caps = { remote_catalog = false },
}

-- ── state ────────────────────────────────────────────────────────────────

---@type obsidian-sync.Config
local config = {
  remotes = {},
  check_interval = 300,
  auto_resync = true,
  safe_resync = true,
  notify_events = true,
  progress_win = true,
  trigger = "manual",
  bisync = { exclude = {}, args = {} },
}

---@type table<string, uv.uv_timer_t>
local timers = {}

---@type table<string, vim.SystemObj>
local running = {}

---@type table<string, boolean>
local initialized = {}

-- ── helpers (must be defined before M.configure) ───────────────────────

---Normalise a directory path to its canonical absolute form.
---@param dir string
---@return string
local function norm(dir)
  local real = vim.uv.fs_realpath(tostring(dir))
  if real then
    return real
  end
  return vim.fs.normalize(vim.fn.fnamemodify(tostring(dir), ":p"))
end

---Look up the configured remote for a vault root.
---@param dir string
---@return string|nil
local function remote_for(dir)
  return config.remotes[norm(dir)]
end

---Post a plugin-scoped notification.
---@param msg string
---@param level? integer vim.log.levels
local function notify(msg, level)
  vim.notify("[obsidian-sync] " .. msg, level or vim.log.levels.INFO)
end

---Apply user config, normalising remote keys.
---@param cfg obsidian-sync.Config
function M.configure(cfg)
  config = vim.tbl_deep_extend("force", config, cfg or {})
  -- Normalise remote keys so lookups match regardless of path representation.
  if cfg.remotes then
    local normalized = {}
    for root, remote in pairs(config.remotes) do
      normalized[norm(root)] = remote
    end
    config.remotes = normalized
  end
end

---Cross-platform rclone binary detection.
---@return string|nil
local function rclone_bin()
  local bin = vim.fn.exepath "rclone"
  if bin and bin ~= "" then
    return bin
  end
  -- Windows: check common install paths
  if vim.fn.has "win32" == 1 then
    for _, p in ipairs { "C:\\rclone\\rclone.exe", vim.fn.expand "~/rclone/rclone.exe" } do
      ---@diagnostic disable-next-line: param-type-mismatch
      if vim.fn.executable(p) == 1 then
        return p
      end
    end
  end
  return nil
end

-- ── backend contract ─────────────────────────────────────────────────────

---Check if a workspace has a remote configured.
---@param ws obsidian.Workspace
---@return boolean
function M.is_configured(ws)
  return remote_for(tostring(ws.root)) ~= nil
end

---Run a single bisync for a vault.
---@param dir string vault root
---@param opts? { silent?: boolean }
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
    -- Skip silently: on_write debounce beats the 15s bisync window; the
    -- running sync already includes the latest changes.
    return
  end

  -- Notify sync start (appears in Noice / statusline)
  local vault_name = vim.fn.fnamemodify(cwd, ":t")
  if config.notify_events ~= false then
    notify(string.format("Syncing %s...", vault_name))
  end

  local runner = require "obsidian.sync.runner"
  local status_mod = require "obsidian.sync.status"
  local ui
  if config.progress_win ~= false then
    ui = require "obsidian-sync.ui"
  end

  -- Bypass the paused→syncing HACK in obsidian.nvim's status module.
  -- It blocks the transition, so the icon stays "paused" forever.
  if status_mod.state.kind == "paused" then
    status_mod.state.kind = "syncing"
    status_mod.state.icon = "󰑓"
    status_mod.state.need_update = true
  end

  -- Open floating progress window
  if ui and not opts.silent then
    ui.progress_win(cwd, string.format("Syncing %s...", vault_name), "comparing files...")
  end

  local handler = runner.make_handler(cwd)
  local args = rclone.bisync_args(cwd, remote, config.bisync)
  local resynced = false

  local on_exit = function(out)
    running[cwd] = nil
    if out.code == 0 then
      initialized[cwd] = true
      runner.append_log(cwd, "Fully synced")
      if config.notify_events ~= false then
        vim.schedule(function()
          notify(string.format("%s synced", vault_name))
        end)
      end
      if ui then
        vim.schedule(function()
          ui.close_progress(cwd, "synced")
        end)
      end
      return
    end

    if config.auto_resync and not initialized[cwd] and not resynced then
      resynced = true
      if config.safe_resync then
        runner.append_log(cwd, "Initial bisync requires --resync (one-time alignment). Running now...")
      else
        runner.append_log(cwd, "Initial bisync failed; retrying with --resync", { error = true })
      end
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
    if ui then
      vim.schedule(function()
        ui.close_progress(cwd, "error")
      end)
    end
  end

  running[cwd] = rclone.run_async(args, { cwd = cwd, handler = handler }, on_exit)
end

---Start continuous sync (runs sync_once immediately, then on a timer).
---@param dir string vault root
---@param opts? { silent?: boolean }
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

---Pause sync for a vault (stop timer, kill running process).
---@param dir string vault root
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

---Open the sync log buffer for a vault.
---@param dir string vault root
function M.log(dir)
  require("obsidian.sync.runner").open_log_buf(norm(dir))
end

---Format a workspace for display in the sync menu.
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

---Unlink a workspace from sync (pause + remove mapping).
---@param ws obsidian.Workspace
function M.disconnect(ws)
  local dir = norm(tostring(ws.root))
  M.pause(dir)
  config.remotes[dir] = nil
  if M.persist then
    M.persist(config)
  end
  notify(string.format("Unlinked %s from sync", ws.name))
end

-- ── wizard: link helper ──────────────────────────────────────────────────

---Persist a new vault→remote mapping and optionally start syncing.
---@param ws obsidian.Workspace
---@param dir string normalised vault root
---@param target string rclone remote target
local function link(ws, dir, target)
  config.remotes[dir] = target
  if M.persist then
    M.persist(config)
  end
  notify(string.format("Linked %s <-> %s", ws.name, target))
  local api = require "obsidian.api"
  if api.confirm "Start syncing now?" == "Yes" then
    M.sync_once(dir)
  end
end

-- ── wizard: WebDAV / Nextcloud (no manual rclone config) ─────────────────

---Create an rclone remote programmatically (cross-platform safe).
---@param name string remote name
---@param kv table<string,string> key=value pairs
---@return boolean success
local function rclone_config_create(name, kv)
  local bin = rclone_bin()
  if not bin then
    return false
  end

  local args = { "config", "create", name, "webdav", "--non-interactive" }
  for k, v in pairs(kv) do
    table.insert(args, k .. "=" .. v)
  end
  table.insert(args, "--obscure")

  local obj = vim.system({ bin, unpack(args) }, { text = true }):wait()
  return obj and obj.code == 0
end

---Detect Nextcloud vendor by URL pattern.
---@param url string
---@return "nextcloud"|"owncloud"|"other"
local function detect_vendor(url)
  if url:find "remote.php" or url:find "nextcloud" then
    return "nextcloud"
  elseif url:find "owncloud" then
    return "owncloud"
  end
  return "other"
end

---WebDAV / Nextcloud setup wizard flow.
---@param ws obsidian.Workspace
---@param dir string normalised vault root
local function webdav_flow(ws, dir)
  local api = require "obsidian.api"

  local vendor_items = { "Nextcloud / ownCloud", "Generic WebDAV" }
  local picker = require "obsidian.picker"
  picker.select(vendor_items, {
    prompt = "Select WebDAV server type",
    format_item = function(v)
      return v
    end,
  }, function(choices)
    if not choices[1] then
      return
    end
    local is_nextcloud = choices[1] == vendor_items[1]

    local url = api.input "WebDAV URL (e.g. https://example.com/remote.php/dav/files/user/): "
    if not url or url == "" then
      notify("Setup cancelled", vim.log.levels.WARN)
      return
    end

    local user = api.input "Username: "
    if not user or user == "" then
      return
    end

    local pass = vim.fn.inputsecret "Password: "
    if not pass or pass == "" then
      notify("Password required for WebDAV", vim.log.levels.WARN)
      return
    end

    local vendor = is_nextcloud and detect_vendor(url) or "other"
    local remote_name = "obsidian-sync-" .. tostring(ws.name):gsub("[^%w]", "-"):lower()

    notify("Creating rclone remote '" .. remote_name .. "' ...")

    local ok = rclone_config_create(remote_name, {
      url = url,
      vendor = vendor,
      user = user,
      pass = pass,
    })

    if not ok then
      notify(
        "Failed to create rclone remote. Check URL and credentials, or run `:Obsidian sync setup` -> 'Existing rclone remote'.",
        vim.log.levels.ERROR
      )
      return
    end

    notify("Remote '" .. remote_name .. "' created.")

    -- Ask for optional sub-path (e.g. vault folder inside WebDAV root)
    local sub = api.input "Remote sub-path (e.g. vault/main, <CR> for root): "
    sub = (sub or ""):gsub("^/+", ""):gsub("/+$", "")
    local target = remote_name .. ":"
    if sub ~= "" then
      target = target .. sub
    end

    link(ws, dir, target)
  end)
end

-- ── wizard: other flows ──────────────────────────────────────────────────

---Prompt for a remote sub-path and link.
---@param ws obsidian.Workspace
---@param dir string normalised vault root
---@param remote string rclone remote name (with colon)
local function prompt_path(ws, dir, remote)
  local api = require "obsidian.api"
  local sub = api.input "Remote path (e.g. vault/main, <CR> for root): "
  sub = (sub or ""):gsub("^/+", ""):gsub("/+$", "")
  local target = remote
  if sub ~= "" then
    target = remote .. sub
  end
  link(ws, dir, target)
end

---Open a terminal buffer running `rclone config`.
---@param ws obsidian.Workspace
---@param _dir string (unused — ws.root is sufficient)
local function run_rclone_config(ws, _dir)
  vim.cmd "tabnew | terminal rclone config"
  vim.api.nvim_create_autocmd("TermClose", {
    once = true,
    callback = function()
      M.setup(ws)
    end,
  })
end

---Existing rclone remote picker flow.
---@param ws obsidian.Workspace
---@param dir string normalised vault root
local function existing_flow(ws, dir)
  local picker = require "obsidian.picker"
  local api = require "obsidian.api"

  local remotes = rclone.listremotes()
  if not remotes then
    vim.notify("[obsidian-sync] `rclone listremotes` failed. Is rclone installed and configured?", vim.log.levels.ERROR)
    return
  end

  if #remotes == 0 then
    if api.confirm "No rclone remotes found. Run `rclone config` now?" == "Yes" then
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
    if choices[1] then
      prompt_path(ws, dir, choices[1])
    end
  end)
end

---Local folder sync setup flow.
---@param ws obsidian.Workspace
---@param dir string normalised vault root
local function local_flow(ws, dir)
  local api = require "obsidian.api"
  local p = api.input "Local folder to two-way sync with (absolute path): "
  if not p or p == "" then
    return
  end
  ---@diagnostic disable-next-line: param-type-mismatch
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

-- ── wizard: main entry ───────────────────────────────────────────────────

---Open the setup wizard for a workspace.
---@param ws obsidian.Workspace
function M.setup(ws)
  local dir = norm(tostring(ws.root))
  local picker = require "obsidian.picker"

  local WEBDAV = "WebDAV / Nextcloud (connect directly)"
  local EXISTING = "Use an existing rclone remote"
  local RCLONE_CFG = "Run rclone config to add a new remote"
  local LOCAL = "Sync with a local folder (two-way)"

  picker.select({ WEBDAV, EXISTING, RCLONE_CFG, LOCAL }, {
    prompt = "Configure rclone sync for " .. tostring(ws.name),
    format_item = function(item)
      return item
    end,
  }, function(choices)
    local choice = choices[1]
    if not choice then
      return
    end
    if choice == WEBDAV then
      webdav_flow(ws, dir)
    elseif choice == EXISTING then
      existing_flow(ws, dir)
    elseif choice == RCLONE_CFG then
      run_rclone_config(ws, dir)
    else
      local_flow(ws, dir)
    end
  end)
end

-- ── cleanup ──────────────────────────────────────────────────────────────

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
