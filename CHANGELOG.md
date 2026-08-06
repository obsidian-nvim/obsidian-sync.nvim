# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
