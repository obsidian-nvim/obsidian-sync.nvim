---obsidian-sync.nvim — bidirectional Obsidian vault sync backed by rclone.
---
---Registers a "rclone" backend into obsidian.nvim's sync module so the
---existing `:Obsidian sync` menu, `on_write` trigger, continuous mode,
---log buffer and statusline all work with WebDAV / Nextcloud / S3 / Dropbox
---/ Google Drive / SFTP / SMB / local folders — i.e. the same feature set
---as the desktop "Remotely Save" plugin, without the desktop app.
---
---Works on macOS, Linux, and Windows (rclone is fully cross-platform).

---@class obsidian-sync.Config.Bisync
---@field exclude string[] globs to exclude from bisync
---@field args string[] extra rclone bisync flags

---@class obsidian-sync.Config
---@field remotes table<string,string> vault root → remote target (rclone remote:path or local dir)
---@field check_interval integer seconds between continuous syncs (default 300)
---@field auto_resync boolean retry once with --resync if bisync demands it
---@field safe_resync boolean log a friendly notice instead of ERROR on first --resync
---@field notify_events boolean vim.notify on sync start / complete / error
---@field progress_win boolean floating spinner window while syncing
---@field verbose_progress boolean show file-level detail in progress window (default false)
---@field trigger string "manual"|"on_write"|"continuous"
---@field bisync obsidian-sync.Config.Bisync

local M = {}

local DEFAULT = {
  remotes = {},
  check_interval = 300,
  auto_resync = true,
  safe_resync = true,
  notify_events = true,
  progress_win = true,
  verbose_progress = false,
  trigger = "manual",
  bisync = { exclude = { ".DS_Store", "*.bisync*", ".bisync/**" }, args = {} },
}

---@type obsidian-sync.Config
local config

---Return the persistent state JSON file path.
---@return string
local function state_file()
  return vim.fn.stdpath "data" .. "/obsidian-sync.json"
end

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

---Load persisted config from disk.
---@return table
local function load()
  local file = state_file()
  if vim.fn.filereadable(file) == 0 then
    return {}
  end
  local ok, lines = pcall(vim.fn.readfile, file)
  if not ok or type(lines) ~= "table" or #lines == 0 then
    return {}
  end
  local ok2, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
  if not ok2 or type(decoded) ~= "table" then
    return {}
  end
  return decoded
end

---Save config to disk (strips non-serialisable function keys).
---@param cfg obsidian-sync.Config
local function persist(cfg)
  config = cfg
  -- Ensure stdpath("data") exists (fresh Neovim may not have it).
  vim.fn.mkdir(vim.fn.stdpath "data", "p")
  local saved = {}
  for k, v in pairs(config) do
    if type(v) == "function" then
      saved[k] = v
      config[k] = nil
    end
  end
  local ok, encoded = pcall(vim.fn.json_encode, config)
  for k, v in pairs(saved) do
    config[k] = v
  end
  if not ok then
    return
  end
  pcall(vim.fn.writefile, vim.split(encoded, "\n"), state_file())
end

