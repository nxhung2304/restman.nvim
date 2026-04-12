local util = require("restman.parser.util")
local M = {}

---HTTP request method names (lowercase for DSL matching)
local DSL_METHODS = {
  "get",
  "post",
  "put",
  "patch",
  "delete",
  "head",
  "options",
}

---Pattern to match Rails/Sinatra DSL: method 'url' or method "url" or method `url`
---Examples: get '/users', post "/login", delete `items/:id`
local RAILS_PATTERN = "^%s*([%w]+)[%s%(]+(['\"`])([^%'\"`]+)%2"

---Pattern to match Express DSL: obj.method('url') or obj.method("url") or obj.method(`url`)
---Examples: router.get('/x'), app.post("/y"), api.delete(`z`)
local EXPRESS_PATTERN_SINGLE = "^%s*([%w%.]+)[%.]([%w]+)%((['])([^']+)%3%)"
local EXPRESS_PATTERN_DOUBLE = "^%s*([%w%.]+)[%.]([%w]+)%(([\"])([^\"]+)%3%)"
local EXPRESS_PATTERN_BACKTICK = "^%s*([%w%.]+)[%.]([%w]+)%((`)([^`]+)%3%)"

---@class Request
---@field method string HTTP method (uppercase)
---@field url string Request URL
---@field headers table<string, string> Request headers (empty by default)
---@field body? string Request body (nil by default)
---@field source RequestSource Source location info

---@class RequestSource
---@field file string Source file path
---@field line number Source line number (1-indexed)

---Check if a string is a valid DSL method (case-insensitive)
---@param method_str string String to check
---@return boolean True if valid DSL method
local function is_valid_dsl_method(method_str)
  local lower = string.lower(method_str)
  for _, method in ipairs(DSL_METHODS) do
    if lower == method then
      return true
    end
  end
  return false
end

---Parse a line as Rails/Sinatra DSL route
---Returns nil if line does not match the pattern
---
---@param line string Line to parse
---@param line_number number Line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
local function parse_rails_dsl(line, line_number, file_path)
  local method, _, url = line:match(RAILS_PATTERN)
  if not method or not url then
    return nil
  end

  -- Validate that method is exactly an HTTP verb (word boundary)
  -- This prevents matching getUser, get_user, etc.
  if not is_valid_dsl_method(method) then
    return nil
  end

  -- Strip quotes from URL if present
  local clean_url = util.strip_quotes(url)

  -- Validate URL is not empty
  if not clean_url or clean_url == "" then
    return nil
  end

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

---Parse a line as Express DSL route
---Returns nil if line does not match the pattern
---
---@param line string Line to parse
---@param line_number number Line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
local function parse_express_dsl(line, line_number, file_path)
  -- Try single quote pattern first
  local obj, method, _, url = line:match(EXPRESS_PATTERN_SINGLE)
  -- Try double quote pattern
  if not obj or not method or not url then
    obj, method, _, url = line:match(EXPRESS_PATTERN_DOUBLE)
  end
  -- Try backtick pattern
  if not obj or not method or not url then
    obj, method, _, url = line:match(EXPRESS_PATTERN_BACKTICK)
  end

  if not obj or not method or not url then
    return nil
  end

  -- Validate that method is exactly an HTTP verb (word boundary)
  if not is_valid_dsl_method(method) then
    return nil
  end

  -- Strip quotes from URL if present
  local clean_url = util.strip_quotes(url)

  -- Validate URL is not empty
  if not clean_url or clean_url == "" then
    return nil
  end

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

---Parse a line as DSL route (Rails/Sinatra or Express)
---Returns nil if line does not match any known pattern
---
---Accepts:
--- - Rails/Sinatra: get '/users', post "/login", delete `items/:id`
--- - Express: router.get('/x'), app.post("/y"), api.delete(`z`)
---
---Word boundary enforcement: getUser('/x') → nil (not a verb)
---
---@param line string Line to parse
---@param line_number number Line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
function M.parse(line, line_number, file_path)
  if not line or line == "" then
    return nil
  end

  -- Try Rails/Sinatra pattern first
  local result = parse_rails_dsl(line, line_number, file_path)
  if result then
    return result
  end

  -- Try Express pattern
  result = parse_express_dsl(line, line_number, file_path)
  if result then
    return result
  end

  return nil
end

return M
