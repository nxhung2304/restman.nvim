-- Environment loader — manage .env.json, variable substitution, header/base_url merge

local M = {}

local log = require("restman.log")

-- Module state
M._cache = nil  -- Loaded .env.json content
M._active = nil  -- Active environment name
M._notified_missing = false  -- Flag to suppress duplicate missing file notifications
M._base_url_cache = nil  -- Session cache for prompted base_url

---Find project root by walking up directories until .git/ is found
---@param start_dir string Starting directory path
---@return string Project root directory or start_dir if not found
local function find_project_root(start_dir)
  local dir = start_dir
  local max_depth = 20  -- Prevent infinite loops

  while dir and dir ~= "/" and max_depth > 0 do
    if vim.fn.isdirectory(dir .. "/.git") == 1 then
      return dir
    end
    dir = vim.fn.fnamemodify(dir, ":h")
    max_depth = max_depth - 1
  end

  return start_dir
end

---Load and parse .env.json file (lazy load with cache)
---@return table|nil Environment file content or nil if file missing/invalid
local function load_env_file()
  if M._cache ~= nil then
    return M._cache
  end

  -- Find .env.json in project root
  local current_file = vim.api.nvim_buf_get_name(0)
  local current_dir = vim.fn.fnamemodify(current_file, ":h")
  local project_root = find_project_root(current_dir)
  local env_file = project_root .. "/.env.json"

  -- Check if file exists
  if vim.fn.filereadable(env_file) == 0 then
    if not M._notified_missing then
      log.info("restman: .env.json not found, using empty environment")
      M._notified_missing = true
    end
    M._cache = false  -- Mark as checked (no file)
    return nil
  end

  -- Read and parse file
  local success, content = pcall(function()
    local lines = vim.fn.readfile(env_file)
    return table.concat(lines, "\n")
  end)

  if not success then
    log.error("restman: failed to read .env.json: " .. tostring(content))
    M._cache = false
    return nil
  end

  -- Parse JSON
  local success_json, env_data = pcall(vim.json.decode, content)
  if not success_json then
    log.error("restman: .env.json parse error: " .. tostring(env_data))
    M._cache = false
    return nil
  end

  -- Validate default environment exists
  if env_data.default then
    if not env_data.environments or not env_data.environments[env_data.default] then
      log.error(
        "restman: default environment '" .. env_data.default .. "' not found in .env.json"
      )
      M._cache = false
      return nil
    end
    M._active = env_data.default
  end

  M._cache = env_data
  return env_data
end

---Substitute variables in a string
---Supports: {{VAR_NAME}} and {{$env.VAR}}
---@param str string String to substitute
---@param variables table<string, string> Environment variables
---@return string String with variables substituted
local function gsub_vars(str, variables)
  if not str or type(str) ~= "string" then
    return str
  end

  -- Track unknown vars to warn only once per var
  local unknown_warned = {}

  -- Replace {{VAR_NAME}} with environment variable
  str = str:gsub("{{(%w+)}}", function(var_name)
    if variables and variables[var_name] then
      return tostring(variables[var_name])
    else
      if not unknown_warned[var_name] then
        log.warn("restman: unknown variable {{" .. var_name .. "}}")
        unknown_warned[var_name] = true
      end
      return "{{" .. var_name .. "}}"
    end
  end)

  -- Replace {{$env.VAR}} with system environment variable
  str = str:gsub("{{%$env%.(%w+)}}", function(var_name)
    local value = vim.env[var_name] or os.getenv(var_name)
    if value then
      return value
    else
      if not unknown_warned["$env." .. var_name] then
        log.warn("restman: environment variable $" .. var_name .. " not found")
        unknown_warned["$env." .. var_name] = true
      end
      return "{{$env." .. var_name .. "}}"
    end
  end)

  return str
end

---Recursively substitute variables in table values (for headers, query, form)
---@param tbl table<string, string> Table to substitute
---@param variables table<string, string> Environment variables
---@return table Table with substituted values
local function substitute_table(tbl, variables)
  if not tbl then
    return nil
  end

  local result = {}
  for key, value in pairs(tbl) do
    -- Substitute both key and value
    local new_key = gsub_vars(tostring(key), variables)
    local new_value = gsub_vars(tostring(value), variables)
    result[new_key] = new_value
  end
  return result
