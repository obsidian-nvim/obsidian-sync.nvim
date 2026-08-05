---@meta

local M = {}

---@param prompt string
---@return string|nil
function M.input(prompt) end

---@param question string
---@return "Yes"|"No"
function M.confirm(question) end

return M
