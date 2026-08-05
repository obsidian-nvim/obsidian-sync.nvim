---@meta

---@class obsidian.sync.Backend
---@field name string
---@field caps table<string,boolean>
---@field is_configured fun(ws: obsidian.Workspace, cache?: any): boolean
---@field sync_once fun(dir: string, opts?: { silent?: boolean })
---@field start fun(dir: string, opts?: { silent?: boolean })
---@field pause fun(dir: string): boolean
---@field setup fun(ws: obsidian.Workspace)
---@field disconnect fun(ws: obsidian.Workspace)
---@field log fun(dir: string)
---@field ws_formatter fun(ws: obsidian.Workspace): string

local M = {}

---@param name string
---@param backend obsidian.sync.Backend
function M.register(name, backend) end

---@return obsidian.sync.Backend|nil
function M.get_backend() end

---Open the sync menu.
function M.menu() end

---Open the setup wizard.
function M.setup() end

---Run a one-shot sync.
function M.sync_once() end

---Start continuous sync.
function M.start() end

---Check if a workspace is configured for sync.
---@param ws obsidian.Workspace
---@return boolean
function M.is_configured(ws) end

return M
