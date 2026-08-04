--- Pretty UI for obsidian-sync: floating progress window and status display.
---
---     require("obsidian-sync.ui").progress_win(dir, "Syncing SECOND_BRAIN...")
---     require("obsidian-sync.ui").close_progress(dir)
---
--- The progress window is auto-managed; it shows a spinner while syncing
--- and briefly flips to a checkmark / error icon before closing.

local M = {}

---@class obsidian-sync.ui.ProgressWin
---@field buf integer
---@field win integer
---@field timer uv.uv_timer_t|nil
---@field frame integer

---@type table<string, obsidian-sync.ui.ProgressWin>
local wins = {}

local spinner_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function make_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = true
  return buf
end

local function make_win(buf, title)
  local width = math.min(60, vim.o.columns - 4)
  local height = 3
  local row = vim.o.lines - height - 3
  local col = math.floor((vim.o.columns - width) / 2)

  local win = vim.api.nvim_open_win(buf, false, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = title,
    title_pos = "center",
    noautocmd = true,
  })

  vim.wo[win].winhl = "Normal:ObsidianSyncFloat,NormalNC:ObsidianSyncFloat"
  return win
end

local function update(buf, lines)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
end

---Open a floating progress window for a sync session.
---@param dir string unique session key (vault root)
---@param title string window title
---@param detail? string optional detail line
function M.progress_win(dir, title, detail)
  if wins[dir] then
    -- Already showing; update content.
    local w = wins[dir]
    local frame = spinner_frames[(w.frame % #spinner_frames) + 1]
    update(w.buf, {
      string.format(" %s  %s", frame, title),
      "",
      " " .. (detail or "connecting..."),
    })
    w.frame = w.frame + 1
    return
  end

  local buf = make_buf()
  local win = make_win(buf, "Obsidian Sync")
  local w = { buf = buf, win = win, frame = 1, detail = detail }
  wins[dir] = w

  -- Spinner timer
  w.timer = vim.uv.new_timer()
  w.timer:start(0, 100, vim.schedule_wrap(function()
    if not wins[dir] then
      return
    end
    local frame = spinner_frames[(w.frame % #spinner_frames) + 1]
    update(buf, {
      string.format(" %s  %s", frame, title),
      "",
      " " .. (w.detail or "syncing..."),
    })
    w.frame = w.frame + 1
  end))

  -- Close on <Esc>
  vim.keymap.set("n", "<Esc>", function()
    M.close_progress(dir)
  end, { buffer = buf, silent = true })
end

---Update the detail line of an open progress window.
---@param dir string
---@param detail string
function M.update_detail(dir, detail)
  local w = wins[dir]
  if not w then
    return
  end
  w.detail = detail
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

  local icon, hl = "", "ObsidianSyncFloat"
  if result == "synced" then
    icon, hl = "󰸞  Synced", "DiagnosticOk"
  elseif result == "error" then
    icon, hl = "󰅙  Error", "DiagnosticError"
  end

  if icon ~= "" then
    update(w.buf, { "", "  " .. icon, "" })
    vim.api.nvim_set_hl(0, hl, { default = true })
    -- Flash result for 1.5s then close
    vim.defer_fn(function()
      if vim.api.nvim_win_is_valid(w.win) then
        vim.api.nvim_win_close(w.win, true)
      end
    end, 1500)
  else
    vim.api.nvim_win_close(w.win, true)
  end

  wins[dir] = nil
end

---Check if a progress window is open for a session.
---@param dir string
---@return boolean
function M.is_open(dir)
  return wins[dir] ~= nil
end

-- ── highlight groups ─────────────────────────────────────────────────────

vim.api.nvim_set_hl(0, "ObsidianSyncFloat", {
  link = "NormalFloat",
  default = true,
})

return M
