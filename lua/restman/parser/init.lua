-- Parser module
-- Integrates HTTP-style and cURL parsers

local M = {}

-- Load individual parsers
local http_parser = require("restman.parser.http")
local curl_parser = require("restman.parser.curl")

-- Parser registry for future extensibility
local PARSERS = {
  {
    name = "http",
    ---@diagnostic disable-next-line: duplicate-doc-field
    parse = function(line, line_number, file_path)
      return http_parser.parse(line, line_number, file_path)
    end,
  },
  {
    name = "curl",
    ---@diagnostic disable-next-line: duplicate-doc-field
    parse = function(lines_block, start_line, file_path)
      return curl_parser.parse(lines_block, start_line, file_path)
    end,
  },
}

---@class Request
---@field method string HTTP method (uppercase)
---@field url string Request URL
---@field headers table<string, string> Request headers (empty by default)
---@field body? string Request body (nil by default)
---@field source RequestSource Source location info

---@class RequestSource
---@field file string Source file path
---@field line number Source line number (1-indexed)

---Try to parse a line or block of lines using all registered parsers
---Returns the first successful parse result, or nil if no parser matches
---@param lines string|string[] Single line or array of lines (for multi-line cURL)
---@param line_number number Starting line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
function M.parse(lines, line_number, file_path)
  -- Normalize input to array
  local lines_block
  if type(lines) == "string" then
    lines_block = { lines }
  else
    lines_block = lines
  end

  if not lines_block or #lines_block == 0 then
    return nil
  end

  -- Try each parser in order
  for _, parser in ipairs(PARSERS) do
    local success, result = pcall(parser.parse, lines_block, line_number, file_path)
    if success and result then
      return result
    end
  end

  -- No parser matched
  return nil
end

---Get list of registered parser names
---@return string[] Parser names
function M.list_parsers()
  local names = {}
  for _, parser in ipairs(PARSERS) do
    table.insert(names, parser.name)
  end
  return names
end

return M
