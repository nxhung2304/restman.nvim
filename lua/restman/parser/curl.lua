local util = require("restman.parser.util")
local M = {}

---cURL command flags that we recognize
local CURL_FLAGS = {
  method = { "-X", "--request" },
  header = { "-H", "--header" },
  data = { "-d", "--data", "--data-raw", "--data-binary" },
}

---Pattern to detect cURL command at start
local CURL_PATTERN = "^curl%s"

---@class Request
---@field method string HTTP method (uppercase)
---@field url string Request URL
---@field headers table<string, string> Request headers (empty by default)
---@field body? string Request body (nil by default)
---@field source RequestSource Source location info

---@class RequestSource
---@field file string Source file path
---@field line number Source line number (1-indexed)

---Join multi-line cURL command (lines ending with \)
---Returns nil if no valid cURL command found
---@param lines_block string[] Array of lines
---@return string[] Joined lines or empty array if invalid
local function join_multiline(lines_block)
  if #lines_block == 0 then
    return {}
  end

  local result = {}
  local current_line = ""

  for _, line in ipairs(lines_block) do
    -- Remove trailing backslash and whitespace
    local trimmed = vim.trim(line)
    local ends_with_backslash = trimmed:sub(-1) == "\\"

    if ends_with_backslash then
      -- Remove backslash and append to current line
      current_line = current_line .. trimmed:sub(1, -2)
    else
      -- Append this line and add to result
      current_line = current_line .. line
      table.insert(result, current_line)
      current_line = ""
    end
  end

  -- If there's still content (shouldn't happen with well-formed input), add it
  if current_line ~= "" then
    table.insert(result, current_line)
  end

  return result
end

---Minimal shell-like argument parser
---Handles double quotes, single quotes, and escaped quotes
---@param cmdline string Command line to parse
---@return string[] Array of arguments
local function shell_split(cmdline)
  local args = {}
  local current = ""
  local in_quote = nil -- '"', "'", or nil
  local escape_next = false
  local i = 1

  while i <= #cmdline do
    local char = cmdline:sub(i, i)

    if escape_next then
      -- Escaped character, add literally
      current = current .. char
      escape_next = false
    elseif char == "\\" then
      -- Escape next character
      escape_next = true
    elseif char == '"' or char == "'" then
      if in_quote == char then
        -- Closing quote
        in_quote = nil
      elseif in_quote == nil then
        -- Opening quote
        in_quote = char
      else
        -- Quote inside other quotes, add literally
        current = current .. char
      end
    elseif char == " " or char == "\t" then
      if in_quote then
        -- Space inside quotes, keep
        current = current .. char
      else
        -- Space outside quotes, delimiter
        if current ~= "" then
          table.insert(args, current)
          current = ""
        end
      end
    else
      current = current .. char
    end

    i = i + 1
  end

  -- Add last argument
  if current ~= "" then
    table.insert(args, current)
  end

  return args
end

---Check if a flag matches any of the given flag variants
---@param flag string Flag to check
---@param variants string[] Flag variants to match against
---@return boolean True if flag matches
local function flag_matches(flag, variants)
  for _, variant in ipairs(variants) do
    if flag == variant then
      return true
    end
  end
  return false
end

---Parse header value from "-H Key: Value" format
---@param value string Header value string
---@return string|nil key, string|nil value
local function parse_header_value(value)
  local stripped = util.strip_quotes(value)
  local key, val = stripped:match("^([^:]+):%s*(.*)$")
  if key and val then
    return vim.trim(key), vim.trim(val)
  end
  return nil, nil
end

---Read body content from file
---@param file_path string Path to file (may be relative or absolute)
---@param base_file string Base file path for resolving relative paths
---@return string|nil Body content or nil if file not found
local function read_body_file(file_path, base_file)
  -- Expand path: if relative, resolve against base file's directory
  local expanded_path
  if file_path:sub(1, 1) == "/" then
    -- Absolute path
    expanded_path = file_path
  else
    -- Relative path - resolve from base file's directory
    local base_dir = vim.fn.fnamemodify(base_file, ":h")
    expanded_path = base_dir .. "/" .. file_path
  end

  -- Try to read file
  local file = io.open(expanded_path, "r")
  if not file then
    vim.notify(
      "[restman] cURL parser: cannot read body file: " .. expanded_path,
      vim.log.levels.WARN
    )
    return nil
  end

  local content = file:read("*a")
  file:close()

  return content
end

---Parse cURL command from joined lines
---Returns nil if not a valid cURL command
---@param cmdline string Command line to parse
---@param line_number number Starting line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
local function parse_curl_command(cmdline, line_number, file_path)
  -- Check if this looks like a cURL command
  if not cmdline:match(CURL_PATTERN) then
    return nil
  end

  local args = shell_split(cmdline)
  if #args < 2 then
    -- Just "curl" with no arguments
    return nil
  end

  -- Parse arguments
  local method = nil
  local url = nil
  local headers = {}
  local body = nil
  local has_data_flag = false

  local i = 2 -- Skip "curl" at index 1
  while i <= #args do
    local arg = args[i]

    -- Check for method flags (-X, --request)
    if flag_matches(arg, CURL_FLAGS.method) then
      if i + 1 <= #args then
        method = vim.trim(args[i + 1])
        i = i + 2
      else
        i = i + 1
      end
    -- Check for header flags (-H, --header)
    elseif flag_matches(arg, CURL_FLAGS.header) then
      if i + 1 <= #args then
        local key, value = parse_header_value(args[i + 1])
        if key and value then
          headers[key] = value
        end
        i = i + 2
      else
        i = i + 1
      end
    -- Check for data flags (-d, --data, --data-raw, --data-binary)
    elseif flag_matches(arg, CURL_FLAGS.data) then
      has_data_flag = true
      if i + 1 <= #args then
        local data_value = util.strip_quotes(args[i + 1])
        -- Check if it's a file reference (@file.json)
        if data_value:sub(1, 1) == "@" then
          local file_ref = data_value:sub(2)
          body = read_body_file(file_ref, file_path)
        else
          body = data_value
        end
        i = i + 2
      else
        i = i + 1
      end
    -- URL (non-flag argument)
    elseif arg:sub(1, 1) ~= "-" then
      url = arg
      i = i + 1
    else
      -- Unknown flag, skip
      i = i + 1
    end
  end

  -- Must have URL
  if not url then
    return nil
  end

  -- Determine method
  if not method then
    if has_data_flag then
      method = "POST"
    else
      method = "GET"
    end
  end

  -- Normalize method to uppercase
  method = string.upper(method)

  return {
    method = method,
    url = url,
    headers = headers,
    body = body,
    source = {
      file = file_path,
      line = line_number,
    },
  }
end

---Parse cURL command from a block of lines
---Supports multi-line cURL commands with backslash continuation
---Returns nil if no valid cURL command found
---@param lines_block string[] Array of lines
---@param start_line number Starting line number (1-indexed)
---@param file_path string Source file path
---@return Request|nil Parsed request or nil if no match
function M.parse(lines_block, start_line, file_path)
  if not lines_block or #lines_block == 0 then
    return nil
  end

  local joined = join_multiline(lines_block)
  if #joined == 0 then
    return nil
  end

  -- Parse the first (or only) line as the cURL command
  return parse_curl_command(joined[1], start_line, file_path)
end

return M
