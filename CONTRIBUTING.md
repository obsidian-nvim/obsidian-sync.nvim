# Contributing to `obsidian-sync.nvim`

Thanks for considering contributing! Here's what you need to know before submitting a pull request.

## TL;DR

- Open an issue to discuss planned changes first
- Branch, develop, then:
  ```
  make chores   # style + lint + types + test — all must pass
  ```
- A PR must include:
  - Code changes with `---@param` / `---@return` annotations
  - Tests (if applicable)
  - `CHANGELOG.md` entry under `[Unreleased]`

## Details

All automation lives in the `Makefile`. Run `make help` to see available targets.

### Before committing

```bash
make chores   # runs: style → lint → types → test
```

CI runs the same checks on every PR, but run them locally first.

### Keeping `CHANGELOG.md` up-to-date

We use [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.
Every PR that changes `lua/**` must add an entry under `[Unreleased]`:

```markdown
## [Unreleased]

### Added
- New feature description

### Fixed
- Bug description
```

CI will fail the PR if `CHANGELOG.md` wasn't touched.

### Formatting code

```bash
make style   # stylua --check
```

Uses [StyLua](https://github.com/JohnnyMorganz/StyLua) with 2-space indent,
double quotes, no call parentheses. The `.stylua.toml` at the repo root has
the exact config.

### Linting code

```bash
make lint    # selene
```

Uses [selene](https://github.com/Kampfkarren/selene) with a Neovim-aware
config in `selene/`. Allowed globals: `vim`, `bit`, `jit`, `Obsidian`,
`MiniTest`, `_G`.

### Checking types

```bash
make types   # emmylua_check
```

Every public function must have `---@param` / `---@return` annotations.
Type definitions live in `.emmy/lua/vim/` for Neovim internals; obsidian.nvim
types are resolved by cloning the upstream repo (CI does this automatically).

### Running tests

```bash
make test    # mini.test (headless Neovim)
```

Tests live in `tests/` and use [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md).
The make target auto-clones `mini.test` into `deps/`.

### CI

Three jobs run on every PR (`.github/workflows/ci.yml`):

| Job | What |
|---|---|
| `lint` | selene + stylua --check |
| `types` | emmylua_check (clones obsidian.nvim for type resolution) |
| `test` | mini.test on ubuntu (v0.10, v0.11, nightly), macos, windows |

### Releasing

On tag push (`v*.*.*`), GitHub Actions generates release notes from
`CHANGELOG.md` + commit history and publishes a GitHub Release. Users
install tagged versions via lazy.nvim:

```lua
{ "obsidian-nvim/obsidian-sync.nvim", tag = "v0.1.0" }
```
