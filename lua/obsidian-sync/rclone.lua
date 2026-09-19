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

---Computed at require time (main loop): vim.fn.has is not callable in fast contexts.
---@type boolean
local IS_WIN = vim.fn.has "win32" == 1

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
---@param opts { cwd?: string, handler?: fun(err: string?, data: string?), stderr?: fun(err: string?, data: string?) }
---@param on_exit fun(out: vim.SystemCompleted)
---@return vim.SystemObj
function M.run_async(args, opts, on_exit)
  -- Note: with streamed handlers, SystemCompleted.stdout/stderr are nil.
  return vim.system(
    { M.bin, unpack(args) },
    { cwd = opts.cwd, stdout = opts.handler, stderr = opts.stderr or opts.handler },
    on_exit
  )
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

-- ── bisync lock recovery ──────────────────────────────────────────────────

---Detect rclone's "prior lock file found" failure and locate the lock file.
---
---rclone colourises stderr, so ANSI escapes are stripped before matching.
---The path is taken from the NOTICE line, with rclone's own
---`deletefile "…"` tip as a fallback.
---@param stderr string? rclone stderr
---@return string|true|nil lock file path, `true` if the error is a lock error but no path parses, nil otherwise
function M.lock_error(stderr)
  local s = tostring(stderr or "")
  if not s:find("prior lock file found", 1, true) then
    return nil
  end
  local clean = s:gsub("\27%[[0-9;]*m", "")
  return clean:match "prior lock file found:%s*(%S+%.lck)" or clean:match 'deletefile%s+"([^"]+%.lck)"' or true
end

---Remove a stale bisync lock if its owning process is dead.
---
---A `.lck` is JSON (`{"Session":…, "PID":"19449", …}`) left behind when a
---bisync dies without cleanup (nvim crash, SIGKILL, reboot). It blocks every
---future run until manually deleted. The lock is only removed when the
---recorded PID no longer exists — a live owner means a bisync is genuinely
---in flight and must not be disturbed.
---@param lock_path string path to the `.lck` file
---@return boolean removed true if a stale lock was deleted
---@return string|nil pid owner PID from the lock file, when readable
function M.clear_stale_lock(lock_path)
  -- Called from vim.system's on_exit (fast context): vim.fn.* would raise
  -- E5560 there, so everything below is libuv / Lua-only.
  local fd = vim.uv.fs_open(lock_path, "r", 438)
  if not fd then
    return false, nil
  end
  local stat = vim.uv.fs_fstat(fd)
  local contents = (stat and stat.size > 0) and vim.uv.fs_read(fd, stat.size, 0) or ""
  vim.uv.fs_close(fd)
  local jok, data = pcall(vim.json.decode, contents or "")
  if not jok or type(data) ~= "table" then
    return false, nil
  end
  local pid = tonumber(data.PID) --[[@as integer]]
  if not pid then
    return false, data.PID
  end
  -- Signal 0 probes liveness without signalling anything. 0 (or a pcall
  -- failure) means alive; EPERM/EACCES (exists, other user) also means alive.
  -- Only ESRCH — plus EINVAL on Windows, where OpenProcess maps a bogus pid
  -- to it — proves the owner is dead.
  local pok, res, _, name = pcall(vim.uv.kill, pid, 0)
  if not pok or res == 0 or (name ~= "ESRCH" and not (IS_WIN and name == "EINVAL")) then
    return false, data.PID
  end
  local unlinked = vim.uv.fs_unlink(lock_path)
  return unlinked == true or unlinked == 0, data.PID
end

return M
