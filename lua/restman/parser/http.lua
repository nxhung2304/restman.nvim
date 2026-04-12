local M = {}

---HTTP request method names
local HTTP_METHODS = {
  "GET",
  "POST",
  "PUT",
  "PATCH",
  "DELETE",
  "HEAD",
  "OPTIONS",
  "CONNECT",
  "TRACE",
}

---Pattern to match HTTP-style prefix: METHOD URL
---Supports quoted or bare URLs, case-insensitive methods
local PATTERN = "^(%S+)%s+(.+)$"

---@class Request
---@field method string HTTP method (uppercase)
---@field url string Request URL
---@field headers table<string, string> Request headers (empty by default)
---@field body? string Request body (nil by default)
---@field source RequestSource Source location info

---@class RequestSource
---@field file string Source file path
---@field line number Source line number (1-indexed)

---Strip quotes from a string if wrapped in single or double quotes
---@param str string String to strip quotes from
---@return string String with quotes removed if present
local function strip_quotes(str)
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

---Check if a string is a valid HTTP method (case-insensitive)
---@param method_str string String to check
---@return boolean True if valid HTTP method
local function is_valid_method(method_str)
  local upper = string.upper(method_str)
  for _, method in ipairs(HTTP_METHODS) do
    if upper == method then
      return true
    end
  end
  return false
end

---Parse a line as HTTP-style request (METHOD URL)
---Returns nil if line does not match the pattern
---Accepts:
--- - GET https://api.com/users
--- - POST /users
--- - delete '/api/x'
--- - # GET /api/v1/users/42 (comment lines are still parsed if pattern matches)
---
---@param line string Line to parse
---@param line_number number Line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
function M.parse(line, line_number, file_path)
  if not line or line == "" then
    return nil
  end

  -- Strip leading comment marker (#) to support comment lines with patterns
  local stripped = line:gsub("^%s*#%s*", "", 1)

  -- Try to match METHOD URL pattern
  local method, url = stripped:match(PATTERN)
  if not method or not url then
    return nil
  end

  -- Validate that method is an HTTP verb
  if not is_valid_method(method) then
    return nil
  end

  -- Strip quotes from URL if present
  local clean_url = strip_quotes(url)

  -- Return parsed request structure
  return {
    method = string.upper(method),
    url = clean_url,
    headers = {},
    body = nil,
    source = {
      file = file_path,
      line = line_number,
    },
  }
end

return M
