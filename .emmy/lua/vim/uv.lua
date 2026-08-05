---@meta

---@class uv.uv_timer_t
local Timer = {}
---@param timeout integer
---@param repeat_ integer
---@param callback fun()
function Timer:start(timeout, repeat_, callback) end
function Timer:stop() end
function Timer:close() end

---@type table<string, fun(...)>
vim.uv = {}

---@return uv.uv_timer_t
function vim.uv.new_timer() end

---@param path string
---@return string|nil
function vim.uv.fs_realpath(path) end
