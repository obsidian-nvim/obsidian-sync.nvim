--- rclone backend for obsidian.nvim's sync module — WebDAV / S3 / local two-way sync.
---
--- Implements the `obsidian.sync.Backend` contract (see
--- `lua/obsidian/sync/init.lua` in obsidian.nvim) so it plugs into the
--- existing `:Obsidian sync` menu, `on_write` trigger, continuous mode,
--- log buffer and statusline component with zero changes to obsidian.nvim.
---
--- Wizard supports three flows:
---   1. WebDAV / Nextcloud — enter URL + credentials, rclone remote auto-created
---   2. Existing rclone remote — pick from `rclone listremotes`
---   3. Local folder — two-way sync between two directories (test mode)

local rclone = require "obsidian-sync.rclone"

local M = {
  name = "rclone",
  caps = { remote_catalog = false },
}

-- ── state ────────────────────────────────────────────────────────────────

---@type { remotes: table<string,string>, check_interval: integer, auto_resync: boolean, safe_resync: boolean, bisync: { exclude: string[], args: string[] }, persist: (fun(cfg: any)|nil) }
local config = {
  remotes = {},
  check_interval = 300,
  auto_resync = true,
  safe_resync = true, -- warn before --resync (disables auto-retry warning)
  bisync = { exclude = {}, args = {} },
  persist = nil,
}

---@type table<string, uv.uv_timer_t>
local timers = {}

---@type table<string, vim.SystemObj>
local running = {}

---@type table<string, boolean>
local initialized = {}

function M.configure(cfg)
  config = vim.tbl_deep_extend("force", config, cfg or {})
end

-- ── helpers ──────────────────────────────────────────────────────────────

local function norm(dir)
  return vim.uv.fs_realpath(tostring(dir)) or vim.fs.normalize(vim.fn.fnamemodify(tostring(dir), ":p"))
end

local function remote_for(dir)
  return config.remotes[norm(dir)]
end

local function notify(msg, level)
  vim.notify("[obsidian-sync] " .. msg, level or vim.log.levels.INFO)
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
      if vim.fn.executable(p) == 1 then
        return p
      end
    end
  end
  return nil
end

local function has_rclone()
  if rclone.bin ~= "rclone" and rclone.bin ~= "" then
    return true
  end
  return rclone_bin() ~= nil
end

-- ── backend contract ─────────────────────────────────────────────────────

function M.is_configured(ws)
  return remote_for(tostring(ws.root)) ~= nil
end

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
  end

  running[cwd] = rclone.run_async(args, { cwd = cwd, handler = handler }, on_exit)
end

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
  t:start(interval_ms, interval_ms, vim.schedule_wrap(function()
    M.sync_once(cwd, { silent = true })
  end))
end

function M.pause(dir)
  local cwd = norm(dir)

  local t = timers[cwd]
  if t then
    pcall(function() t:stop(); t:close() end)
    timers[cwd] = nil
  end

  local proc = running[cwd]
  if proc then
    pcall(function() proc:kill(15) end)
  end

  local runner = require "obsidian.sync.runner"
  runner.clear_notify_state(cwd)
  require("obsidian.sync.status").set "paused"
  return true
end

function M.log(dir)
  require("obsidian.sync.runner").open_log_buf(norm(dir))
end

function M.ws_formatter(ws)
  local root = tostring(ws.root)
  local remote = remote_for(root)
  if remote then
    return string.format("%s (%s) -> %s", ws.name, root, remote)
  end
  return string.format("%s (%s)", ws.name, root)
end

function M.disconnect(ws)
  local dir = norm(tostring(ws.root))
  M.pause(dir)
  config.remotes[dir] = nil
  if config.persist then
    config.persist(config)
  end
  notify(string.format("Unlinked %s from sync", ws.name))
end

-- ── wizard: link helper ──────────────────────────────────────────────────

local function link(ws, dir, target)
  config.remotes[dir] = target
  if config.persist then
    config.persist(config)
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
  if not bin then return false end

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
---@return string "nextcloud"|"owncloud"|"other"
local function detect_vendor(url)
  if url:find "remote.php" or url:find "nextcloud" then
    return "nextcloud"
  elseif url:find "owncloud" then
    return "owncloud"
  end
  return "other"
end

---@param ws obsidian.Workspace
---@param dir string
local function webdav_flow(ws, dir)
  local api = require "obsidian.api"

  local vendor_items = { "Nextcloud / ownCloud", "Generic WebDAV" }
  local picker = require "obsidian.picker"
  picker.select(vendor_items, {
    prompt = "Select WebDAV server type",
    format_item = function(v) return v end,
  }, function(choices)
    if not choices[1] then return end
    local is_nextcloud = choices[1] == vendor_items[1]

    local url = api.input "WebDAV URL (e.g. https://example.com/remote.php/dav/files/user/): "
    if not url or url == "" then
      notify("Setup cancelled", vim.log.levels.WARN)
      return
    end

    local user = api.input "Username: "
    if not user or user == "" then return end

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
    local sub = api.input("Remote sub-path (e.g. vault/main, <CR> for root): ")
    sub = (sub or ""):gsub("^/+", ""):gsub("/+$", "")
    local target = remote_name .. ":"
    if sub ~= "" then target = target .. sub end

    link(ws, dir, target)
  end)
end

-- ── wizard: other flows ──────────────────────────────────────────────────

local function prompt_path(ws, dir, remote)
  local api = require "obsidian.api"
  local sub = api.input("Remote path (e.g. vault/main, <CR> for root): ")
  sub = (sub or ""):gsub("^/+", ""):gsub("/+$", "")
  local target = remote
  if sub ~= "" then target = remote .. sub end
  link(ws, dir, target)
end

local function run_rclone_config(ws, dir)
  vim.cmd "tabnew | terminal rclone config"
  vim.api.nvim_create_autocmd("TermClose", {
    once = true,
    callback = function()
      M.setup(ws)
    end,
  })
end

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
    format_item = function(r) return r end,
  }, function(choices)
    if choices[1] then
      prompt_path(ws, dir, choices[1])
    end
  end)
end

local function local_flow(ws, dir)
  local api = require "obsidian.api"
  local p = api.input "Local folder to two-way sync with (absolute path): "
  if not p or p == "" then return end
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

function M.setup(ws)
  local dir = norm(tostring(ws.root))
  local picker = require "obsidian.picker"

  local WEBDAV = "WebDAV / Nextcloud (connect directly)"
  local EXISTING = "Use an existing rclone remote"
  local RCLONE_CFG = "Run rclone config to add a new remote"
  local LOCAL = "Sync with a local folder (two-way)"

  picker.select({ WEBDAV, EXISTING, RCLONE_CFG, LOCAL }, {
    prompt = "Configure rclone sync for " .. tostring(ws.name),
    format_item = function(item) return item end,
  }, function(choices)
    local choice = choices[1]
    if not choice then return end
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
      pcall(function() t:stop(); t:close() end)
    end
  end,
})

return M
