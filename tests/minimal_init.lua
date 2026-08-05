-- Bootstrap for running mini.test-based tests.
-- Usage:
--   nvim --headless --clean -u tests/minimal_init.lua -c "lua MiniTest.run()"

local cwd = vim.fn.getcwd()

-- Ensure mini.test is available
local mini_test_dir = cwd .. "/deps/mini.test"
if vim.fn.isdirectory(mini_test_dir) == 0 then
  vim.fn.system { "git", "clone", "--filter=blob:none", "https://github.com/echasnovski/mini.test", mini_test_dir }
end

-- obsidian.nvim: try CI path (cloned by workflow), fall back to local checkout
local obsidian_path = cwd .. "/deps/obsidian.nvim"
if vim.fn.isdirectory(obsidian_path) == 0 then
  obsidian_path = "/Users/acidsugarx/CODES/h/obsidian.nvim"
end

vim.opt.runtimepath:prepend(mini_test_dir)
vim.opt.runtimepath:prepend(obsidian_path)
vim.opt.runtimepath:prepend(cwd)

-- Minimal Neovim settings
vim.cmd [[set rtp+=.]]
vim.o.swapfile = false
vim.bo.swapfile = false
vim.o.swapfile = false

-- Load mini.test
local MiniTest = require "mini.test"
MiniTest.setup()

-- Global mocks registry for tests to use
_G.__obsidian_sync_mocks = {}
