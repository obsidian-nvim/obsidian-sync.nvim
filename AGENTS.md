# obsidian-sync.nvim

Neovim plugin — bidirectional Obsidian vault sync over rclone (WebDAV / S3 / Dropbox / …).
Registers an `obsidian.sync.Backend` into `obsidian.nvim` so `:Obsidian sync`, triggers, statusline and log all work without changes to the upstream plugin.

## Dev environment

- Neovim ≥ 0.10 (`vim.system`, `vim.uv`)
- `rclone` on `$PATH`
- `obsidian.nvim` on runtimepath — tests expect it at `/Users/acidsugarx/CODES/h/obsidian.nvim`
- No Lua dependencies beyond Neovim stdlib, no package manager needed

## Build & test

```
make chores        # lint + style + types + test — PRs must pass this
make lint          # selene
make style         # stylua --check
make types         # emmylua_check
make test          # mini.test (clones deps/mini.test on first run)
```

Under the hood:

```
nvim --headless --clean --noplugin -u tests/minimal_init.lua -c "lua MiniTest.run()"
```

Smoke test (requires rclone, hits real filesystem):

```
nvim --headless --clean -u scripts/smoke.lua
```

`deps/` is gitignored — `make test` bootstraps it on first run.

**Before committing**, run:

```
make chores   # style + lint + types + test — all must pass
```

## CI (GitHub Actions)

Three workflows on PR and push to main:

| Workflow | File | What it does |
|---|---|---|
| Linting | `.github/workflows/lint.yml` | selene (lint) + stylua --check (style) |
| Tests | `.github/workflows/test.yml` | mini.test on ubuntu (v0.10, v0.11, nightly), macos (v0.11), windows (v0.11) — installs rclone |
| Types | `.github/workflows/types.yml` | emmylua_check via Rust toolchain |

## Project structure

```
lua/obsidian-sync/
  init.lua         entry point — setup(), user commands, health, persist
  rclone.lua       rclone CLI wrapper — bisync_args, run_async, listremotes
  backend.lua      obsidian.sync.Backend contract — is_configured, sync_once, start, pause, …
  ui.lua           floating progress window with animated spinner
  statusline.lua   drop-in components for lualine/heirline/mini/feline/windline/plain
  health.lua       :checkhealth obsidian-sync (auto-discovered by Neovim)
tests/
  minimal_init.lua test bootstrap (rtp, mini.test setup)
  test_config.lua  defaults, persistence, path norm, commands
  test_backend.lua rclone args, backend contract fields, statusline, UI
scripts/
  smoke.lua        headless end-to-end: two-way local sync + conflict resolution
docs/              per-module reference (Sync, Setup, Statusline, Backends)
```

## Conventions (observed — do not deviate)

### Modules
- Every file starts with a `---` doc header summarising its purpose.
- `local M = {}` at top, `return M` at bottom.
- No `require`-ing external Lua libraries — only Neovim stdlib and sibling modules under `obsidian-sync.*` / `obsidian.*`.
- Section dividers: `-- ── section name ──` (Unicode box-drawing, 80-col).

### LuaDoc (mandatory — every public function)
Every public function MUST carry `---@param` and `---@return` annotations. Use `---@class`, `---@type`, `---@module` for module-level types. The existing codebase already follows this — do not degrade.

### Error handling
- `pcall(require, …)` for optional dependencies (obsidian.nvim, lualine, mini.statusline).
- `pcall` / nil-check for filesystem and system calls — the plugin must degrade gracefully when rclone is missing.
- Sync operations use async `vim.system` with `on_exit` callbacks; never block the UI.

### Path handling
- Normalise vault roots with `vim.uv.fs_realpath` → fallback `vim.fs.normalize(vim.fn.fnamemodify(…, ":p"))`.
- Remote keys in config are always canonical absolute paths — normalise on write and on lookup.

### Config
- Defaults live in `DEFAULT` table (init.lua) or inline (backend.lua).
- Merge: `vim.tbl_deep_extend("force", defaults, persisted, user_opts)`.
- Persistent state: `vim.fn.stdpath("data") .. "/obsidian-sync.json"` — round-trips through `vim.fn.json_encode`/`json_decode`, stripping non-serialisable keys (functions).

### Timers & async
- Continuous sync uses `vim.uv.new_timer()` with `vim.schedule_wrap` for callback scheduling.
- Timers are tracked per-vault in a `timers` table, cleaned up in `VimLeavePre`.

## Tooling config

- `.stylua.toml` — 2-space indent, double quotes, no call parens, 120 cols
- `.luarc.json` — LLS: LuaJIT runtime, `$VIMRUNTIME/lua/` + `./lua/`, globals `vim`/`MiniTest`/`Obsidian`
- `.emmyrc.json` — emmylua_check: LuaJIT, strict typeCall + arrayIndex, `$VIMRUNTIME` library
- `selene/config.toml` — lint reference `selene/globals.toml` (v51 base, permits globals `vim`/`bit`/`jit`/`Obsidian`/`MiniTest`)

## Pitfalls

- **`deps/mini.test` is a shallow clone** — `make test` clones it with `--filter=blob:none`. If tests fail with missing mini.test functions, run `rm -rf deps/mini.test && make test`.
- **Hardcoded obsidian.nvim path** in `tests/minimal_init.lua` and `scripts/smoke.lua` — points at `/Users/acidsugarx/CODES/h/obsidian.nvim`. Adjust if your checkout is elsewhere.
- **`running[cwd]` guard** in `sync_once` prevents overlapping syncs — debounce on `on_write` trigger will silently skip if a bisync is already in flight. This is deliberate; do not remove.
- **`initialized[cwd]` flag** gates `--resync` retry to first-ever sync. After a successful sync, bisync failures are real errors.
- **Statusline icons** use Nerd Font glyphs (`󰸞`, `󰑓`, `󰏤`, `󰅙`) — tests don't validate the glyph, only that the function returns a string.
