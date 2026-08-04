# obsidian-sync.nvim

Bidirectional Obsidian vault sync for Neovim, backed by [rclone](https://rclone.org).
S3, WebDAV, Nextcloud, Dropbox, Google Drive, OneDrive, SFTP, SMB, local folders, and
every other remote rclone supports — the same feature set as the desktop
[Remotely Save](https://github.com/remotely-save/remotely-save) plugin, without the app.

Cross-platform: macOS, Linux, Windows.  The plugin delegates all network I/O to rclone,
which handles every cloud protocol and TLS.  No cloud-specific code is shipped.

It registers a `"rclone"` **sync backend** into [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim)'s
pluggable sync module (`require("obsidian.sync").register`), so **all existing obsidian.nvim
sync UX just works**: `:Obsidian sync` menu, `Sync` statusline component, `on_write`
debounced trigger and continuous mode — no changes to obsidian.nvim required.

## Requirements

- Neovim ≥ 0.10 (`vim.system` / `vim.uv`)
- [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) (community fork)
- `rclone` on `$PATH` — [install instructions](https://rclone.org/install/)
  - macOS: `brew install rclone`
  - Linux: `apt install rclone` / `pacman -S rclone`
  - Windows: `winget install rclone` or download from rclone.org

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
      -- triggers are backend-agnostic:
      trigger = "on_write", -- "on_write" | "continuous" | "manual"
    },
  },
},
{
  "your-user/obsidian-sync.nvim",
  dependencies = { "obsidian-nvim/obsidian.nvim" },
  config = function()
    require("obsidian-sync").setup {
      -- vault root -> rclone target ("remote:path" or an absolute local folder)
      remotes = {
        ["/path/to/my/vault"] = "s3:backups/my-vault",
      },
      check_interval = 300,  -- seconds between syncs in continuous mode
      auto_resync = true,    -- retry once with --resync on first connect
      safe_resync = true,    -- log a friendly notice on --resync (instead of ERROR)
      bisync = {
        exclude = { ".DS_Store", "*.bisync*", ".bisync/**" },
        args = {},  -- extra rclone bisync flags, e.g. { "--max-delete=20" }
      },
    }
  end,
}
```

### Mapping persists across restarts

Vault→remote mappings created through the setup wizard are saved to
`stdpath("data")/obsidian-sync.json`.  You can also edit this file directly.

## Usage

Everything goes through the existing **`:Obsidian sync`** menu:

| Command | What it does |
|---|---|
| `:Obsidian sync` | open the sync menu (first run offers the setup wizard) |
| `:Obsidian sync setup` | wizard — pick how to connect |
| `:Obsidian sync start` | continuous sync (bisync every `check_interval` seconds) |
| `:Obsidian sync pause` | stop current sync |
| `:Obsidian sync sync` | one-shot sync now |
| `:Obsidian sync log` | open the per-session sync log |
| `:Obsidian sync disconnect` | unlink the vault |

### Setup wizard — 3 ways to connect

1. **WebDAV / Nextcloud** — enter URL + username + password directly.  The plugin
   creates the rclone remote for you.  No manual `rclone config` required.
2. **Existing rclone remote** — pick from your `rclone.conf` (S3, SFTP, etc.).
3. **Local folder** — two-way sync between two directories on the same machine
   (useful for testing, or syncing with a mounted drive).

### Triggers

- **`on_write`** — every saved note triggers a debounced one-shot sync
  (2 s default, configurable via `vim.g.obsidian_sync_on_write_debounce_ms`).
- **`continuous`** — a timer runs `rclone bisync` every `check_interval` seconds.
- **`manual`** — only sync when you ask.

A `Sync` statusline component is exported by obsidian.nvim:
`require("obsidian.sync.status").component`.

## How it works under the hood

```
obsidian.nvim  sync  menu / triggers / statusline
                    │
                    ▼  register("rclone", backend)
     obsidian-sync.nvim  (backend.lua)
                    │
                    ▼  rclone bisync
     rclone  ── S3 / WebDAV / SFTP / ...
```

`rclone bisync` is a one-shot deterministic tool: it compares two directory
trees by size + modtime, copies differences bidirectionally, and on conflict
keeps **both** versions as `Note.md.conflict1` / `Note.md.conflict2` —
zero data loss, same behaviour as Remotely Save.

Continuous mode is a `vim.uv` timer loop that runs bisync each interval.
One-shot syncs run as async `vim.system` processes; output streams into
obsidian.nvim's sync log and statusline.

## Replacing Remotely Save

If you're migrating from the desktop [Remotely Save](https://github.com/remotely-save/remotely-save)
plugin:

1. Find your settings in `.obsidian/plugins/remotely-save/data.json`
2. Create the matching rclone remote (`rclone config create` or use the wizard)
3. Map your vault in `obsidian-sync.json` or via `setup()`:
   ```json
   { "remotes": { "/home/you/SECOND_BRAIN": "nc-secondbrain:" } }
   ```
4. Disable the Remotely Save plugin in the Obsidian desktop app (community plugins → toggle off)
5. Enable `trigger = "on_write"` in Neovim — now Neovim handles sync when you save

On mobile (iOS/Android Obsidian) you can keep Remotely Save if you need — both
sync to the same WebDAV, and the `--resync` on first connect handles the
baseline alignment automatically.

## License

MIT
