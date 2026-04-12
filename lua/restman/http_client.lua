-- HTTP Client — async request execution via vim.system
-- Sends requests using curl CLI, parses responses, handles cancellation

local M = {}

-- Dependencies
local config = require("restman.config")
local log = require("restman.log")

-- Module state
M._pending = nil  -- { handle, started_at } when request is in-flight
M._cancelled = false  -- flag to track if user cancelled

---Encode request body for curl
---@param body string|table Request body
---@return string Encoded body
local function encode_body(body)
  if type(body) == "table" then
    return vim.json.encode(body)
  end
  return tostring(body)
end

---Build URL with query parameters
---@param base_url string Base URL
---@param query table<string, string> Query parameters (nil ok)
---@return string URL with appended query string
local function build_url_with_query(base_url, query)
  if not query or next(query) == nil then
    return base_url
  end

  local query_parts = {}
  for key, value in pairs(query) do
    table.insert(query_parts, key .. "=" .. vim.uri_encode(tostring(value)))
  end

  local query_string = table.concat(query_parts, "&")
  local separator = base_url:find("?") and "&" or "?"
  return base_url .. separator .. query_string
end

---Encode form parameters as application/x-www-form-urlencoded
---@param form table<string, string> Form parameters
---@return string URL-encoded form string
local function encode_form_params(form)
  if not form or next(form) == nil then
    return nil
  end

  local parts = {}
  for key, value in pairs(form) do
    table.insert(parts, key .. "=" .. vim.uri_encode(tostring(value)))
  end
  return table.concat(parts, "&")
end

---Check if request should send body via stdin
---@param request table ParsedRequest
---@return boolean
local function needs_stdin(request)
  if not request.body then
    return false
  end
  local method = request.method or ""
  return method == "POST" or method == "PUT" or method == "PATCH"
end

---Build curl command arguments from request
---@param request table ParsedRequest
---@param cfg table Config
---@return string[] Curl argument array
local function build_curl_args(request, cfg)
  local args = { "curl" }

  -- Silent mode + show errors, dump headers inline
  table.insert(args, "-sS")
  table.insert(args, "-D")
  table.insert(args, "-")

  -- Format: set footer with status code + time
  table.insert(args, "-w")
  table.insert(args, "\nRESTMAN_META %{http_code} %{time_total}\n")

  -- Timeout
  local timeout = cfg.timeout or 30
  table.insert(args, "--max-time")
  table.insert(args, tostring(timeout))

  -- HTTP method
  table.insert(args, "-X")
  table.insert(args, request.method or "GET")

  -- Add User-Agent if not already present
  local has_user_agent = false
  if request.headers then
    for key in pairs(request.headers) do
      if key:lower() == "user-agent" then
        has_user_agent = true
        break
      end
    end
  end
  if not has_user_agent then
    table.insert(args, "-H")
    table.insert(args, "User-Agent: restman.nvim/1.0")
  end

  -- Headers
  if request.headers then
    for key, value in pairs(request.headers) do
      table.insert(args, "-H")
      table.insert(args, key .. ": " .. tostring(value))
    end
  end

  -- Query parameters (append to URL)
  local url = request.url or ""
  url = build_url_with_query(url, request.query)

  -- Form parameters: add as data (form-urlencoded)
  if request.form and next(request.form) ~= nil then
    local form_data = encode_form_params(request.form)
    if form_data then
      table.insert(args, "--data-urlencode")
      table.insert(args, form_data)
    end
  end

  -- Body: use stdin for POST/PUT/PATCH (avoid command-line length limits)
  if needs_stdin(request) then
    table.insert(args, "--data")
    table.insert(args, "@-")
  end

  -- URL at the end
  table.insert(args, url)

  return args
end

