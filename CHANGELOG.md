# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `scripts/smoke.lua` now refuses to run without an isolated `XDG_DATA_HOME` —
  previously every run persisted its temp vault mappings into the user's real
  `obsidian-sync.json`.

## [v0.1.1] — 2026-09-19

### Fixed
- Stale `rclone bisync` lock files (left by a killed run) no longer wedge every
  sync: the lock's recorded PID is probed and a dead owner's lock is removed
  with an automatic retry; live-owner locks are reported with their PID and
  left alone. Previously such failures also triggered a pointless `--resync`
  retry.

## [v0.1.0] — 2026-08-06

### Added
- Initial release: bidirectional vault sync via rclone bisync
- WebDAV / Nextcloud setup wizard (no terminal required)
- Existing rclone remote picker
- Local folder two-way sync
- Floating progress window with animated spinner
- Statusline drop-ins for lualine, heirline, mini.statusline, feline, windline, plain vim
- `on_write`, `continuous`, and `manual` sync triggers
- Persistent vault→remote mappings (`stdpath("data")/obsidian-sync.json`)
- `:ObsidianSync` / `:ObsidianSyncHealth` commands
- `:checkhealth obsidian-sync` integration
- CI: lint (selene + stylua), types (emmylua_check), tests (mini.test on ubuntu/macos/windows)

[Unreleased]: https://github.com/obsidian-nvim/obsidian-sync.nvim/compare/v0.1.1...main
[v0.1.1]: https://github.com/obsidian-nvim/obsidian-sync.nvim/releases/tag/v0.1.1
[v0.1.0]: https://github.com/obsidian-nvim/obsidian-sync.nvim/releases/tag/v0.1.0
