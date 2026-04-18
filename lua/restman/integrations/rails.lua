local M = {}

local config = require("restman.config")
local log = require("restman.log")

local HTTP_METHODS = {
  GET = true,
  POST = true,
  PUT = true,
  PATCH = true,
  DELETE = true,
  HEAD = true,
  OPTIONS = true,
  CONNECT = true,
  TRACE = true,
}

local function find_project_root(start_dir)
  local dir = start_dir
  local max_depth = 20

  while dir and dir ~= "/" and max_depth > 0 do
    if
      vim.fn.filereadable(dir .. "/config/routes.rb") == 1
      or vim.fn.isdirectory(dir .. "/.git") == 1
    then
      return dir
    end
    dir = vim.fn.fnamemodify(dir, ":h")
    max_depth = max_depth - 1
  end

  return start_dir
end

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

local function get_routes_file(project_root)
  return project_root .. "/config/routes.rb"
end

local function get_cache_file(project_root)
  local cfg = config.get()
  return cfg.rails.cache_file or (project_root .. "/.cache/restman/rails_routes.txt")
end

local function ensure_cache_dir(cache_file)
  vim.fn.mkdir(vim.fn.fnamemodify(cache_file, ":h"), "p")
end

local function ensure_gitignore(project_root)
  local gitignore = project_root .. "/.gitignore"
  if vim.fn.filereadable(gitignore) == 0 then
    return
  end

  local lines = vim.fn.readfile(gitignore)
  for _, line in ipairs(lines) do
    if vim.trim(line) == ".cache/restman/" then
      return
    end
  end

  table.insert(lines, ".cache/restman/")
  vim.fn.writefile(lines, gitignore)
end

local detect_grape_mount

local function compare_mtime(a, b)
  local a_sec = a.sec or 0
  local b_sec = b.sec or 0
  if a_sec ~= b_sec then
    return a_sec - b_sec
  end
  return (a.nsec or 0) - (b.nsec or 0)
end

local function normalize_verb(value)
  if not value or value == "" then
    return nil
  end

  for token in tostring(value):gmatch("[A-Z]+") do
    if HTTP_METHODS[token] then
      return token
    end
  end

  return nil
end

local function normalize_path(value)
  local path = vim.trim(value or "")
  if path == "" then
    return path
  end

  path = path:gsub("%(%.:format%)", "")
  path = path:gsub("%(%.format%)", "")
  return path
end

