-- Parser dispatcher module
-- Integrates HTTP-style, DSL, cURL parsers + directives + dynamic params + prompting

local M = {}

-- Load individual parsers and utilities
local curl_parser = require("restman.parser.curl")
local directives = require("restman.parser.directives")
local dsl_parser = require("restman.parser.dsl")
local http_parser = require("restman.parser.http")

-- Session cache for dynamic params: key = "file_path:param_name"
M._param_cache = {}

-- HTTP methods for prompting
local HTTP_METHODS =
  { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS", "CONNECT", "TRACE" }

-- Parser registry - dispatch order: cURL first (multi-line support), then HTTP-style, then DSL
local PARSERS = {
  {
    name = "curl",
    ---@diagnostic disable-next-line: duplicate-doc-field
    parse = function(lines_block, start_line, file_path)
      return curl_parser.parse(lines_block, start_line, file_path)
    end,
  },
  {
    name = "http",
    ---@diagnostic disable-next-line: duplicate-doc-field
    parse = function(lines_block, line_number, file_path)
      local line = type(lines_block) == "table" and lines_block[1] or lines_block
      return http_parser.parse(line, line_number, file_path)
    end,
  },
  {
    name = "dsl",
    ---@diagnostic disable-next-line: duplicate-doc-field
    parse = function(lines_block, line_number, file_path)
      local line = type(lines_block) == "table" and lines_block[1] or lines_block
      return dsl_parser.parse(line, line_number, file_path)
    end,
  },
}

---@class ParsedRequest
---@field method string HTTP method (uppercase)
---@field url string Request URL
---@field headers table<string, string> Request headers
---@field body? string|table Request body (nil by default)
---@field query? table<string, string> Query parameters from directives
---@field form? table<string, string> Form parameters from directives
---@field source RequestSource Source location info

---@class RequestSource
---@field file string Source file path
---@field line number Source line number (1-indexed)

---Scan lines below a request line for inline headers and body
---Reads header lines (Key: Value), a blank separator, then body content.
---Stops at separator lines (---/###), another request line, or end of buffer.
---@param bufnr number Buffer number
---@param start_line number Request line number (1-indexed)
---@return table headers Inline headers (key → value)
---@return string|nil body Body content or nil
local function scan_below(bufnr, start_line)
  local headers = {}
  local body_lines = {}
  local in_body = false
  local current_line = start_line + 1
  local total_lines = vim.api.nvim_buf_line_count(bufnr)

  while current_line <= total_lines do
    local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
    if not line_content then
      break
    end

    if not in_body then
      if line_content:match("^%s*$") then
        in_body = true
      elseif line_content:match("^[%w][%w%-]*:%s") then
        local key, value = line_content:match("^([%w][%w%-]*):%s*(.-)%s*$")
        if key then
          headers[key] = value or ""
        end
      else
        break
      end
    else
      if line_content:match("^%-%-%-") or line_content:match("^###") then
        break
      end
      local first_word = line_content:match("^%s*(%S+)")
      if first_word then
        local upper = first_word:upper()
        if
          upper == "GET"
          or upper == "POST"
          or upper == "PUT"
          or upper == "PATCH"
          or upper == "DELETE"
          or upper == "HEAD"
          or upper == "OPTIONS"
        then
          break
        end
      end
      table.insert(body_lines, line_content)
    end

    current_line = current_line + 1
  end

  while #body_lines > 0 and body_lines[#body_lines]:match("^%s*$") do
    body_lines[#body_lines] = nil
  end

  local body = #body_lines > 0 and table.concat(body_lines, "\n") or nil
  return headers, body
end

---Collect lines from buffer starting at start_line, following '\' continuations
---@param bufnr number Buffer number (0 for current)
---@param start_line number Starting line (1-indexed)
---@return string[] Array of lines, or empty if start_line is invalid
local function collect_block(bufnr, start_line)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  local lines = {}
  local current_line = start_line

  while true do
    local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]
    if not line_content then
      break
    end

    table.insert(lines, line_content)

    -- Check if line ends with backslash (multi-line continuation)
    if not line_content:match("\\%s*$") then
      break
    end

    current_line = current_line + 1
  end

  return lines
end

---Extract param names from URL
---Supports: :name, {name}, <name>, ${name}, #{name}
---@param url string URL string
---@return string[] Array of parameter names (may contain duplicates)
local function detect_params(url)
  local params = {}

  -- Pattern 1: :name (colon prefix)
  -- Skip port numbers (pure digits after colon, e.g., localhost:3000)
  for param in url:gmatch(":(%w+)") do
    -- Exclude pure numbers (likely ports)
    if not param:match("^%d+$") then
      table.insert(params, param)
    end
  end

  -- Pattern 2: {name} (curly braces)
  for param in url:gmatch("{(%w+)}") do
    table.insert(params, param)
  end

  -- Pattern 3: <name> (angle brackets)
  for param in url:gmatch("<(%w+)>") do
    table.insert(params, param)
  end

  -- Pattern 4: ${name} or #{name} (template literals)
  for param in url:gmatch("[%$#]{(%w+)}") do
    table.insert(params, param)
  end

  return params
end

---Resolve dynamic parameters in URL via prompts
---@param url string Request URL
---@param file_path string Source file path
---@param callback function Callback(resolved_url) when done
local function resolve_dynamic_params(url, file_path, callback)
  local params = detect_params(url)
  if #params == 0 then
    callback(url)
    return
  end

  -- Remove duplicates and maintain order
  local seen = {}
  local unique_params = {}
  for _, param in ipairs(params) do
    if not seen[param] then
      seen[param] = true
      table.insert(unique_params, param)
    end
  end

  -- Resolve parameters sequentially
  local resolved_values = {}
  local param_index = 1

  local function resolve_next()
    if param_index > #unique_params then
      -- All params resolved, substitute into URL
      local result_url = url
      for param, value in pairs(resolved_values) do
        result_url = result_url:gsub(":" .. param, value)
        result_url = result_url:gsub("{" .. param .. "}", value)
        result_url = result_url:gsub("<" .. param .. ">", value)
        result_url = result_url:gsub("%$" .. "{" .. param .. "}", value)
        result_url = result_url:gsub("#" .. "{" .. param .. "}", value)
      end
      callback(result_url)
      return
    end

    local param_name = unique_params[param_index]
    local cache_key = file_path .. ":" .. param_name
    local cached_value = M._param_cache[cache_key]

    vim.ui.input(
      { prompt = "Enter " .. param_name .. ": ", default = cached_value or "" },
      function(input)
        if input then
          resolved_values[param_name] = input
          M._param_cache[cache_key] = input
        end
        param_index = param_index + 1
        resolve_next()
      end
    )
  end

  resolve_next()
end

---Resolve dynamic parameters in a URL via prompts.
---@param url string
---@param file_path string
---@param callback function
function M.resolve_dynamic_params(url, file_path, callback)
  resolve_dynamic_params(url, file_path, callback)
end

---Prompt for HTTP method when URL is plain (no method detected)
---@param callback function Callback(method) when done
local function prompt_method(callback)
  vim.ui.select(HTTP_METHODS, { prompt = "Select HTTP method:" }, function(method)
    callback(method)
  end)
end

---Merge directives into parsed request
---@param request ParsedRequest Parsed request from sub-parser
---@param directives_result table Directives from scan_above
---@return ParsedRequest Updated request
local function merge_directives(request, directives_result)
  if not directives_result then
    return request
  end

  -- Merge headers (directive overrides)
  if directives_result.headers then
    for key, value in pairs(directives_result.headers) do
      request.headers[key] = value
    end
  end

  -- Copy query params
  if directives_result.query then
    request.query = directives_result.query
  end

  -- Copy form params
  if directives_result.form then
    request.form = directives_result.form
  end

  -- Handle body precedence: visual > directive > existing (don't override if already set)
  if directives_result.body and not request.body then
    request.body = directives_result.body
  end

  return request
end

---Parse request from current line in buffer
---Dispatches to sub-parsers (cURL > HTTP-style > DSL), merges directives,
---handles body precedence, resolves dynamic params, and prompts as needed.
---
---@param bufnr number Buffer number (0 for current)
---@param line number Line number (1-indexed) of request line
---@param opts table Options table:
---  - visual_block: string|nil Visual block content (highest body precedence)
---  - file_path: string|nil Override source file path (default: buffer name)
---@param callback function Callback(request) when parsing complete; receives nil if no match
function M.parse_current_line(bufnr, line, opts, callback)
  if not bufnr or bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end

  opts = opts or {}
  local file_path = opts.file_path or vim.api.nvim_buf_get_name(bufnr)

  -- Validate line number
  if not line or line < 1 then
    callback(nil)
    return
  end

  -- Collect block (for cURL multi-line support)
  local block = collect_block(bufnr, line)
  if #block == 0 then
    callback(nil)
    return
  end

  -- Try parsers in order
  local request = nil
  for _, parser in ipairs(PARSERS) do
    local success, result = pcall(parser.parse, block, line, file_path)
    if success and result then
      request = result
      break
    end
  end

  if not request then
    callback(nil)
    return
  end

  -- Ensure headers table exists
  if not request.headers then
    request.headers = {}
  end

  -- Read inline headers and body from lines below the request line
  -- (precedence: directives above > inline below)
  local inline_headers, inline_body = scan_below(bufnr, line)
  for key, value in pairs(inline_headers) do
    request.headers[key] = value
  end
  if inline_body and not request.body then
    request.body = inline_body
  end

  -- Scan directives above the request line (take precedence over inline)
  local directives_result = directives.scan_above(bufnr, line)
  request = merge_directives(request, directives_result)

  -- Handle body precedence
  if opts.visual_block then
    request.body = opts.visual_block
  elseif
    not request.body
    and (request.method == "POST" or request.method == "PUT" or request.method == "PATCH")
  then
    -- Need to prompt for body
    vim.ui.input({ prompt = "Enter request body (JSON): " }, function(body_input)
      if body_input and body_input ~= "" then
        request.body = body_input
      end
      resolve_dynamic_params(request.url, file_path, function(resolved_url)
        request.url = resolved_url
        callback(request)
      end)
    end)
    return
  end

  -- Check if method is missing (plain URL in string)
  if not request.method or request.method == "" then
    prompt_method(function(method)
      if method then
        request.method = method
      end
      resolve_dynamic_params(request.url, file_path, function(resolved_url)
        request.url = resolved_url
        callback(request)
      end)
    end)
    return
  end

  -- Resolve dynamic params and return
  resolve_dynamic_params(request.url, file_path, function(resolved_url)
    request.url = resolved_url
    callback(request)
  end)
end

---Legacy sync parse function for backward compatibility
---Try to parse a line or block of lines using all registered parsers
---@param lines string|string[] Single line or array of lines (for multi-line cURL)
---@param line_number number Starting line number (1-indexed)
---@param file_path string Source file path
---@return ParsedRequest|nil Parsed request or nil if no match
function M.parse(lines, line_number, file_path)
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
