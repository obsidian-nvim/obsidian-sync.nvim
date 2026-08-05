---@meta

---@class vim.SystemCompleted
---@field code integer
---@field signal integer
---@field stdout string
---@field stderr string

---@class vim.SystemObj
local SystemObj = {}
---@return integer
function SystemObj:kill(signal) end
---@return vim.SystemCompleted
function SystemObj:wait(timeout) end