end

---Recursively substitute variables in a table (deep)
---@param obj any Object to substitute
---@param variables table<string, string> Environment variables
---@return any Object with substituted values
local function deep_substitute(obj, variables)
  if type(obj) == "string" then
    return gsub_vars(obj, variables)
  elseif type(obj) == "table" then
    local result = {}
    for key, value in pairs(obj) do
      result[key] = deep_substitute(value, variables)
    end
    return result
  else
    return obj
  end
end

---Resolve base URL for relative URLs
---@param url string Request URL
---@param base_url string|nil Environment base URL
---@return string Resolved URL
local function resolve_url(url, base_url)
  if not url then
    return url
  end

  -- Check if already absolute
  if url:match("^https?://") then
    return url
  end

  -- Relative URL - append to base_url
  if base_url then
    return base_url .. url
  end

  -- No base URL - prompt user once per session
  if not M._base_url_cache then
    local input_received = false
    vim.ui.input(
      { prompt = "Enter base URL (e.g. http://localhost:3000): " },
      function(input)
        if input and input ~= "" then
          M._base_url_cache = input
          input_received = true
        end
      end
    )
    -- Note: This is async, so we'll just return the original URL here
    -- In production, this would need to be handled differently
  end

  if M._base_url_cache then
    return M._base_url_cache .. url
  end

  -- Return URL unchanged if no base URL
  return url
end

---Load environment (lazy load)
---@return table|nil Environment data or nil
function M.load()
  return load_env_file()
end

---Force reload environment from disk
function M.reload()
  M._cache = nil
  M._active = nil
  M._notified_missing = false
  return load_env_file()
end

---Get active environment name
---@return string|nil Active environment name
function M.get_active()
  return M._active
end

---Set active environment by name
---@param name string Environment name
function M.set_active(name)
  local env_data = M.load()
  if not env_data or not env_data.environments or not env_data.environments[name] then
    log.error("restman: environment '" .. name .. "' not found")
    return false
  end
  M._active = name
  return true
end

---List all available environments
---@return string[] List of environment names
function M.list()
  local env_data = M.load()
  if not env_data or not env_data.environments then
    return {}
  end
  local names = {}
  for name in pairs(env_data.environments) do
    table.insert(names, name)
  end
  table.sort(names)
  return names
end

---Apply environment to request (substitute vars, merge headers, resolve base_url)
---@param request table Parsed request object
---@return table Modified request object
function M.apply_to(request)
  if not request then
    return request
  end

  -- Load environment
  local env_data = M.load()
  if not env_data then
    return request  -- No environment, return request unchanged
  end

  -- Get active environment (use default if not set)
  local active = M._active or env_data.default
  if not active or not env_data.environments[active] then
    return request  -- No valid active environment
  end

  local active_env = env_data.environments[active]
  local variables = active_env.variables or {}

  -- Make a copy to avoid modifying original
  local modified_request = vim.deepcopy(request)

  -- 1. Substitute URL
  if modified_request.url then
    modified_request.url = gsub_vars(modified_request.url, variables)
    -- 2. Resolve relative URLs with base_url
    if active_env.base_url then
      modified_request.url = resolve_url(modified_request.url, active_env.base_url)
    end
  end

  -- 3. Merge environment headers into request headers
  if active_env.headers then
    if not modified_request.headers then
      modified_request.headers = {}
    end
    -- Substitute env headers first
    local substituted_env_headers = substitute_table(active_env.headers, variables)
    -- Merge with request headers (request headers override env headers)
    for key, value in pairs(substituted_env_headers) do
      if not modified_request.headers[key] then
        modified_request.headers[key] = value
      end
    end
  end

  -- 4. Substitute request headers (key and value)
  if modified_request.headers then
    modified_request.headers = substitute_table(modified_request.headers, variables)
  end

  -- 5. Substitute body (string or table)
  if modified_request.body then
    modified_request.body = deep_substitute(modified_request.body, variables)
  end

  -- 6. Substitute query params
  if modified_request.query then
    modified_request.query = substitute_table(modified_request.query, variables)
  end

  -- 7. Substitute form params
  if modified_request.form then
    modified_request.form = substitute_table(modified_request.form, variables)
  end

  return modified_request
end

return M