---Configure the plugin and register the backend with obsidian.nvim.
---@param opts? obsidian-sync.Config
function M.setup(opts)
  opts = opts or {}

  local loaded = load()
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT), loaded, opts)

  local normalized = {}
  for root, remote in pairs(config.remotes) do
    normalized[norm(root)] = remote
  end
  config.remotes = normalized
  persist(config)

  -- Detect rclone binary (cross-platform).
  local rclone_bin = vim.fn.exepath "rclone"
  if rclone_bin and rclone_bin ~= "" then
    require("obsidian-sync.rclone").bin = rclone_bin
  elseif vim.fn.has "win32" == 1 then
    for _, p in ipairs { "C:\\rclone\\rclone.exe", vim.fn.expand "~/rclone/rclone.exe" } do
      ---@diagnostic disable-next-line: param-type-mismatch
      if vim.fn.executable(p) == 1 then
        require("obsidian-sync.rclone").bin = p
        break
      end
    end
  end

  local backend = require "obsidian-sync.backend"
  backend.configure(config)
  backend.persist = persist

  local ok, sync = pcall(require, "obsidian.sync")
  if not ok then
    vim.notify(
      "[obsidian-sync] obsidian.nvim not found on the runtimepath.\n"
        .. "Load obsidian.nvim (as a dependency) before this plugin.",
      vim.log.levels.ERROR
    )
    return
  end
  sync.register("rclone", backend)

  -- Apply trigger preference (auto-enables on_write if requested).
  -- `obsidian` is a global module loaded by obsidian.nvim.
  if config.trigger == "on_write" and _G.obsidian and _G.obsidian.opts and _G.obsidian.opts.sync then
    _G.obsidian.opts.sync.trigger = "on_write"
  end

  -- First-run: auto-offer setup wizard if no vaults are linked yet.
  if vim.tbl_isempty(config.remotes) then
    local function offer_wizard()
      if not Obsidian then
        return
      end
      if vim.fn.isdirectory ".obsidian" == 0 then
        return
      end
      local choice = vim.fn.confirm("obsidian-sync: No vaults linked yet.\nRun the setup wizard now?", "&Yes\n&No", 1)
      if choice == 1 then
        sync.setup()
      else
        vim.notify("[obsidian-sync] Run :ObsidianSync or :Obsidian sync setup later.", vim.log.levels.INFO)
      end
    end
    vim.api.nvim_create_autocmd("VimEnter", { once = true, callback = offer_wizard })
    vim.api.nvim_create_autocmd("User", {
      pattern = "ObsidianWorkpspaceSet",
      once = true,
      callback = vim.schedule_wrap(function()
        if vim.tbl_isempty(config.remotes) then
          offer_wizard()
        end
      end),
    })
  end
end

---Get the rclone backend instance.
---@return obsidian.sync.Backend?
function M.backend()
  return require "obsidian-sync.backend"
end

-- ── convenience: direct command ─────────────────────────────────────────

vim.api.nvim_create_user_command("ObsidianSync", function()
  local ok, sync = pcall(require, "obsidian.sync")
  if not ok then
    vim.notify("[obsidian-sync] obsidian.nvim not found.", vim.log.levels.ERROR)
    return
  end
  local has = false
  for _, ws in ipairs(Obsidian.workspaces or {}) do
    if sync.is_configured(ws) then
      has = true
      break
    end
  end
  if has then
    sync.menu()
  else
    sync.setup()
  end
end, { desc = "obsidian-sync: open sync menu or setup wizard" })

-- ── checkhealth ─────────────────────────────────────────────────────────

---Run inline health checks for :ObsidianSyncHealth.
local function health()
  local start = vim.health.start or vim.health.report_start
  local ok = vim.health.ok or vim.health.report_ok
  local warn = vim.health.warn or vim.health.report_warn
  local err = vim.health.error or vim.health.report_error

  start "obsidian-sync"

  local rclone_bin = vim.fn.exepath "rclone"
  if rclone_bin and rclone_bin ~= "" then
    ok("rclone found: " .. rclone_bin)
  else
    err "rclone not found on PATH. Install from https://rclone.org/install/"
  end

  local has_obs, _ = pcall(require, "obsidian.sync")
  if has_obs then
    ok "obsidian.nvim found"
  else
    err "obsidian.nvim not on runtimepath"
  end

  local remotes = config and config.remotes or {}
  if vim.tbl_isempty(remotes) then
    warn "No vaults linked. Run :ObsidianSync to set up."
  else
    for vault, remote in pairs(remotes) do
      ok(string.format("  %s → %s", vault, remote))
    end
  end
end

vim.api.nvim_create_user_command("ObsidianSyncHealth", health, { desc = "obsidian-sync: check health" })

-- :checkhealth obsidian-sync is auto-discovered via lua/obsidian-sync/health.lua.

return M
