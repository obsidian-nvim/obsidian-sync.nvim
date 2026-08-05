---@meta

local M = {}

---@class obsidian.sync.status.State
---@field kind string
---@field icon string
---@field need_update boolean

---@type obsidian.sync.status.State
M.state = { kind = "paused", icon = "󰏤", need_update = false }

---@param kind string "synced"|"syncing"|"paused"|"error"
function M.set(kind) end

---@return string
function M.icon() end

---@return string
function M.color() end

---@return string
function M.component() end

return M
