---@meta

local M = {}

---@param dir string
---@return fun(err: string?, data: string?)
function M.make_handler(dir) end

---@param dir string
---@param message string
---@param opts? { error?: boolean }
function M.append_log(dir, message, opts) end

---@param dir string
function M.open_log_buf(dir) end

---@param dir string
function M.clear_notify_state(dir) end

---@type table<string, string[]>
M.logs = {}

return M