local function parse_route_line(line)
  if not line or line == "" then
    return nil
  end

  local trimmed = vim.trim(line)
  if trimmed == "" or trimmed:match("^Prefix%s+Verb%s+") then
    return nil
  end

  local columns = vim.split(trimmed, "%s+", { trimempty = true })
  if #columns < 3 then
    return nil
  end

  local verb_index = (#columns >= 4) and 2 or 1
  local path_index = verb_index + 1
  local action = columns[#columns]
  local verb = normalize_verb(columns[verb_index])
  local path = normalize_path(columns[path_index])

  if not verb or path == "" or not action:find("#", 1, true) then
    return nil
  end

  return {
    verb = verb,
    path = path,
    action = action,
  }
end

local function parse_routes_output(content)
  local routes = {}
  for _, line in ipairs(vim.split(content or "", "\n", { trimempty = true })) do
    local route = parse_route_line(line)
    if route then
      table.insert(routes, route)
    end
  end
  return routes
end

local function read_cached_routes(cache_file)
  if vim.fn.filereadable(cache_file) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(cache_file)
  return parse_routes_output(table.concat(lines, "\n"))
end

local function cache_is_stale(routes_file, cache_file)
  local routes_stat = vim.uv.fs_stat(routes_file)
  local cache_stat = vim.uv.fs_stat(cache_file)
  if not routes_stat or not cache_stat or not routes_stat.mtime or not cache_stat.mtime then
    return false
  end
  return compare_mtime(routes_stat.mtime, cache_stat.mtime) > 0
end

local function format_route_for_picker(route, description_format)
  description_format = description_format or " → %s"
  local desc_part = ""

  -- Check if action looks like a description (not controller#action format)
  if route.action and route.action ~= "" and not route.action:find("#", 1, true) then
    desc_part = string.format(description_format, route.action)
  end

  if desc_part ~= "" then
    return string.format("%-6s %s%s", route.verb, route.path, desc_part)
  else
    return string.format("%-6s %s %s", route.verb, route.path, route.action)
  end
end

local function open_picker(routes)
  local picker = require("restman.ui.picker")
  local cfg = config.get()
  local description_format = cfg.rails.grape_description_format or " → %s"

  picker.pick({
    items = routes,
    title = "Rails Routes",
    format = function(route)
      return format_route_for_picker(route, description_format)
    end,
    on_select = function(route)
      M.send_route(route)
    end,
  })
end

local function send_request(request)
  local http_client = require("restman.http_client")
  local buffer = require("restman.ui.buffer")
  local view = require("restman.ui.view")
  local history = require("restman.history")

  require("restman.commands")._last = { request = request }

  http_client.send(request, function(response)
    vim.schedule(function()
      local resp_bufnr = buffer.create(request, response)
      local cfg = config.get()
      view.open(resp_bufnr, cfg.response_view.default_view)
      if response.status then
        history.append(request, response, resp_bufnr)
      end
    end)
  end)
end

local function merge_routes(base_routes, extra_routes)
  local merged = {}
  local seen = {}

  for _, route in ipairs(base_routes or {}) do
    -- Use only verb + path as key (ignore action to avoid duplicates)
    local key = route.verb .. " " .. route.path
    if not seen[key] then
      seen[key] = true
      table.insert(merged, route)
    end
  end

  for _, route in ipairs(extra_routes or {}) do
    -- Use only verb + path as key (ignore action to avoid duplicates)
    local key = route.verb .. " " .. route.path
    if not seen[key] then
      seen[key] = true
      table.insert(merged, route)
    end
  end

  return merged
end

local function sort_routes_by_api(routes)
  table.sort(routes, function(a, b)
    -- Check if routes have /api in path
    local a_has_api = a.path:find("/api", 1, true) ~= nil
    local b_has_api = b.path:find("/api", 1, true) ~= nil

    -- If one has /api and the other doesn't, /api comes first
    if a_has_api ~= b_has_api then
      return a_has_api
    end

    -- Otherwise, maintain original order by path
    return a.path < b.path
  end)
  return routes
end

local function load_optional_grape_routes(project_root, base_routes, opts, callback)
  if not detect_grape_mount(project_root) then
    log.info("Restman: no Grape mount detected in config/routes.rb")
    base_routes = sort_routes_by_api(base_routes or {})
    log.info("Restman: " .. #(base_routes or {}) .. " Rails routes loaded")
    callback(base_routes)
    return
  end

  log.info("Restman: detected Grape mount, attempting to load Grape routes...")
  local rails_grape = require("restman.integrations.rails_grape")
  rails_grape.load_routes(opts, function(grape_routes)
    if not grape_routes or #grape_routes == 0 then
      log.warn("Detected mounted Grape API, but grape:routes could not be loaded; Rails routes may be incomplete")
      base_routes = sort_routes_by_api(base_routes or {})
      callback(base_routes)
      return
    end

    log.info("Restman: loaded " .. #(grape_routes or {}) .. " Grape routes")
    log.info("Restman: " .. #(base_routes or {}) .. " Rails routes")

    -- Prioritize Grape routes (API) first, then add Rails routes (sorted by /api)
    local sorted_base = sort_routes_by_api(base_routes or {})
    local merged = merge_routes(grape_routes, sorted_base)

    log.info("Restman: merged to " .. #merged .. " total routes")
    callback(merged)
  end)
end

local function load_from_command(project_root, cache_file, opts, callback)
  local cfg = config.get()
  local cmd = vim.split(cfg.rails.command or "bin/rails routes", "%s+", { trimempty = true })

  ensure_cache_dir(cache_file)
  ensure_gitignore(project_root)
  log.info("Loading rails routes...")

  vim.system(cmd, { cwd = project_root, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or "")
        log.error("rails routes failed" .. (stderr ~= "" and (": " .. stderr) or ""))
        load_optional_grape_routes(project_root, nil, opts, callback)
        return
      end

      local stdout = result.stdout or ""
      vim.fn.writefile(vim.split(stdout, "\n", { plain = true }), cache_file)
      local routes = parse_routes_output(stdout)
      load_optional_grape_routes(project_root, routes, opts, callback)
    end)
  end)
end

function M.send_route(route)
  local parser = require("restman.parser")
  local env = require("restman.env")
  local project_root = get_project_root()
  local routes_file = get_routes_file(project_root)
  local request = {
    method = route.verb,
    url = route.path,
    headers = {},
    source = {
      file = routes_file,
      line = 1,
    },
  }

  parser.resolve_dynamic_params(request.url, routes_file, function(resolved_url)
    request.url = resolved_url
    env.apply_to_async(
      request,
      { project_root = project_root, force_detect = true },
      function(resolved_request)
        send_request(resolved_request)
      end
    )
  end)
end

function M.load_routes(opts, callback)
  opts = opts or {}
  local project_root = get_project_root()
  local routes_file = get_routes_file(project_root)

  if vim.fn.filereadable(routes_file) == 0 then
    log.error("Not a Rails project (config/routes.rb not found)")
    callback(nil)
    return
  end

  local cache_file = get_cache_file(project_root)
  if opts.refresh then
    os.remove(cache_file)
    require("restman.env").clear_base_url_cache(project_root)
  end

  local started_at = vim.uv.hrtime()
  local cached_routes = read_cached_routes(cache_file)
  if cached_routes then
    if cache_is_stale(routes_file, cache_file) then
      log.warn("routes.rb has changed, run :Restman rails refresh")
    end
    M._last_cache_read_ns = vim.uv.hrtime() - started_at
    load_optional_grape_routes(project_root, cached_routes, opts, callback)
    return
  end

  load_from_command(project_root, cache_file, opts, callback)
end

function M.open(opts)
  M.load_routes(opts, function(routes)
    if not routes or #routes == 0 then
      return
    end
    open_picker(routes)
  end)
end

detect_grape_mount = function(project_root)
  local routes_file = get_routes_file(project_root)
  if vim.fn.filereadable(routes_file) == 0 then
    return false
  end

  local content = table.concat(vim.fn.readfile(routes_file), "\n")

  -- Look for common patterns like mount Api::Base => "/" or mount Api::Base => '/'
  local patterns = {
    "mount%s+[^%s]+::Base%s+=>%s+[\"'][^\"']+[\"']",
    "mount%s+[^%s]+::V[0-9]+::Base%s+=>%s+[\"'][^\"']+[\"']",
  }

  for _, pattern in ipairs(patterns) do
    if content:match(pattern) then
      return true
    end
  end

  return false
end

M._find_project_root = find_project_root
M._get_current_dir = get_current_dir
M._parse_route_line = parse_route_line
M._parse_routes_output = parse_routes_output
M._cache_is_stale = cache_is_stale
M._get_cache_file = get_cache_file
M._format_route_for_picker = format_route_for_picker
M._merge_routes = merge_routes
M._sort_routes_by_api = sort_routes_by_api
M.detect_grape_mount = detect_grape_mount

return M
