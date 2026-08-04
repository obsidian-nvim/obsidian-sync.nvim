--- Drop-in integrations for popular Neovim statusline plugins.
---
---    require("obsidian-sync.statusline").lualine()
---    require("obsidian-sync.statusline").heirline()
---    require("obsidian-sync.statusline").mini()
---    require("obsidian-sync.statusline").feline()
---    require("obsidian-sync.statusline").windline()
---    require("obsidian-sync.statusline").plain()
---
--- The component auto-updates via `User ObsidianSyncChanged` autocmd.

local M = {}

local function get_icon()
  local ok, status = pcall(require, "obsidian.sync.status")
  if not ok then
    return ""
  end
  local ico = status.icon()
  if ico ~= "" then
    return ico
  end
  -- status module hasn't fired set() yet — return default for current kind
  local kind = status.state and status.state.kind or "paused"
  local defaults = { synced = "󰸞", syncing = "󰑓", paused = "󰏤", error = "󰅙" }
  return defaults[kind] or ""
end

local function get_hl()
  local ok, status = pcall(require, "obsidian.sync.status")
  if not ok then
    return "Normal"
  end
  return status.color()
end

---@return boolean
local function visible()
  return vim.bo.filetype == "markdown" and get_icon() ~= ""
end

-- ── autocmd: force statusline redraw on sync status change ──────────────

local function ensure_refresh_autocmd()
  if vim.g.obsidian_sync_statusline_autocmd_set then
    return
  end
  vim.g.obsidian_sync_statusline_autocmd_set = true
  vim.api.nvim_create_autocmd("User", {
    pattern = "ObsidianSyncChanged",
    group = vim.api.nvim_create_augroup("ObsidianSyncStatusline", { clear = true }),
    desc = "Refresh statusline when sync status changes",
    callback = function()
      -- lualine
      pcall(function()
        require("lualine").refresh()
      end)
      -- mini.statusline
      pcall(function()
        require("mini.statusline").refresh()
      end)
      -- feline
      pcall(function()
        require("feline").reset_highlights()
      end)
      -- fallback: force vim redraw
      vim.cmd "redrawstatus"
    end,
  })
end

-- ── lualine.nvim ─────────────────────────────────────────────────────────

---@return table lualine component spec
function M.lualine()
  ensure_refresh_autocmd()
  return {
    function()
      return get_icon()
    end,
    color = function()
      return get_hl()
    end,
    cond = visible,
    on_click = function()
      vim.cmd "ObsidianSync"
    end,
  }
end

-- ── heirline.nvim ────────────────────────────────────────────────────────

function M.heirline()
  return {
    provider = function()
      return get_icon() .. " "
    end,
    hl = function()
      return { fg = get_hl() }
    end,
    update = { "User", pattern = "ObsidianSyncChanged" },
    on_click = { callback = function() vim.cmd "ObsidianSync" end },
  }
end

-- ── mini.statusline ──────────────────────────────────────────────────────

---@return function provider function returning icon string
function M.mini()
  return function()
    return get_icon()
  end
end

-- ── feline.nvim ──────────────────────────────────────────────────────────

function M.feline()
  return {
    provider = function()
      return get_icon()
    end,
    hl = {
      fg = get_hl(),
    },
    update = { "User ObsidianSyncChanged" },
  }
end

-- ── windline.nvim ────────────────────────────────────────────────────────

function M.windline()
  return {
    text = function()
      return get_icon()
    end,
    hl_colors = { fg = get_hl() },
    update = { "User", "ObsidianSyncChanged" },
  }
end

-- ── plain vim statusline (drop-in string) ────────────────────────────────

---@return string e.g. "%#ObsidianSyncSynced# 󰸞 %*"
function M.plain()
  return require("obsidian.sync.status").component()
end

return M
