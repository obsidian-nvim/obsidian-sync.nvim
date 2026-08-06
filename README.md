<!--markdoc_ignore_start-->
<h1 align="center">obsidian-sync.nvim</h1>

<div align="center">
<a href="https://github.com/obsidian-nvim/obsidian.nvim">
  <img alt="Requires obsidian.nvim" src="https://img.shields.io/badge/requires-obsidian.nvim-d9b3ff?style=for-the-badge&logo=obsidian&logoColor=D9E0EE&labelColor=302D41&color=d9b3ff" />
</a>
<a href="https://rclone.org">
  <img alt="Backed by rclone" src="https://img.shields.io/badge/engine-rclone-9fdf9f?style=for-the-badge&logo=rclone&logoColor=D9E0EE&labelColor=302D41&color=9fdf9f" />
</a>
<a href="https://github.com/neovim/neovim/releases/latest">
  <img alt="Latest Neovim" src="https://img.shields.io/badge/v0.10+-99d6ff?style=for-the-badge&logo=neovim&logoColor=D9E0EE&label=Neovim&labelColor=302D41&color=99d6ff" />
</a>
</div>
<hr>
<!--markdoc_ignore_end-->

Bidirectional vault sync for Neovim — **WebDAV / Nextcloud / S3 / Dropbox / Google Drive** and every other [rclone](https://rclone.org) remote.  The same feature set as the [Remotely Save](https://github.com/remotely-save/remotely-save) desktop plugin, without the app.

Registers as a **sync backend** into [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) via its public `register()` API, so `:Obsidian sync`, `on_write`, continuous mode, statusline and the menu picker all work with zero changes to obsidian.nvim.

## ⭐ Features

🌐 **Any remote:** WebDAV, Nextcloud/ownCloud, S3, Dropbox, Google Drive, OneDrive, SFTP, SMB, local folders — rclone handles every protocol and TLS, no cloud-specific code shipped.

🔄 **Bidirectional sync:** `rclone bisync` — deterministic two-way sync by size + modtime.  No silent data loss: conflicts produce `Note.md.conflict1` / `Note.md.conflict2`.

🧙 **Setup wizard in Neovim:** enter your WebDAV URL and credentials directly, the rclone remote is created automatically.  No terminal required.

⚡ **Three triggers:** `on_write` — debounced sync on save (2 s).  `continuous` — timer loop every N seconds.  `manual` — only when you ask.

📊 **Floating progress window:** animated spinner, green checkmark / red error, auto-closes.  Mirroring the UX of lazy.nvim / mason.nvim.

📏 **Statusline component:** drop-in for lualine, heirline, mini.statusline, feline, windline, or plain vim statusline.  Auto-refreshes via `User ObsidianSyncChanged`.

💾 **Persistent config:** vault→remote mappings survive restarts (`stdpath("data")/obsidian-sync.json`).  Passwords live only in `rclone.conf` (obscured).

🧪 **Tested:** 23 unit tests via `mini.test`, headless smoke test against real Nextcloud WebDAV.

🖥️ **Cross-platform:** macOS, Linux, Windows.  rclone is the only binary dependency.

## 📦 Requirements

- Neovim ≥ 0.10 (`vim.system` / `vim.uv`)
- [obsidian.nvim](https://github.com/obsidian-nvim/obsidian.nvim) (community fork)
- `rclone` on `$PATH` — [install](https://rclone.org/install/)
  - macOS: `brew install rclone`
  - Linux: `apt install rclone` / `pacman -S rclone`
  - Windows: `winget install rclone`

## 🚀 Quick start

```lua
-- lazy.nvim
{
  "obsidian-nvim/obsidian.nvim",
  lazy = true,
  opts = {
    workspaces = { { name = "vault", path = "~/my-vault" } },
    sync = { enabled = true, backend = "rclone", trigger = "on_write" },
  },
  dependencies = {
    {
      "your-user/obsidian-sync.nvim",
      config = function()
        require("obsidian-sync").setup()
      end,
    },
  },
}
```

Open a markdown file → `:Obsidian sync setup` (or the auto-wizard on first run) → pick `WebDAV / Nextcloud` → enter URL + credentials → done.  Saving a note triggers sync.

## 🕹️ Commands

### `:Obsidian sync`

Menu: start, pause, one-shot sync, setup wizard, disconnect, open log.

### `:ObsidianSync`

Shortcut — opens the setup wizard if no vault is linked, the menu otherwise.

### `:ObsidianSyncHealth`

Diagnostics: rclone version, linked vaults, obsidian.nvim status.

### `:checkhealth obsidian-sync`

Standard Neovim health check (auto-discovered from `health.lua`).

## 📁 Documentation

| Doc | Content |
|---|---|
| [Sync](docs/Sync.md) | Full sync reference: triggers, options, conflicts, quirks |
| [Setup](docs/Setup.md) | Setup wizard walkthrough — WebDAV, existing remotes, local folders |
| [Statusline](docs/Statusline.md) | Drop-in integrations for lualine / heirline / mini / feline / windline |
| [Backends](docs/Backends.md) | How to write a custom sync backend |

## ⚙️ Options

```lua
require("obsidian-sync").setup {
  -- vault root → rclone target
  remotes = { ["/path/to/vault"] = "s3:my-bucket/vault" },

  -- seconds between syncs in continuous mode
  check_interval = 300,

  -- retry once with --resync on first connect
  auto_resync = true,

  -- log a friendly notice on --resync (instead of ERROR)
  safe_resync = true,

  -- show vim.notify on sync start / complete
  notify_events = true,

  -- show floating spinner window during sync
  progress_win = true,

  -- show per-file detail in progress window (\"12 files · note.md\")
  verbose_progress = false,

  -- rclone bisync flags
  bisync = {
    exclude = { ".DS_Store", "*.bisync*", ".bisync/**" },
    args = {},       -- e.g. { "--max-delete=20", "--fast-list" }
  },
}
```

## 🔧 How it works

```
obsidian.nvim  sync menu / triggers / statusline
                    │
                    ▼  sync.register("rclone", backend)
     obsidian-sync.nvim  (backend.lua)
                    │
                    ▼  rclone bisync
     rclone  ── S3 / WebDAV / SFTP / ...
```

`rclone bisync` is a one-shot deterministic tool that compares two directory trees by size + modtime, copies differences in both directions, and on conflict keeps **both** versions — zero data loss, same behaviour as Remotely Save.

The plugin implements obsidian.nvim's `obsidian.sync.Backend` contract — `start`, `pause`, `sync_once`, `setup`, `disconnect`, `log`, `ws_formatter`.  The contract is public; you can write your own backend with `require("obsidian.sync").register("my-name", my_backend)`.

Continuous mode is a `vim.uv` timer loop that runs bisync each interval.  One-shot syncs run as async `vim.system` processes; rclone output streams into obsidian.nvim's sync log and updates its statusline component.

## 🧪 Tests

```bash
make test   # downloads mini.test, runs 23 unit tests headless
```

## 📄 License

MIT
