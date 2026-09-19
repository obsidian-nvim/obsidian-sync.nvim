-- Headless smoke test: two-way sync between a local vault and a local folder
-- through the rclone backend.
-- Prerequisites: rclone on PATH, deps/obsidian.nvim cloned (make test does this).
--
-- The script persists plugin state to stdpath("data")/obsidian-sync.json, so it
-- MUST run with an isolated XDG_DATA_HOME — otherwise it pollutes your real
-- config with temp-dir vault mappings:
--   XDG_DATA_HOME=$(mktemp -d) nvim --headless --clean -u scripts/smoke.lua
assert(
  vim.env.XDG_DATA_HOME ~= nil and vim.fn.stdpath("data"):find(vim.env.XDG_DATA_HOME, 1, true) ~= nil,
  "smoke test writes plugin state — isolate it first:\n  XDG_DATA_HOME=$(mktemp -d) nvim --headless --clean -u scripts/smoke.lua"
)

vim.opt.rtp:append(vim.uv.cwd())
vim.opt.rtp:append "deps/obsidian.nvim"

local vault = vim.fn.tempname() .. ".vault"
local remote = vim.fn.tempname() .. ".remote"
vim.fn.mkdir(vault, "p")
vim.fn.mkdir(remote, "p")

require("obsidian").setup {
  workspaces = { { name = "smoke", path = vault } },
  sync = { enabled = true, backend = "rclone", trigger = "manual" },
  legacy_commands = false,
}

require("obsidian-sync").setup {
  remotes = { [vault] = remote },
  auto_resync = true,
  bisync = { exclude = {} },
}

local sync = require "obsidian.sync"
assert(sync.get_backend() and sync.get_backend().name == "rclone", "backend not registered")

-- local -> remote
local f1 = vault .. "/First Note.md"
vim.fn.writefile({ "# First", "", "hello world" }, f1)

sync.sync_once()
for _ = 1, 100 do
  vim.wait(100)
  if vim.fn.filereadable(remote .. "/First Note.md") == 1 then
    break
  end
end
assert(vim.fn.filereadable(remote .. "/First Note.md") == 1, "FAIL: local->remote")
print "PASS local->remote"

-- remote -> local (bidirectional)
local f2 = remote .. "/From Remote.md"
vim.fn.writefile({ "# From remote" }, f2)
sync.sync_once()
for _ = 1, 100 do
  vim.wait(100)
  if vim.fn.filereadable(vault .. "/From Remote.md") == 1 then
    break
  end
end
assert(vim.fn.filereadable(vault .. "/From Remote.md") == 1, "FAIL: remote->local")
print "PASS remote->local"

-- conflict: same filename, different content on both sides
vim.fn.writefile({ "local version" }, vault .. "/Conflict.md")
vim.fn.writefile({ "remote version" }, remote .. "/Conflict.md")
sync.sync_once()
for _ = 1, 100 do
  vim.wait(100)
  local conflicts = vim.fn.glob(remote .. "/Conflict.md*")
  if conflicts ~= "" and vim.fn.glob(vault .. "/Conflict.md*") ~= "" then
    break
  end
end
print("conflict artifacts:", vim.fn.glob(vault .. "/Conflict.md*"))

-- stale lock recovery: poison the bisync lock with a dead PID, expect the
-- plugin to remove it and retry the same bisync
local cache = (
  vim.env.XDG_CACHE_HOME
  or (vim.uv.os_uname().sysname == "Darwin" and (vim.env.HOME .. "/Library/Caches") or (vim.env.HOME .. "/.cache"))
) .. "/rclone/bisync"
local listings = vim.fn.glob(cache .. "/*" .. vim.fn.fnamemodify(vault, ":t") .. "*.path1.lst", false, true)
table.sort(listings, function(a, b)
  return vim.fn.getftime(a) > vim.fn.getftime(b)
end)
assert(#listings > 0, "FAIL: no bisync listing found for smoke vault")
local session = listings[1]:sub(1, -1 * #".path1.lst" - 1)

local function poison(pid)
  local now = os.time()
  -- rclone auto-deletes locks with no/past TimeExpires; mirror the
  -- far-future expiry of a real renewing run
  vim.fn.writefile({
    vim.fn.json_encode {
      Session = session,
      PID = pid,
      TimeRenewed = os.date("!%Y-%m-%dT%H:%M:%SZ", now),
      TimeExpires = os.date("!%Y-%m-%dT%H:%M:%SZ", now + 365 * 24 * 60 * 60),
    },
  }, session .. ".lck")
end

poison "4194305" -- above every unix pid_max -> guaranteed dead
vim.fn.writefile({ "# after lock" }, vault .. "/After Lock.md")
sync.sync_once()
local recovered = false
for _ = 1, 100 do
  vim.wait(100)
  if vim.fn.filereadable(remote .. "/After Lock.md") == 1 and vim.uv.fs_stat(session .. ".lck") == nil then
    recovered = true
    break
  end
end
assert(recovered, "FAIL: stale lock was not auto-recovered")
print "PASS stale-lock recovery (dead PID)"

-- live lock must be refused, not deleted
poison(tostring(vim.fn.getpid()))
vim.fn.writefile({ "# live lock" }, vault .. "/Live Lock.md")
sync.sync_once()
vim.wait(2000)
assert(vim.uv.fs_stat(session .. ".lck") ~= nil, "FAIL: live lock was deleted")
assert(vim.fn.filereadable(remote .. "/Live Lock.md") == 0, "FAIL: sync ran despite live lock")
print "PASS live lock refused"

print "SMOKE OK"

vim.cmd "qa!"
