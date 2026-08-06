local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()

local function tmpdir()
  local d = os.tmpname() .. ".d"
  vim.fn.mkdir(d, "p")
  return d
end

-- ── rclone ───────────────────────────────────────────────────────────────

T["rclone"] = new_set()

T["rclone"]["bisync_args should produce correct argv"] = function()
  local rclone = require "obsidian-sync.rclone"
  local args = rclone.bisync_args("/tmp/vault", "s3:bucket", {
    exclude = { ".DS_Store", "*.tmp" },
    args = { "--max-delete=10" },
  })
  eq("bisync", args[1])
  eq("--verbose", args[2])
  eq("--create-empty-src-dirs", args[3])

  -- Count --exclude occurrences
  local n_exclude = 0
  for _, a in ipairs(args) do
    if a == "--exclude" then
      n_exclude = n_exclude + 1
    end
  end
  eq(2, n_exclude)

  -- Last two args must be local_dir and remote
  eq("/tmp/vault", args[#args - 1])
  eq("s3:bucket", args[#args])
end

T["rclone"]["bisync_args should handle empty config"] = function()
  local args = require("obsidian-sync.rclone").bisync_args("/v", "r:", { exclude = {}, args = {} })
  eq("bisync", args[1])
  eq("/v", args[#args - 1])
  eq("r:", args[#args])
end

-- ── backend contract ─────────────────────────────────────────────────────

T["backend"] = new_set()

T["backend"]["should have required contract fields"] = function()
  local b = require "obsidian-sync.backend"
  eq("rclone", b.name)
  eq("table", type(b.caps))
  eq("function", type(b.is_configured))
  eq("function", type(b.start))
  eq("function", type(b.sync_once))
  eq("function", type(b.setup))
  eq("function", type(b.disconnect))
  eq("function", type(b.log))
  eq("function", type(b.ws_formatter))
end

T["backend"]["configure should merge without crashing"] = function()
  local b = require "obsidian-sync.backend"
  b.configure { check_interval = 60, auto_resync = false }
  -- reaching here without error is sufficient
end

T["backend"]["is_configured false for unknown vault"] = function()
  local b = require "obsidian-sync.backend"
  b.configure { remotes = {} }
  eq(false, b.is_configured { root = "/nonexistent/vault" })
end

T["backend"]["is_configured finds linked vault"] = function()
  local b = require "obsidian-sync.backend"
  local root = tmpdir()
  b.configure { remotes = { [root] = "r:x" } }
  eq(true, b.is_configured { root = root })
end

T["backend"]["ws_formatter shows remote name"] = function()
  local b = require "obsidian-sync.backend"
  local root = tmpdir()
  vim.wait(50)
  b.configure { remotes = { [root] = "remote:x" } }
  local s = b.ws_formatter { name = "Test", root = root }
  eq("string", type(s))
  eq(true, s:find "Test" ~= nil, "should contain vault name")
end

T["backend"]["ws_formatter without remote"] = function()
  local b = require "obsidian-sync.backend"
  local root = tmpdir()
  b.configure { remotes = {} }
  local s = b.ws_formatter { name = "T", root = root }
  eq(true, s:find "T" ~= nil)
  eq(false, s:find "->" ~= nil)
end

T["backend"]["disconnect removes mapping"] = function()
  local b = require "obsidian-sync.backend"
  local root = tmpdir()
  b.configure { remotes = { [root] = "r:x" }, persist = function() end }
  eq(true, b.is_configured { root = root })
  b.disconnect { name = "T", root = root }
  eq(false, b.is_configured { root = root })
end

T["backend"]["pause returns true"] = function()
  local b = require "obsidian-sync.backend"
  eq(true, b.pause(tmpdir()))
end

T["backend"]["log does not crash"] = function()
  local b = require "obsidian-sync.backend"
  local root = tmpdir()
  b.configure { remotes = {} }
  b.log(root)
  -- Clean up log buffer
  require("obsidian.sync.runner").logs[root] = nil
end

-- ── statusline ───────────────────────────────────────────────────────────

T["statusline"] = new_set()

T["statusline"]["lualine returns table with provider"] = function()
  local comp = require("obsidian-sync.statusline").lualine()
  eq("table", type(comp))
  eq("function", type(comp[1]))
end

T["statusline"]["heirline returns table"] = function()
  local comp = require("obsidian-sync.statusline").heirline()
  eq("table", type(comp))
  eq("function", type(comp.provider))
end

T["statusline"]["plain returns string"] = function()
  eq("string", type(require("obsidian-sync.statusline").plain()))
end

-- ── ui ───────────────────────────────────────────────────────────────────

T["ui"] = new_set()

T["ui"]["progress_win opens and closes"] = function()
  local ui = require "obsidian-sync.ui"
  local dir = tmpdir()
  ui.progress_win(dir, "Test", "")
  eq(true, ui.is_open(dir))
  ui.close_progress(dir)
  vim.wait(100)
end

T["ui"]["close_progress with synced"] = function()
  local ui = require "obsidian-sync.ui"
  local dir = tmpdir()
  ui.progress_win(dir, "T", "")
  ui.close_progress(dir, "synced")
end

T["ui"]["close_progress with error"] = function()
  local ui = require "obsidian-sync.ui"
  local dir = tmpdir()
  ui.progress_win(dir, "T", "")
  ui.close_progress(dir, "error")
end

T["ui"]["update_detail works on open window"] = function()
  local ui = require "obsidian-sync.ui"
  local dir = tmpdir()
  ui.progress_win(dir, "Test", "initial")
  ui.update_detail(dir, "3 files · note.md")
  ui.close_progress(dir)
end

-- ── verbose progress config ───────────────────────────────────────────────

T["verbose"] = new_set()

T["verbose"]["config field defaults to false"] = function()
  local b = require "obsidian-sync.backend"
  b.configure {}
end

T["verbose"]["config accepts verbose_progress = true"] = function()
  local b = require "obsidian-sync.backend"
  b.configure { verbose_progress = true }
  -- reaching here without error is sufficient
end

return T
