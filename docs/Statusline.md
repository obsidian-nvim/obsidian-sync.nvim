- [Quick reference](#quick-reference)
- [lualine.nvim](#lualinenvim)
- [heirline.nvim](#heirlinenvim)
- [mini.statusline](#ministatusline)
- [feline.nvim](#felinenvim)
- [windline.nvim](#windlinenvim)
- [Plain vim statusline](#plain-vim-statusline)
- [Auto-refresh](#auto-refresh)

The sync status icon is available as a drop-in component for every popular statusline plugin — and plain vim statusline — via `require("obsidian-sync.statusline")`.  The icon only appears in **markdown buffers** when a sync backend is active.

## Quick reference

| Icon | Meaning | Highlight group |
|---|---|---|
| `󰑓` | Syncing | `ObsidianSyncSyncing` (→ `DiagnosticWarn`) |
| `󰸞` | Synced | `ObsidianSyncSynced` (→ `DiagnosticOk`) |
| `󰅙` | Error | `ObsidianSyncError` (→ `DiagnosticError`) |
| `󰏤` | Paused | `ObsidianSyncPaused` (→ `DiagnosticInfo`) |

The highlight groups are defined by obsidian.nvim.  The raw component is also available from `require("obsidian.sync.status")`.

## lualine.nvim

```lua
require("lualine").setup {
  sections = {
    lualine_x = {
      require("obsidian-sync.statusline").lualine(),
      -- ... other components
    },
  },
}
```

The component is clickable — opens `:ObsidianSync`.

## heirline.nvim

```lua
{
  require("obsidian-sync.statusline").heirline(),
}
```

Uses `update = { "User", pattern = "ObsidianSyncChanged" }` for auto-refresh.

## mini.statusline

```lua
local sync_provider = require("obsidian-sync.statusline").mini()

require("mini.statusline").setup {
  content = {
    active = {
      -- ... your sections ...
      sync_provider,
    },
  },
}
```

To auto-refresh, add to your config:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianSyncChanged",
  callback = function()
    require("mini.statusline").refresh()
  end,
})
```

## feline.nvim

```lua
{
  require("obsidian-sync.statusline").feline(),
}
```

## windline.nvim

```lua
{
  require("obsidian-sync.statusline").windline(),
}
```

## Plain vim statusline

```lua
-- refresh helper
vim.api.nvim_create_autocmd("User", {
  pattern = "ObsidianSyncChanged",
  command = "redrawstatus",
})

vim.o.statusline = "%f %= " ..
  require("obsidian-sync.statusline").plain() ..
  " %l/%L"
```

Returns a format string like `%#ObsidianSyncSynced# 󰸞 %*` for use in `vim.o.statusline`.

## Auto-refresh

The statusline module auto-creates a `User ObsidianSyncChanged` autocmd that calls `lualine.refresh()`, `mini.statusline.refresh()`, `feline.reset_highlights()`, and `redrawstatus` — so the icon updates automatically when the sync state changes.  No additional config needed for lualine; mini.statusline needs a one-line hook as shown above.
