---:checkhealth obsidian-sync
---(Neovim auto-discovers this file at lua/obsidian-sync/health.lua)

local M = {}

---Standard Neovim healthcheck entry point.
---Called by :checkhealth obsidian-sync.
function M.check()
  vim.health.start "obsidian-sync"

  local rclone_bin = vim.fn.exepath "rclone"
  if rclone_bin and rclone_bin ~= "" then
    vim.health.ok("rclone: " .. rclone_bin)
    -- Check version
    local out = vim.fn.system { rclone_bin, "version" }
    local ver = vim.trim(out):match "rclone v([^\n]+)"
    if ver then
      vim.health.ok("  version: " .. ver)
    end
  else
    vim.health.error "rclone not found on PATH.  Install from https://rclone.org/install/"
  end

  local has_obs, _ = pcall(require, "obsidian.sync")
  if has_obs then
    vim.health.ok "obsidian.nvim loaded"
  else
    vim.health.error "obsidian.nvim not on runtimepath"
  end

  -- Remotes
  local state_file = vim.fn.stdpath "data" .. "/obsidian-sync.json"
  local remotes = {}
  if vim.fn.filereadable(state_file) == 1 then
    local ok, lines = pcall(vim.fn.readfile, state_file)
    if ok then
      local ok2, decoded = pcall(vim.fn.json_decode, table.concat(lines, "\n"))
      if ok2 and decoded and decoded.remotes then
        remotes = decoded.remotes
      end
    end
  end

  if vim.tbl_isempty(remotes) then
    vim.health.warn "No vaults linked.  Run :ObsidianSync to set up."
  else
    vim.health.ok "Linked vaults:"
    for vault, remote in pairs(remotes) do
      vim.health.ok(string.format("  %s → %s", vault, remote))
    end
  end
end

return M
