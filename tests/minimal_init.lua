-- Add current directory to 'runtimepath' to be able to use 'lua' files
vim.opt.rtp:append(vim.uv.cwd())
-- Add 'mini.test' from deps (cloned by Makefile)
vim.opt.rtp:append "deps/mini.test"
-- Add 'obsidian.nvim' from deps (cloned by Makefile)
vim.opt.rtp:append "deps/obsidian.nvim"

-- Set up 'mini.test'
require("mini.test").setup()

-- Global mocks registry for tests to use
_G.__obsidian_sync_mocks = {}
