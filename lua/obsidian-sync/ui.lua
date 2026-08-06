---Floating progress window for obsidian-sync.
---
---    require("obsidian-sync.ui").progress_win(dir, "Syncing vault...")
---    require("obsidian-sync.ui").close_progress(dir)
---
---Minimal, professional styling: spinner + title + detail line,
---auto-closes after a brief result flash.

local M = {}

---@class obsidian-sync.ui.ProgressWin
---@field buf integer
---@field win integer
---@field timer uv.uv_timer_t|nil
---@field frame integer
---@field vault_name string
---@field detail string|nil

---@type table<string, obsidian-sync.ui.ProgressWin>
local wins = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

-- ── highlight groups (link to built-ins, no hardcoded colors) ───────────

local HL_NS = vim.api.nvim_create_namespace "obsidian-sync-hl"

local function ensure_highlights()
  local defs = {
    ObsidianSyncSpinner = { link = "DiagnosticInfo", default = true },
    ObsidianSyncDetail = { link = "Comment", default = true },
    ObsidianSyncSuccess = { link = "DiagnosticOk", default = true },
    ObsidianSyncError = { link = "DiagnosticError", default = true },
    ObsidianSyncFloatTitle = { link = "FloatTitle", default = true },
  }
  for name, opts in pairs(defs) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end
ensure_highlights()

-- ── helpers ───────────────────────────────────────────────────────────────

---@return integer buf
local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  return buf
end

---@param buf integer
---@param lines string[]
local function set_content(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

local function render(w, frame_icon)
  local lines = {
    string.format("  %s  %s", frame_icon, w.vault_name),
    "",
    "  " .. (w.detail or ""),
  }
  set_content(w.buf, lines)
  -- Highlight spinner
  vim.api.nvim_buf_clear_namespace(w.buf, HL_NS, 0, -1)
  vim.api.nvim_buf_set_extmark(w.buf, HL_NS, 0, 2, {
    end_col = 2 + #frame_icon,
    hl_group = "ObsidianSyncSpinner",
  })
  -- Dim detail line
  vim.api.nvim_buf_set_extmark(w.buf, HL_NS, 2, 0, {
    end_col = #lines[3],
    hl_group = "ObsidianSyncDetail",
  })
end

-- ── public API ────────────────────────────────────────────────────────────

---Open a floating progress window.
---@param dir string vault root (session key)
---@param title string e.g. "Syncing vault..."
---@param detail? string
function M.progress_win(dir, title, detail)
  if wins[dir] then
    local w = wins[dir]
    w.detail = detail or w.detail
    local icon = spinner_frames[(w.frame % #spinner_frames) + 1]
    render(w, icon)
    w.frame = w.frame + 1
    return
  end

  local width = math.min(44, vim.o.columns - 4)
  local height = 3
  local row = math.max(0, vim.o.lines - height - 4)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = make_buf()
  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " Obsidian Sync ",
    title_pos = "center",
    noautocmd = true,
  })
  vim.wo[win].winhl = "Normal:NormalFloat,FloatTitle:ObsidianSyncFloatTitle"

  local w = {
    buf = buf,
    win = win,
    timer = nil,
    frame = 1,
    vault_name = title,
    detail = detail or "connecting...",
  }
  wins[dir] = w

  render(w, spinner_frames[1])

  -- Spinner
  w.timer = vim.uv.new_timer()
  w.timer:start(
    0,
    100,
    vim.schedule_wrap(function()
      if not wins[dir] then
        return
      end
      local icon = spinner_frames[(w.frame % #spinner_frames) + 1]
      render(w, icon)
      w.frame = w.frame + 1
    end)
  )

  for _, key in ipairs { "<Esc>", "q" } do
    vim.keymap.set("n", key, function()
      M.close_progress(dir)
    end, { buffer = buf, silent = true })
  end
end

---Update the detail line.
---@param dir string
---@param detail string
function M.update_detail(dir, detail)
  local w = wins[dir]
  if w then
    w.detail = detail
  end
end

---Close the progress window after a brief result flash.
---@param dir string
---@param result? "synced"|"error"
function M.close_progress(dir, result)
  local w = wins[dir]
  if not w then
    return
  end

  if w.timer then
    w.timer:stop()
    w.timer:close()
    w.timer = nil
  end
  wins[dir] = nil

  local icon, hl
  if result == "synced" then
    icon, hl = " 󰸞  Synced ", "ObsidianSyncSuccess"
  elseif result == "error" then
    icon, hl = " 󰅙  Error ", "ObsidianSyncError"
  end

  if icon then
    set_content(w.buf, { "", icon, "" })
    vim.api.nvim_buf_set_extmark(w.buf, HL_NS, 1, 0, {
      end_col = #icon,
      hl_group = hl,
    })
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(w.win) then
        vim.api.nvim_win_close(w.win, true)
      end
    end, 1500)
  else
    vim.api.nvim_win_close(w.win, true)
  end
end

---Check if a progress window is open for a session.
---@param dir string
---@return boolean
function M.is_open(dir)
  return wins[dir] ~= nil
end

return M
