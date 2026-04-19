-- Request template generator for :Restman new command

local M = {}

-- Supported HTTP methods (uppercase for internal use)
local HTTP_METHODS = { "GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS" }

-- Default placeholder URLs
local DEFAULT_URL = "https://jsonplaceholder.typicode.com/todos"
local FALLBACK_URL = "https://example.com"

---Get the best default URL based on active environment
---@return string URL to use in template
local function get_default_url()
  local ok_env, env_module = pcall(require, "restman.env")
  if ok_env then
    local env_data = env_module.load()
    if env_data then
      local active = env_module.get_active() or env_data.default
      if active and env_data.environments and env_data.environments[active] then
        local base_url = env_data.environments[active].base_url
        if base_url and base_url ~= "" then
          -- Use base_url from env with a placeholder path
          return base_url .. "/{path}"
        end
      end
    end
  end

  return DEFAULT_URL
end

---Generate template lines for a given HTTP method
---@param method string HTTP method (case-insensitive)
---@return string[]|nil Table of template lines, or nil if method invalid
function M.generate(method)
  local upper_method = method:upper()

  -- Validate method
  local valid = false
  for _, m in ipairs(HTTP_METHODS) do
    if m == upper_method then
      valid = true
      break
    end
  end

  if not valid then
    return nil
  end

  -- Methods with body template
  local body_methods = { POST = true, PUT = true, PATCH = true }

  local lines = {}
  table.insert(lines, upper_method .. " " .. get_default_url())

  if body_methods[upper_method] then
    table.insert(lines, "@restman.body {}")
  end

  return lines
end

---List all supported HTTP methods
---@return string[]
function M.list_methods()
  return vim.deepcopy(HTTP_METHODS)
end

---Insert template at cursor position
---@param method string HTTP method (case-insensitive)
---@return boolean success
function M.insert_at_cursor(method)
  local lines = M.generate(method)
  if not lines then
    return false
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row = cursor[1]
  local bufnr = 0

  -- Insert at current position (0-indexed)
  vim.api.nvim_buf_set_lines(bufnr, row, row, false, lines)

  -- Position cursor after URL for easy editing
  local url = get_default_url()
  local url_len = #method:upper() + 1 + #url
  vim.api.nvim_win_set_cursor(0, { row + 1, url_len })

  return true
end

return M
