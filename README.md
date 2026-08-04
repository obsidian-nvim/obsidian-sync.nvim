# obsidian-sync.nvim

Bidirectional Obsidian vault sync for Neovim, backed by [rclone](https://rclone.org).
S3, WebDAV, Nextcloud, Dropbox, Google Drive, OneDrive, SFTP, SMB, local folders, and
every other remote rclone supports — the same feature set as the desktop
[Remotely Save](https://github.com/remotely-save/remotely-save) plugin, without the app.

It registers a `"rclone"` **sync backend** into [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim)'s
pluggable sync module (`require("obsidian.sync").register`), so **all existing obsidian.nvim
sync UX just works**: the `:Obsidian sync` menu, `Sync` statusline component, `on_write`
debounced trigger and continuous mode — no changes to obsidian.nvim required.

## Why rclone?

The honest answer to "can we do it with zero external deps?": **no.** Neovim's Lua exposes no
TLS (cloud storage is HTTPS-only) and no HMAC/crypto API, so a pure-Lua S3/WebDAV client is
not feasible. rclone is the one canonical tool that already solves multi-cloud bidirectional
sync (`bisync`) — installing it removes ~3000 lines of fragile cloud-client + OAuth code.
On macOS: `brew install rclone`.

## Requirements

- Neovim ≥ 0.10 (uses `vim.system` / `vim.uv`)
- [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) (community fork)
- `rclone` on `$PATH`

## Installation

```lua
-- lazy.nvim
{
  "obsidian-nvim/obsidian.nvim",
  lazy = true,
  opts = {
    sync = {
      enabled = true,
      backend = "rclone",
      trigger = "on_write", -- "on_write" | "continuous" | "manual"
    },
  },
},
{
  "dir/path/to/obsidian-sync.nvim", -- or a git remote
  dependencies = { "obsidian-nvim/obsidian.nvim" },
  config = function()
    require("obsidian-sync").setup {
      -- vault root -> rclone target ("remote:path" or an absolute local folder)
      remotes = {
        ["/path/to/my/vault"] = "s3:backups/my-vault",
      },
      check_interval = 300,  -- seconds between syncs in continuous mode
      auto_resync = true,    -- retry once with --resync if bisync asks for it
      -- extra rclone bisync flags
      bisync = {
        exclude = { ".trash/", "*.tmp" },
        args = { "--max-delete=20", "--fast-list" },
      },
    }
  end,
}
```

> Configure rclone remotes first with `rclone config` (S3, WebDAV, etc.). A local folder
> also works as a target for a zero-setup two-way test.

## Usage

Everything goes through the existing **`:Obsidian sync`** menu:

| Command | What it does |
|---|---|
| `:Obsidian sync` | open the sync menu (first run offers the setup wizard) |
| `:Obsidian sync setup` | wizard: pick existing rclone remote, run `rclone config`, or a local folder |
| `:Obsidian sync start` | run sync once per `check_interval` (continuous) |
| `:Obsidian sync pause` | stop the current sync |
| `:Obsidian sync sync` | one-shot sync now |
| `:Obsidian sync log` | open the per-session sync log |
| `:Obsidian sync disconnect` | unlink the vault |

Triggers (set via `sync.trigger` in obsidian.nvim opts):

- **`on_write`** — each saved note triggers a debounced one-shot sync (like Remotely Save).
- **`continuous`** — a timer runs `rclone bisync` every `check_interval` seconds.
- **`manual`** — only sync when you ask.

A `Sync` statusline component is already exported by obsidian.nvim:
`require("obsidian.sync.status").component` (see its docs).

## How it works

The plugin implements obsidian.nvim's `obsidian.sync.Backend` contract:

```
lua/obsidian-sync/
  rclone.lua     -- thin rclone CLI wrapper (bisync aware)
  backend.lua    -- the "rclone" Backend: start/pause/sync_once/setup/disconnect/log
  init.lua       -- setup(), config persistence, backend registration
```

`rclone bisync` is a one-shot process, so **continuous mode** is a `vim.uv` timer loop that
runs `bisync` each interval. One-shot syncs are run as async `vim.system` processes; output
streams into obsidian.nvim's existing sync log and statusline. Vault↔remote mappings persist to
`stdpath("data")/obsidian-sync.json` (wizard-created mappings survive restarts).

### Conflict behavior

`bisync` never silently drops data: on a divergent edit it keeps **both** versions as
`Note.md.conflict1` / `Note.md.conflict2` and logs the event, mirroring Remotely Save.

### First sync / resync

bisync sometimes refuses to start on a brand-new or previously-interrupted target and asks for
`--resync`. With `auto_resync = true` (default) the plugin retries once automatically — the
same "resync" Remotely Save does on first connect.

## License

MIT