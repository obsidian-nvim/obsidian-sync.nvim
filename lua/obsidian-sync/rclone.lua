--- Thin wrapper around the `rclone` CLI (https://rclone.org).
---
--- All sync is delegated to `rclone bisync`, which provides true
--- bidirectional sync over S3, WebDAV, Nextcloud, Dropbox, Google Drive,
--- SFTP, SMB, local folders, and ~every other remote type rclone supports.
--- That means the same code path works for "Remotely Save"-style cloud sync
--- without writing any cloud-specific code.

local M = {}

---@type string
M.bin = "rclone"

---@return string? rclone version line, nil if the binary is missing
function M.available()
  local out = vim.fn.system { M.bin, "version" }
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(out):match "^([^\n]*)"
end

---@return string[]? configured remote names (e.g. {"mys3:", "webdav:"}), nil on error
function M.listremotes()
  local out = vim.fn.systemlist { M.bin, "listremotes" }
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return out
end

---@param args string[]
---@param opts { cwd?: string, handler?: fun(err: string?, data: string?) }
---@param on_exit fun(out: vim.SystemCompleted)
---@return vim.SystemObj
function M.run_async(args, opts, on_exit)
  return vim.system({ M.bin, unpack(args) }, { cwd = opts.cwd, stdout = opts.handler, stderr = opts.handler }, on_exit)
end

---Build the `rclone bisync` argv for a vault.
---@param local_dir string
---@param remote string e.g. "mys3:vault/main"
---@param cfg { exclude?: string[], args?: string[] }
---@return string[]
function M.bisync_args(local_dir, remote, cfg)
  local args = { "bisync", "--verbose", "--create-empty-src-dirs" }
  for _, pat in ipairs(cfg.exclude or {}) do
    vim.list_extend(args, { "--exclude", pat })
  end
  vim.list_extend(args, cfg.args or {})
  vim.list_extend(args, { local_dir, remote })
  return args
end

return M
