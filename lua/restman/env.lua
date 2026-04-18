-- Environment loader — manage .env.json, variable substitution, header/base_url merge

local M = {}

local log = require("restman.log")
local find_project_root

-- Module state
M._cache = nil -- Loaded .env.json content
M._active = nil -- Active environment name
M._notified_missing = false -- Flag to suppress duplicate missing file notifications
M._base_url_cache = {} -- Session cache for prompted/detected base_url by project root

local function get_current_dir()
  local current_file = vim.api.nvim_buf_get_name(0)
  if current_file and current_file ~= "" then
    return vim.fn.fnamemodify(current_file, ":h")
  end
  return vim.uv.cwd()
end

local function get_project_root()
  return find_project_root(get_current_dir())
end

---@param project_root string|nil
---@return string|nil
local function get_cached_base_url(project_root)
  if not project_root then
    return nil
  end
  return M._base_url_cache[project_root]
end

---@param project_root string|nil
---@param base_url string|nil
local function set_cached_base_url(project_root, base_url)
  if not project_root or not base_url or base_url == "" then
    return
  end
  M._base_url_cache[project_root] = base_url
end

---Find project root by walking up directories until .git/ is found
---@param start_dir string Starting directory path
---@return string Project root directory or start_dir if not found
find_project_root = function(start_dir)
  local dir = start_dir
  local max_depth = 20 -- Prevent infinite loops

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
  local project_root = get_project_root()
  local env_file = project_root .. "/.env.json"

  -- Check if file exists
  if vim.fn.filereadable(env_file) == 0 then
    M._cache = false -- Mark as checked (no file)
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
      log.error("restman: default environment '" .. env_data.default .. "' not found in .env.json")
      M._cache = false
      return nil
    end
    M._active = env_data.default
  end

  M._cache = env_data
  return env_data
end

---@param lsof_output string
---@return integer|nil
local function parse_listen_port(lsof_output)
  if not lsof_output or lsof_output == "" then
    return nil
  end

  for line in lsof_output:gmatch("[^\r\n]+") do
    local port = line:match("TCP%s+[%w%.%*:%[%]-]+:(%d+)%s+%(LISTEN%)")
    if port then
      return tonumber(port)
    end
  end

  return nil
end

---@param project_root string
---@return string|nil
local function get_rails_server_pid(project_root)
  local pid_file = project_root .. "/tmp/pids/server.pid"
  if vim.fn.filereadable(pid_file) == 0 then
    return nil
  end

  local lines = vim.fn.readfile(pid_file)
  local pid = lines[1] and vim.trim(lines[1]) or nil
  if not pid or pid == "" or not pid:match("^%d+$") then
    return nil
  end

  return pid
end

---@param project_root string
---@param callback function Callback(base_url)
local function detect_rails_base_url_async(project_root, callback)
  if vim.fn.filereadable(project_root .. "/config/routes.rb") == 0 then
    callback(nil)
    return
  end

  local pid = get_rails_server_pid(project_root)
  if not pid then
    callback(nil)
    return
  end

  vim.system(
    { "lsof", "-Pan", "-p", pid, "-iTCP", "-sTCP:LISTEN" },
    { text = true },
    function(result)
      vim.schedule(function()
        if result.code ~= 0 then
          callback(nil)
          return
        end

        local port = parse_listen_port(result.stdout or "")
        if not port then
          callback(nil)
          return
        end

        callback("http://localhost:" .. tostring(port))
      end)
    end
  )
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

---Resolve base URL for relative URLs without prompting.
---@param url string Request URL
---@param base_url string|nil Environment base URL
---@return string Resolved URL
local function resolve_url(url, base_url, project_root)
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

  local cached_base_url = get_cached_base_url(project_root or get_project_root())
  if cached_base_url then
    return cached_base_url .. url
  end

  -- Return URL unchanged if no base URL
  return url
end

---Resolve base URL for relative URLs, prompting when needed.
---@param url string Request URL
---@param base_url string|nil Environment base URL
---@param opts table|nil Options: { project_root?, force_detect? }
---@param callback function Callback(resolved_url)
local function resolve_url_async(url, base_url, opts, callback)
  if not url or url:match("^https?://") then
    callback(url)
    return
  end

  opts = opts or {}
  local project_root = opts.project_root or get_project_root()

  if base_url then
    callback(base_url .. url)
    return
  end

  if not opts.force_detect then
    local cached_base_url = get_cached_base_url(project_root)
    if cached_base_url then
      callback(cached_base_url .. url)
      return
    end
  end

  detect_rails_base_url_async(project_root, function(detected_base_url)
    if detected_base_url then
      set_cached_base_url(project_root, detected_base_url)
      log.info("restman: detected local Rails server at " .. detected_base_url)
      callback(detected_base_url .. url)
      return
    end

    vim.ui.input({ prompt = "Enter base URL (e.g. http://localhost:3000): " }, function(input)
      if input and input ~= "" then
        set_cached_base_url(project_root, input)
        callback(input .. url)
        return
      end
      callback(url)
    end)
  end)
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
  M._base_url_cache = {}
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

  local modified_request = vim.deepcopy(request)

  -- Load environment
  local env_data = M.load()
  if not env_data then
    if modified_request.url then
      modified_request.url = resolve_url(modified_request.url, nil, get_project_root())
    end
    return modified_request
  end

  -- Get active environment (use default if not set)
  local active = M._active or env_data.default
  if not active or not env_data.environments[active] then
    if modified_request.url then
      modified_request.url = resolve_url(modified_request.url, nil, get_project_root())
    end
    return modified_request
  end

  local active_env = env_data.environments[active]
  local variables = active_env.variables or {}

  -- 1. Substitute URL
  if modified_request.url then
    modified_request.url = gsub_vars(modified_request.url, variables)
    modified_request.url =
      resolve_url(modified_request.url, active_env.base_url, get_project_root())
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

---Apply environment to request and resolve relative URL asynchronously.
---@param request table Parsed request object
---@param opts table|nil Options: { project_root?, force_detect? }
---@param callback function Callback(modified_request)
function M.apply_to_async(request, opts, callback)
  if not request then
    callback = opts
    callback(request)
    return
  end

  if type(opts) == "function" then
    callback = opts
    opts = {}
  end

  opts = opts or {}

  local modified_request = M.apply_to(request)
  local env_data = M.load()
  local active_env = nil

  if env_data and env_data.environments then
    local active = M._active or env_data.default
    active_env = active and env_data.environments[active] or nil
  end

  resolve_url_async(
    modified_request.url,
    active_env and active_env.base_url or nil,
    opts,
    function(url)
      modified_request.url = url
      callback(modified_request)
    end
  )
end

---@param project_root string|nil
function M.clear_base_url_cache(project_root)
  if project_root then
    M._base_url_cache[project_root] = nil
    return
  end
  M._base_url_cache = {}
end

M._parse_listen_port = parse_listen_port

return M
