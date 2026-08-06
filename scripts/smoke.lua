-- Headless smoke test: two-way sync between a local vault and a local folder
-- through the rclone backend.
-- Prerequisites: rclone on PATH, deps/obsidian.nvim cloned (make test does this).
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
print "SMOKE OK"

vim.cmd "qa!"