---Parse curl response
---Expected format (with -sS -D -):
---```
---HTTP/1.1 200 OK
---Content-Type: application/json
---...
---(blank line)
---{"body": "..."}
---
---RESTMAN_META 200 0.123456
---```
---@param stdout string Raw curl stdout
---@return table Parsed response
local function parse_response(stdout)
  if not stdout or stdout == "" then
    return { status = 0, headers = {}, body = "" }
  end

  -- Extract footer: RESTMAN_META <status_code> <time_total>
  local meta_match = stdout:match("RESTMAN_META%s+(%d+)%s+([%d%.]+)%s*$")
  local status_code = 200
  local time_total = 0

  if meta_match then
    status_code = tonumber(meta_match:match("(%d+)"))
    time_total = tonumber(meta_match:match("[%d%.]+"))
  end

  -- Remove footer from output
  local output_without_footer = stdout:gsub("RESTMAN_META%s+%d+%s+[%d%.]+%s*$", ""):gsub("%s+$", "")

  -- Split header and body at first blank line
  local header_end = output_without_footer:find("\n\n") or output_without_footer:find("\r\n\r\n")
  local headers_text = ""
  local body = ""

  if header_end then
    headers_text = output_without_footer:sub(1, header_end - 1)
    body = output_without_footer:sub(header_end + 2):gsub("^%s+", ""):gsub("%s+$", "")
  else
    -- No blank line found, treat all as headers (no body)
    headers_text = output_without_footer
    body = ""
  end

  -- Parse status line
  local status_line_match = headers_text:match("^HTTP/%d%.%d%s+(%d+)%s*(.*)")
  if status_line_match then
    status_code = tonumber(status_line_match)
  end

  -- Parse headers
  local headers = {}
  for line in headers_text:gmatch("[^\n]+") do
    local key, value = line:match("^([^:]+):%s*(.*)$")
    if key and value then
      headers[key] = value
    end
  end

  return {
    status = status_code,
    headers = headers,
    body = body,
    raw = stdout,
  }
end

---Send HTTP request asynchronously
---@param request table ParsedRequest with fields: method, url, headers, body?, query?, form?, source
---@param on_complete function Callback(response). Response = { status, headers, body, duration_ms } or { kind="network"/"cancelled"/"busy", ... }
function M.send(request, on_complete)
  -- Check if already pending
  if M._pending then
    on_complete({ kind = "busy", message = "request already in-flight" })
    return
  end

  -- Validate request
  if not request or not request.url then
    on_complete({ kind = "network", message = "invalid request: no URL" })
    return
  end

  -- Get config
  local cfg = config.get()

  -- Build curl args
  local args = build_curl_args(request, cfg)

  -- Prepare stdin if needed
  local stdin_input = nil
  if needs_stdin(request) and request.body then
    stdin_input = encode_body(request.body)
  end

  -- Record start time for duration calculation
  local started_at = vim.uv.hrtime()

  -- Spawn curl process asynchronously
  local handle
  handle = vim.system(
    args,
    { stdin = stdin_input, text = true },
    function(result)
      -- Clear pending state
      M._pending = nil

      -- Check if cancelled
      if M._cancelled then
        M._cancelled = false
        on_complete({ kind = "cancelled" })
        return
      end

      -- Check for exit code (non-zero = error)
      if result.code ~= 0 and result.code ~= nil then
        local error_msg = result.stderr or "curl exited with code " .. tostring(result.code)
        on_complete({ kind = "network", message = error_msg })
        return
      end

      -- Parse response
      local response = parse_response(result.stdout or "")

      -- Add duration in milliseconds
      local duration_ns = vim.uv.hrtime() - started_at
      response.duration_ms = math.floor(duration_ns / 1e6)

      -- Success callback
      on_complete(response)
    end
  )

  -- Track pending request
  M._pending = {
    handle = handle,
    started_at = started_at,
  }
end

---Cancel the in-flight request
function M.cancel()
  if M._pending and M._pending.handle then
    M._cancelled = true
    M._pending.handle:kill(15)  -- SIGTERM
    M._pending = nil
  end
end

---Check if a request is currently in-flight
---@return boolean
function M.is_pending()
  return M._pending ~= nil
end

return M
