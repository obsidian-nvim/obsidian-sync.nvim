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
end

---@return obsidian.sync.Backend?
function M.backend()
  return require "obsidian-sync.backend"
end

return M
