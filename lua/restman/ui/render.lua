-- UI Render layer — format and display responses in buffers with syntax highlighting

local M = {}

-- Create namespace for highlights
local RESTMAN_NS = vim.api.nvim_create_namespace("restman")

-- HTTP status text mapping
local HTTP_STATUS_TEXT = {
  [200] = "OK",
  [201] = "Created",
  [204] = "No Content",
  [301] = "Moved Permanently",
  [302] = "Found",
  [304] = "Not Modified",
  [400] = "Bad Request",
  [401] = "Unauthorized",
  [403] = "Forbidden",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [409] = "Conflict",
  [422] = "Unprocessable Entity",
  [429] = "Too Many Requests",
  [500] = "Internal Server Error",
  [502] = "Bad Gateway",
  [503] = "Service Unavailable",
}

---Recursively serialize Lua table to JSON with 2-space indentation
---@param val any Value to serialize
---@param indent number Current indentation level (default 0)
---@return string JSON string
local function json_pretty(val, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)
  local inner_pad = string.rep("  ", indent + 1)
  local t = type(val)

  if val == nil or val == vim.NIL then
    return "null"
  elseif t == "boolean" then
    return tostring(val)
  elseif t == "number" then
    -- Format integers without decimal point
    if val == math.floor(val) and math.abs(val) < 2 ^ 53 then
      return string.format("%d", val)
    end
    return tostring(val)
  elseif t == "string" then
    -- Use vim.json.encode for safe string escaping (includes quotes)
    return vim.json.encode(val)
  elseif t == "table" then
    -- Detect array vs object
    local is_array = #val > 0
    if is_array then
      local items = {}
      for _, v in ipairs(val) do
        table.insert(items, inner_pad .. json_pretty(v, indent + 1))
      end
      if #items == 0 then
        return "[]"
      end
      return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
    else
      local entries = {}
      -- Sort keys for deterministic output
      local keys = vim.tbl_keys(val)
      table.sort(keys, function(a, b)
        return tostring(a) < tostring(b)
      end)
      for _, k in ipairs(keys) do
        local key_str = vim.json.encode(tostring(k))
        table.insert(entries, inner_pad .. key_str .. ": " .. json_pretty(val[k], indent + 1))
      end
      if #entries == 0 then
        return "{}"
      end
      return "{\n" .. table.concat(entries, ",\n") .. "\n" .. pad .. "}"
    end
  end

  return "null"
end

---Format byte size to human-readable string
---@param bytes number Number of bytes
---@return string Formatted size (e.g., "1.2 KB", "256 B")
function M.format_bytes(bytes)
  if bytes < 1024 then
    return string.format("%d B", bytes)
  elseif bytes < 1024 * 1024 then
    return string.format("%.1f KB", bytes / 1024)
  else
    return string.format("%.1f MB", bytes / (1024 * 1024))
  end
end

---Get status text and highlight group for HTTP status code
---@param code number HTTP status code
---@return table { text: string, hl_group: string }
function M.format_status(code)
  local text = code .. " " .. (HTTP_STATUS_TEXT[code] or "Unknown")

  local hl_group = "Normal"
  if code >= 200 and code < 300 then
    hl_group = "DiagnosticOk"  -- Green
  elseif code >= 300 and code < 400 then
    hl_group = "WarningMsg"  -- Yellow
  elseif code >= 400 then
    hl_group = "ErrorMsg"  -- Red
  end

  return { text = text, hl_group = hl_group }
end

---Prettify body based on content type and detect filetype
---@param body string Raw response body
---@param content_type string|nil Content-Type header value
---@return string, string|nil Prettified body, filetype for buffer
function M.prettify(body, content_type)
  if not body or body == "" then
    return body, nil
  end

  content_type = (content_type or ""):lower()

  -- JSON detection and prettification
  if content_type:find("application/json") or body:match("^%s*[%{%[]") then
    local success, decoded = pcall(vim.json.decode, body)
    if success then
      -- Pretty print with 2-space indent
      local pretty = json_pretty(decoded)
      return pretty, "json"
    end
  end

  -- HTML detection
  if content_type:find("text/html") or body:match("<!DOCTYPE") or body:match("<html") then
    return body, "html"
  end

  -- XML detection
  if content_type:find("text/xml") or content_type:find("application/xml") or body:match("<%?xml") then
    return body, "xml"
  end

  -- Default: plain text
  return body, nil
