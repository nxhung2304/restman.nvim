-- Shared utility functions for parsers

local M = {}

---Strip quotes from a string if wrapped in single or double quotes
---@param str string String to strip quotes from
---@return string String with quotes removed if present
function M.strip_quotes(str)
  local trimmed = vim.trim(str)
  -- Check for double quotes
  if string.sub(trimmed, 1, 1) == '"' and string.sub(trimmed, -1) == '"' then
    return string.sub(trimmed, 2, -2)
  end
  -- Check for single quotes
  if string.sub(trimmed, 1, 1) == "'" and string.sub(trimmed, -1) == "'" then
    return string.sub(trimmed, 2, -2)
  end
  return trimmed
end

return M
