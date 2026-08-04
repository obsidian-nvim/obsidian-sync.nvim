--- obsidian-sync.nvim — bidirectional Obsidian vault sync backed by rclone.
---
--- Registers a "rclone" backend into obsidian.nvim's sync module so the
--- existing `:Obsidian sync` menu, `on_write` trigger, continuous mode,
--- log buffer and statusline all work with WebDAV / Nextcloud / S3 / Dropbox
--- / Google Drive / SFTP / SMB / local folders — i.e. the same feature set
--- as the desktop "Remotely Save" plugin, without the desktop app.
---
--- Works on macOS, Linux, and Windows (rclone is fully cross-platform).
---
--- Usage:
---   { "obsidian-nvim/obsidian.nvim", lazy = true, opts = { sync = { enabled = true, backend = "rclone" } } },
---   require("obsidian-sync").setup {
---     remotes = { ["/path/to/vault"] = "my-webdav:" },
---     trigger = "on_write",
---     safe_resync = true,
---   }

local M = {}

local DEFAULT = {
  remotes = {}, -- vault root → "remote:path" (or an absolute local path)
  check_interval = 300, -- seconds between continuous syncs
  auto_resync = true, -- retry once with --resync if bisync demands it
  safe_resync = true, -- log a friendly notice instead of ERROR on first --resync
  trigger = "manual", -- "on_write" | "continuous" | "manual" (overrides obsidian.nvim's sync.trigger)
  bisync = { exclude = { ".DS_Store", "*.bisync*", ".bisync/**" }, args = {} },
}

local config

local function state_file()
  return vim.fn.stdpath("data") .. "/obsidian-sync.json"
end

local function norm(dir)
  return vim.uv.fs_realpath(tostring(dir)) or vim.fs.normalize(vim.fn.fnamemodify(tostring(dir), ":p"))
end

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

local function persist(cfg)
  config = cfg
  local ok, encoded = pcall(vim.fn.json_encode, config)
  if not ok then
    return
  end
  pcall(vim.fn.writefile, vim.split(encoded, "\n"), state_file())
end

---Configure the plugin and register the backend with obsidian.nvim.
---@param opts? obsidian-sync.config
function M.setup(opts)
  opts = opts or {}

  local loaded = load()
  config = vim.tbl_deep_extend("force", vim.deepcopy(DEFAULT), loaded, opts)

  -- Normalize remote keys to canonical absolute paths.
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

  -- Apply trigger preference (auto-enables on_write if requested)
  if config.trigger == "on_write" and obsidian and obsidian.opts and obsidian.opts.sync then
    obsidian.opts.sync.trigger = "on_write"
  end

  -- First-run: auto-offer setup wizard if no vaults are linked yet.
  -- Uses a one-shot VimEnter autocmd so we don't block startup.
  -- First-run wizard: fires when obsidian is loaded and no vaults are linked.
  -- With lazy ft='markdown', this may be deferred until the first .md buffer.
  if vim.tbl_isempty(config.remotes) then
    local function offer_wizard()
      if not _G.Obsidian then return end -- obsidian hasn't loaded yet, skip
      local choice = vim.fn.confirm(
        "obsidian-sync: No vaults linked yet.\nRun the setup wizard now?",
        "&Yes\n&No",
        1
      )
      if choice == 1 then
        sync.setup()
      else
        vim.notify(
          "[obsidian-sync] Run :ObsidianSync or :Obsidian sync setup later.",
          vim.log.levels.INFO
        )
      end
    end
    -- Try early; also listen for obsidian workspace init as fallback.
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
  -- If any vault already configured, show the menu; otherwise jump to wizard.
  local has = false
  for _, ws in ipairs(Obsidian.workspaces or {}) do
    if sync.is_configured(ws) then has = true; break end
  end
  if has then
    sync.menu()
  else
    sync.setup()
  end
end, { desc = "obsidian-sync: open sync menu or setup wizard" })

-- ── checkhealth ─────────────────────────────────────────────────────────

---@module "obsidian"
local function health()
  local start = vim.health.start or vim.health.report_start
  local ok = vim.health.ok or vim.health.report_ok
  local warn = vim.health.warn or vim.health.report_warn
  local err = vim.health.error or vim.health.report_error

  start "obsidian-sync"

  -- rclone binary
  local rclone_bin = vim.fn.exepath "rclone"
  if rclone_bin and rclone_bin ~= "" then
    ok("rclone found: " .. rclone_bin)
  else
    err("rclone not found on PATH. Install from https://rclone.org/install/")
  end

  -- obsidian.nvim
  local has_obs, _ = pcall(require, "obsidian.sync")
  if has_obs then
    ok "obsidian.nvim found"
  else
    err "obsidian.nvim not on runtimepath"
  end

  -- configured remotes
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

-- Register with :checkhealth if available (Neovim >= 0.10)
pcall(function()
  local health_ns = vim.api.nvim_create_namespace "obsidian-sync"
  -- Available via :checkhealth obsidian-sync (auto-discovered if lua/obsidian-sync/health.lua exists)
end)

return M
