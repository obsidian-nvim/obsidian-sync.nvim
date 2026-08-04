- [Commands](#commands)
- [Triggers](#triggers)
- [First sync & resync](#first-sync--resync)
- [Conflicts](#conflicts)
- [Statusline](#statusline)
- [Progress window](#progress-window)
- [Quirks](#quirks)
- [Options](#options)

The Sync module integrates with [rclone](https://rclone.org) to sync vaults to any supported cloud storage provider (WebDAV, S3, Dropbox, Nextcloud, Google Drive, SFTP, SMB, local folders, …).

You need `rclone` installed on `$PATH`, an obsidian.nvim workspace, and `sync.backend = "rclone"` in your obsidian.nvim config. After that, run `:Obsidian sync setup` (or the auto-wizard on first launch) to link your vault to a remote.

## Commands

### `:Obsidian sync`

Menu: start, pause, one-shot sync, setup wizard, disconnect, open log. On first run with no linked vaults, it offers the setup wizard.

### `:ObsidianSync`

Shortcut — jumps to the wizard if no vault is configured, to the menu otherwise.

### `:Obsidian sync setup`

Setup wizard (see [[docs/Setup]]). Three flows:

1. **WebDAV / Nextcloud** — enter URL + username + password; the plugin creates an rclone remote via `rclone config create ... webdav --obscure`.
2. **Existing rclone remote** — pick from `rclone listremotes`.
3. **Local folder** — two-way sync between two directories.

### `:ObsidianSyncHealth`

Print rclone version, linked vaults, obsidian.nvim status to the command line.

### `:checkhealth obsidian-sync`

Standard Neovim health check.

## Triggers

Set `sync.trigger` in obsidian.nvim:

| Value | Behavior |
|---|---|
| `"on_write"` | Debounced one-shot sync after each note save (2 s, configurable via `vim.g.obsidian_sync_on_write_debounce_ms`). The debounce coalesces rapid saves into a single bisync. |
| `"continuous"` | Start syncing when the workspace is set, then repeat every `check_interval` seconds. |
| `"manual"` | Sync only by calling `:Obsidian sync sync` / `:Obsidian sync start`. |

Overlapping calls (debounce triggers while a sync is already running) are silently skipped — the running bisync already covers the latest changes.

## First sync & resync

`rclone bisync` cannot run without a prior listing. The first time you sync a vault (or after an interrupted run), bisync asks you to run `--resync` to establish the baseline.

With `auto_resync = true` (default), the plugin detects this and retries with `--resync` automatically, logging a friendly notice.  The resync copies from **both** directions, so nothing is lost — it's a one-time alignment.

On subsequent runs the normal bisync is incremental and fast (10–20 seconds on a ~45 MB vault over WebDAV).

## Conflicts

`rclone bisync` never silently drops data:

| Situation | Outcome |
|---|---|
| File new on one side | Copied to the other side |
| File changed on one side | Copied to the other side |
| File changed on **both** sides | Keeps **both** as `name.md.conflict1` (local) and `name.md.conflict2` (remote) |
| File deleted on one side | Restored from the surviving side |

This matches Remotely Save's conflict behaviour exactly.

## Statusline

A `Sync` icon is available in the right section of your statusline (only in markdown buffers):

| Icon | Meaning | Highlight |
|---|---|---|
| `󰑓` | Syncing | `DiagnosticWarn` |
| `󰸞` | Synced | `DiagnosticOk` |
| `󰅙` | Error | `DiagnosticError` |
| `󰏤` | Paused | `DiagnosticInfo` |

Integrations are drop-in — see [[docs/Statusline]].

## Progress window

With `progress_win = true` (default), a floating window appears at the bottom of the editor during sync:

```
╭──── Obsidian Sync ────╮
│  ⠋  Syncing vault...
│
│   comparing files...
╰───────────────────────╯
```

On completion it briefly flashes `󰸞 Synced` (green) / `󰅙 Error` (red) and auto-closes after 1.5 s. Press `<Esc>` to dismiss immediately.

## Quirks

- The obsidian.nvim status module has a guard that blocks `paused → syncing` transitions. This plugin works around it.
- `rclone bisync` excludes its own `.bisync` metadata directory.  You should additionally exclude platform files (`.DS_Store`, `Thumbs.db`) via `bisync.exclude`.
- On macOS, `/var` and `/private/var` are the same path; the plugin normalises both sides with `uv.fs_realpath` so lookups always match.
- If you use both the Obsidian desktop app (with Remotely Save) and Neovim syncing to the same WebDAV, they will not conflict — both detect changes and bisync converges.  To avoid double work, disable Remotely Save in the desktop app.

## Options

```lua
---@class obsidian-sync.config
---@field remotes? table<string,string> vault root → rclone target
---@field check_interval? integer seconds between continuous syncs
---@field auto_resync? boolean retry with --resync on first connect
---@field safe_resync? boolean log a friendly notice on --resync
---@field notify_events? boolean vim.notify on sync start / complete
---@field progress_win? boolean floating spinner window during sync
---@field bisync? { exclude?: string[], args?: string[] }

require("obsidian-sync").setup {
  remotes = {},
  check_interval = 300,
  auto_resync = true,
  safe_resync = true,
  notify_events = true,
  progress_win = true,
  bisync = {
    exclude = { ".DS_Store", "*.bisync*", ".bisync/**" },
    args = {},
  },
}
```
