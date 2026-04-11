local M = {}

local PREFIX = "[Restman]"

---Format message with prefix
---@param msg string Message to format
---@return string Formatted message
local function format(msg)
  return string.format("%s %s", PREFIX, msg)
end

---Log debug message
---@param msg string Debug message
function M.debug(msg)
  vim.notify(format(msg), vim.log.levels.DEBUG)
end

---Log info message
---@param msg string Info message
function M.info(msg)
  vim.notify(format(msg), vim.log.levels.INFO)
end

---Log warning message
---@param msg string Warning message
function M.warn(msg)
  vim.notify(format(msg), vim.log.levels.WARN)
end

---Log error message
---@param msg string Error message
function M.error(msg)
  vim.notify(format(msg), vim.log.levels.ERROR)
end

return M