end

---Render response into buffer
---@param bufnr number Buffer number to render into
---@param request table Request object
---@param response table Response object or error object
---@param opts table|nil Options (mode: "body" | "headers" | "raw")
function M.render(bufnr, request, response, opts)
  opts = opts or {}
  local mode = opts.mode or "body"

  -- Validate buffer
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Set modifiable
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  -- Clear existing lines and highlights
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  vim.api.nvim_buf_clear_namespace(bufnr, RESTMAN_NS, 0, -1)

  -- Build lines
  local lines = {}

  -- Error response handling
  if response.kind then
    -- Line 1: Method + URL
    table.insert(lines, request.method .. " " .. request.url)

    -- Line 2: Error status (sanitize message by replacing newlines with space)
    local error_icon = "❌"
    local message = response.message or "unknown error"
    -- Replace newlines with space to avoid nvim_buf_set_lines error
    message = message:gsub("[\r\n]+", " ")
    local error_msg = error_icon .. " " .. (response.kind or "unknown") .. ": " .. message
    table.insert(lines, error_msg)

    -- Line 3: Blank
    table.insert(lines, "")

    -- Line 4: Hint
    table.insert(lines, "Hint: Check your connection and try again")

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    return
  end

  -- Normal response (success)
  -- Line 1: Method + URL
  table.insert(lines, request.method .. " " .. request.url)

  -- Line 2: Status + duration + size
  local status_info = M.format_status(response.status or 0)
  local duration_str = (response.duration_ms and response.duration_ms .. "ms") or "0ms"
  local body_size = (response.body and #tostring(response.body)) or 0
  local size_str = M.format_bytes(body_size)

  local status_line = status_info.text .. "   •   " .. duration_str .. "   •   " .. size_str
  table.insert(lines, status_line)
  local status_line_idx = #lines - 1  -- 0-indexed

  -- Line 3: Separator
  table.insert(lines, string.rep("─", 40))

  -- Line 4: Toggle hints
  local header_count = (response.headers and vim.tbl_count(response.headers)) or 0
  table.insert(lines, "[H] Headers (" .. header_count .. ")   [B] Body   [R] Raw")

  -- Line 5: Blank
  table.insert(lines, "")

  -- Body content based on mode
  if mode == "headers" then
    -- Headers view
    if response.headers then
      for key, value in pairs(response.headers) do
        table.insert(lines, key .. ": " .. tostring(value))
      end
    end
  elseif mode == "raw" then
    -- Raw view (unformatted body)
    if response.raw then
      local raw_lines = vim.split(response.raw, "\n", { plain = true })
      for _, line in ipairs(raw_lines) do
        table.insert(lines, line)
      end
    end
  else
    -- Default: Body view (prettified)
    if response.body then
      local content_type = response.headers and response.headers["Content-Type"]
      local prettified, filetype = M.prettify(response.body, content_type)

      -- Split body into lines
      local body_lines = vim.split(prettified, "\n", { plain = true })
      for _, line in ipairs(body_lines) do
        table.insert(lines, line)
      end

      -- Set filetype for syntax highlighting
      if filetype then
        vim.api.nvim_buf_set_option(bufnr, "filetype", filetype)
      end
    end
  end

  -- Set lines
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Apply status line highlighting
  vim.api.nvim_buf_add_highlight(bufnr, RESTMAN_NS, status_info.hl_group, status_line_idx, 0, -1)

  -- Store view mode in buffer variable
  vim.api.nvim_buf_set_var(bufnr, "restman_view_mode", mode)

  -- Disable modifications
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

return M
