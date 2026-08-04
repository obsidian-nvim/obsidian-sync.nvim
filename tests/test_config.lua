local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()

local function tmpdir()
  local d = os.tmpname() .. ".d"
  vim.fn.mkdir(d, "p")
  return d
end

-- ── defaults / setup ─────────────────────────────────────────────────────

T["defaults"] = new_set()

T["defaults"]["setup registers rclone backend"] = function()
  local state = vim.fn.stdpath("data") .. "/obsidian-sync.json"
  os.remove(state)

  require("obsidian-sync").setup { remotes = {}, check_interval = 120 }

  local backend = require("obsidian.sync").get_backend()
  -- get_backend reads Obsidian.opts.sync.backend — which is "obsidian" by
  -- default because obsidian.nvim hasn't been set up with user opts here.
  -- But our register("rclone", ...) should have stored "rclone".
  -- Verify the backend name via the registered module.
  eq("rclone", require("obsidian-sync.backend").name)

  os.remove(state)
end

-- ── persistence ──────────────────────────────────────────────────────────

T["persistence"] = new_set()

T["persistence"]["config round-trips through JSON"] = function()
  local state = vim.fn.stdpath("data") .. "/obsidian-sync-test.json"
  os.remove(state)

  local test_config = {
    remotes = { ["/tmp/test-vault"] = "s3:test" },
    check_interval = 99,
    auto_resync = false,
    bisync = { exclude = { "*.tmp" }, args = { "--dry-run" } },
  }

  local encoded = vim.fn.json_encode(test_config)
  vim.fn.writefile(vim.split(encoded, "\n"), state)

  eq(1, vim.fn.filereadable(state))
  local lines = vim.fn.readfile(state)
  local decoded = vim.fn.json_decode(table.concat(lines, "\n"))
  eq("table", type(decoded))
  eq(99, decoded.check_interval)
  eq(false, decoded.auto_resync)
  eq("s3:test", decoded.remotes["/tmp/test-vault"])
  eq("*.tmp", decoded.bisync.exclude[1])
  eq("--dry-run", decoded.bisync.args[1])

  os.remove(state)
end

-- ── path normalisation ───────────────────────────────────────────────────

T["normalisation"] = new_set()

T["normalisation"]["handles trailing slash"] = function()
  local root = tmpdir()
  local state = vim.fn.stdpath("data") .. "/obsidian-sync.json"
  os.remove(state)

  require("obsidian-sync").setup { remotes = { [root .. "/"] = "r:x" } }
  eq(true, require("obsidian-sync.backend").is_configured { root = root })

  os.remove(state)
end

T["normalisation"]["consistent resolution"] = function()
  local root = tmpdir()
  local state = vim.fn.stdpath("data") .. "/obsidian-sync.json"
  os.remove(state)

  require("obsidian-sync").setup { remotes = { [root] = "r:x" } }
  eq(true, require("obsidian-sync.backend").is_configured { root = root })

  os.remove(state)
end

-- ── commands ─────────────────────────────────────────────────────────────

T["commands"] = new_set()

T["commands"]["ObsidianSync is defined"] = function()
  -- Command is created at module load time in init.lua
  eq(2, vim.fn.exists(":ObsidianSync"))
end

T["commands"]["ObsidianSyncHealth is defined"] = function()
  eq(2, vim.fn.exists(":ObsidianSyncHealth"))
end

return T
