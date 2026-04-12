local util = require("restman.parser.util")
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

---Check if a string looks like a URL
---Matches: http://, https://, or paths starting with /
---@param str string String to check
---@return boolean True if looks like a URL
local function looks_like_url(str)
  local trimmed = vim.trim(str)
  -- Check for http:// or https://
  if trimmed:match("^https?://") then
    return true
  end
  -- Check for path starting with /
  if trimmed:match("^/") then
    return true
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
--- - https://api.com/users (defaults to GET)
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
    -- No method found, check if this looks like a plain URL (default to GET)
    if looks_like_url(stripped) then
      method = "GET"
      url = stripped
    else
      return nil
    end
  end

  -- Validate that method is an HTTP verb
  if not is_valid_method(method) then
    return nil
  end

  -- Strip quotes from URL if present
  local clean_url = util.strip_quotes(url)

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
