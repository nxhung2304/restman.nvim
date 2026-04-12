-- Parser for @restman.* comment directives
-- Scans comment block above request line to extract directives
--
-- Example:
--   -- @restman.body { "name": "Alice" }
--   -- @restman.header X-Trace-Id: abc-123
--   POST http://localhost:3000/users
--
-- Supported directives:
--   @restman.body     — JSON body (single or multi-line)
--   @restman.header   — Add header (Key: Value format)
--   @restman.query    — Add query param (key=value format)
--   @restman.form     — Add form param (key=value format)

local M = {}

-- Constants
-- Hard limit from spec: scan up to 20 lines above request (specs/issues/005-parser-directives.md line 22)
local MAX_SCAN_LINES = 20

-- Directive patterns
local PATTERN_BODY = "^@restman%.body%s*(.*)"
local PATTERN_HEADER = "^@restman%.header%s+([^:]+):%s*(.*)"
local PATTERN_QUERY = "^@restman%.query%s+([^=]+)=(.*)"
local PATTERN_FORM = "^@restman%.form%s+([^=]+)=(.*)"

-- Comment prefix patterns
local COMMENT_PREFIXES = {
  "^%s*%/%/",  -- // (JS)
  "^%s*#",     -- # (Python/Ruby)
  "^%s*%-%-",  -- -- (Lua)
  "^%s*/%*",   -- /* (C block start)
  "^%s*%*",    -- * (C block middle)
}

---Check if a string is blank (whitespace only)
---@param str string String to check
---@return boolean True if blank
local function is_blank(str)
  return str:match("^%s*$") ~= nil
end

---Trim whitespace from both ends of a string
---@param str string String to trim
---@return string Trimmed string
local function trim(str)
  return vim.trim(str)
end

---@class Directives
---@field body? table|string Parsed body as table (if JSON) or raw string
---@field headers? table<string, string> Headers from directives
---@field query? table<string, string> Query parameters
---@field form? table<string, string> Form-urlencoded parameters

---Strip comment prefix from a line
---Returns the stripped line (trimmed), or nil if not a comment
---@param line string Line to strip
---@return string|nil Stripped line or nil if no comment prefix
local function strip_comment_prefix(line)
  if not line or line == "" then
    return nil
  end

  -- Try each comment prefix pattern
  for _, pattern in ipairs(COMMENT_PREFIXES) do
    local stripped = line:gsub(pattern, "", 1)
    if stripped ~= line then
      return trim(stripped)
    end
  end

  -- No comment prefix found
  return nil
end

---Parse @restman.body directive with multi-line support
---Accumulates lines until valid JSON is found
---@param comment_lines string[] All comment lines (with prefixes stripped)
---@param start_idx number Starting index in comment_lines array
---@return table|string|nil body Parsed body (table if JSON, string if raw)
---@return number next_idx Next index to process
local function parse_body_directive(comment_lines, start_idx)
  if start_idx > #comment_lines then
    return nil, start_idx
  end

  local first_line = comment_lines[start_idx]
  local match = first_line:match(PATTERN_BODY)

  if not match then
    return nil, start_idx
  end

  local first_content = trim(match)

  -- If first line has content, try to parse it
  if first_content ~= "" then
    local success, decoded = pcall(vim.json.decode, first_content)
    if success then
      return decoded, start_idx + 1
    end
  end

  -- Accumulate additional lines for multi-line JSON
  local accumulated = { first_content }
  local idx = start_idx + 1

  while idx <= #comment_lines do
    local next_line_raw = comment_lines[idx]

    -- Stop at blank line
    if is_blank(next_line_raw) then
      break
    end

    -- Stop at new directive
    if next_line_raw:match("^@restman%..") then
      break
    end

    table.insert(accumulated, next_line_raw)
    idx = idx + 1

    -- Try to parse accumulated content
    local full_content = table.concat(accumulated, "")
    local success, decoded = pcall(vim.json.decode, full_content)

    if success then
      return decoded, idx
    end
  end

  -- If we get here, try to use accumulated content as-is
  local full_content = table.concat(accumulated, "")
  full_content = trim(full_content)

  if full_content ~= "" then
    -- Try one more JSON parse
    local success, decoded = pcall(vim.json.decode, full_content)
    if success then
      return decoded, idx
    end
    -- Return raw string
    return full_content, idx
  end

  return nil, start_idx + 1
end

---Parse @restman.header directive
---@param line string Line to parse (with prefix stripped)
---@return string|nil key Header key
---@return string|nil value Header value
local function parse_header_directive(line)
  local key, value = line:match(PATTERN_HEADER)
  if key and value then
    return trim(key), trim(value)
  end
  return nil, nil
end

---Parse @restman.query directive
---@param line string Line to parse (with prefix stripped)
---@return string|nil key Query key
---@return string|nil value Query value
local function parse_query_directive(line)
  local key, value = line:match(PATTERN_QUERY)
  if key and value then
    return trim(key), trim(value)
  end
  return nil, nil
end

---Parse @restman.form directive
---@param line string Line to parse (with prefix stripped)
---@return string|nil key Form key
---@return string|nil value Form value
local function parse_form_directive(line)
  local key, value = line:match(PATTERN_FORM)
  if key and value then
    return trim(key), trim(value)
  end
  return nil, nil
end

---Scan comment block above a request line for directives
---Starts from line - 1, goes up, stops at blank line, non-comment, or MAX_SCAN_LINES
---
---@param bufnr number Buffer number
---@param line number Line number (1-indexed) of the request line
---@return Directives Parsed directives (may have nil fields)
function M.scan_above(bufnr, line)
  ---@type Directives
  local result = {
    body = nil,
    headers = {},
    query = {},
    form = {},
  }

  -- Use current buffer (0) if not specified
  if not bufnr then
    bufnr = 0
  end

  -- No lines above to scan
  if not line or line <= 1 then
    return { body = nil, headers = nil, query = nil, form = nil }
  end

  -- Collect comment lines above request (going up from line - 1)
  local comment_lines = {}
  local current_line = line - 1

  while current_line >= math.max(1, line - MAX_SCAN_LINES) do
    local line_content = vim.api.nvim_buf_get_lines(bufnr, current_line - 1, current_line, false)[1]

    if not line_content then
      break
    end

    -- Stop at blank line
    if is_blank(line_content) then
      break
    end

    -- Try to strip comment prefix
    local stripped = strip_comment_prefix(line_content)

    -- Stop if not a comment line
    if not stripped then
      break
    end

    -- Add to front of array (to maintain order from top to bottom)
    table.insert(comment_lines, 1, stripped)
    current_line = current_line - 1
  end

  -- Parse directives from collected comment lines
  local idx = 1
  while idx <= #comment_lines do
    local comment_line = comment_lines[idx]

    -- Skip blank lines in comment block
    if is_blank(comment_line) then
      idx = idx + 1
      goto continue
    end

    -- Check for @restman.body directive
    if comment_line:match("^@restman%.body") then
      result.body, idx = parse_body_directive(comment_lines, idx)
      goto continue
    end

    -- Check for @restman.header directive
    if comment_line:match("^@restman%.header") then
      local key, value = parse_header_directive(comment_line)
      if key and value then
        result.headers[key] = value
      end
      idx = idx + 1
      goto continue
    end

    -- Check for @restman.query directive
    if comment_line:match("^@restman%.query") then
      local key, value = parse_query_directive(comment_line)
      if key and value then
        result.query[key] = value
      end
      idx = idx + 1
      goto continue
    end

    -- Check for @restman.form directive
    if comment_line:match("^@restman%.form") then
      local key, value = parse_form_directive(comment_line)
      if key and value then
        result.form[key] = value
      end
      idx = idx + 1
      goto continue
    end

    -- Unknown directive or non-directive comment line - skip
    idx = idx + 1

    ::continue::
  end

  -- Clean up empty tables (convert to nil)
  if not next(result.headers) then
    result.headers = nil
  end
  if not next(result.query) then
    result.query = nil
  end
  if not next(result.form) then
    result.form = nil
  end

  return result
end

return M
