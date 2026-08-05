---@meta

---@class uv.uv_timer_t
local Timer = {}

---@param timeout integer
---@param repeat integer
---@param callback fun()
---@return integer 0 on success
function Timer:start(timeout, repeat_, callback) end

---@return integer
function Timer:stop() end

function Timer:close() end

local M = {}

---@return uv.uv_timer_t
function M.new_timer() end

---@param path string
---@return string|nil
function M.fs_realpath(path) end

return M
