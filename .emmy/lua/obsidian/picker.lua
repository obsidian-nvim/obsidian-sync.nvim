---@meta

local M = {}

---@param items string[]
---@param opts { prompt: string, format_item: fun(item: string): string }
---@param callback fun(choices: string[])
function M.select(items, opts, callback) end

return M
