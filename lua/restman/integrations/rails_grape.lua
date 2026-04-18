local M = {}

local config = require("restman.config")
local log = require("restman.log")
local picker = require("restman.ui.picker")
local http_client = require("restman.http_client")
local buffer = require("restman.ui.buffer")
local view = require("restman.ui.view")
local history = require("restman.history")
local parser = require("restman.parser")
local env = require("restman.env")
local commands = require("restman.commands")

-- Re-use functions from rails.lua or define new ones specific to Grape
local rails_integration = require("restman.integrations.rails")

local find_project_root = rails_integration._find_project_root
local get_project_root = function()
  return find_project_root(rails_integration._get_current_dir())
end

local function get_grape_cache_file(project_root)
  local cfg = config.get()
  return cfg.rails.grape_cache_file or (project_root .. "/.cache/restman/rails_grape_routes.txt")
end

local function ensure_cache_dir(cache_file)
  vim.fn.mkdir(vim.fn.fnamemodify(cache_file, ":h"), "p")
end

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

local function compare_mtime(a, b)
  local a_sec = a.sec or 0
  local b_sec = b.sec or 0
  if a_sec ~= b_sec then
    return a_sec - b_sec
  end
  return (a.nsec or 0) - (b.nsec or 0)
end

local function normalize_verb(value)
  if not value then
    return nil
  end
  local upper = tostring(value):upper()
  return HTTP_METHODS[upper] and upper or nil
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

local function parse_grape_route_line(line)
  if not line or line == "" then
    return nil
  end

  local trimmed = vim.trim(line)
  if trimmed == "" or trimmed:match("^Prefix%s+Verb%s+") or trimmed:match("^HTTP%s+PATH") then
    return nil
  end

  -- Handle both formats:
  -- 1. Space-separated: GET /api/users(.:format) Api::Users#index
  -- 2. Pipe-separated: GET  |  /oauth/token(.:format)  |  ...  |  Description

  local verb, path, action

  if line:find("|") then
    -- Pipe-separated format from grape:routes
    local parts = vim.split(line, "|", { trimempty = true })
    if #parts < 2 then
      return nil
    end
    verb = normalize_verb(vim.trim(parts[1]))
    path = normalize_path(vim.trim(parts[2]))
    -- Try to get description from parts[3] or parts[4]
    action = vim.trim(parts[#parts] or "")
    if action == "" then
      action = "Grape API"
    end
  else
    -- Space-separated format
    local columns = vim.split(trimmed, "%s+", { trimempty = true })
    if #columns < 2 then
      return nil
    end
    verb = normalize_verb(columns[1])
    path = normalize_path(columns[2] or "")
    action = columns[#columns] or "Grape API"
  end

  if not verb or path == "" then
    return nil
  end

  return {
    verb = verb,
    path = path,
    action = action,
  }
end

local function parse_grape_routes_output(content)
  local routes = {}
  for _, line in ipairs(vim.split(content or "", "\n", { trimempty = true })) do
    local route = parse_grape_route_line(line)
    if route then
      table.insert(routes, route)
    end
  end
  return routes
end

local function read_cached_grape_routes(cache_file)
  if vim.fn.filereadable(cache_file) == 0 then
    return nil
  end
  local lines = vim.fn.readfile(cache_file)
  return parse_grape_routes_output(table.concat(lines, "\n"))
end

local function grape_cache_is_stale(project_root, cache_file)
  local routes_file = project_root .. "/config/routes.rb"
  local routes_stat = vim.uv.fs_stat(routes_file)
  local cache_stat = vim.uv.fs_stat(cache_file)
  if not routes_stat or not cache_stat or not routes_stat.mtime or not cache_stat.mtime then
    return false
  end
  return compare_mtime(routes_stat.mtime, cache_stat.mtime) > 0
end

local function format_grape_route_for_picker(route, description_format)
  description_format = description_format or " → %s"
  local desc_part = ""
  if route.action and route.action ~= "" and route.action ~= "Grape API" then
    desc_part = string.format(description_format, route.action)
  end
  return string.format("%-6s %s%s", route.verb, route.path, desc_part)
end

local function open_picker(routes)
  local cfg = config.get()
  local description_format = cfg.rails.grape_description_format or " → %s"

  picker.pick({
    items = routes,
    title = "Grape Routes",
    format = function(route)
      return format_grape_route_for_picker(route, description_format)
    end,
    on_select = function(route)
      M.send_route(route)
    end,
  })
end

local function send_request(request)
  commands._last = { request = request }

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

local function load_from_command(project_root, cache_file, callback)
  local cfg = config.get()
  local cmd = vim.split(cfg.rails.grape_command or "bundle exec rake grape:routes", "%s+", { trimempty = true })

  ensure_cache_dir(cache_file)
  log.info("Loading Grape routes...")

  vim.system(cmd, { cwd = project_root, text = true }, function(result)
    vim.schedule(function()
      if result.code ~= 0 then
        local stderr = vim.trim(result.stderr or "")
        log.error("grape:routes failed" .. (stderr ~= "" and (": " .. stderr) or ""))
        callback(nil)
        return
      end

      local stdout = result.stdout or ""
      vim.fn.writefile(vim.split(stdout, "\n", { plain = true }), cache_file)
      callback(parse_grape_routes_output(stdout))
    end)
  end)
end

function M.send_route(route)
  local project_root = get_project_root()
  local request = {
    method = route.verb,
    url = route.path,
    headers = {},
    source = {
      file = "Grape API", -- Placeholder for source file
      line = 1,
    },
  }

  parser.resolve_dynamic_params(request.url, "Grape API", function(resolved_url) -- Placeholder for source file
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
  local routes_file = project_root .. "/config/routes.rb"

  if vim.fn.filereadable(routes_file) == 0 then
    log.error("Not a Rails project (config/routes.rb not found)")
    callback(nil)
    return
  end

  local cache_file = get_grape_cache_file(project_root)
  if opts.refresh then
    os.remove(cache_file)
    env.clear_base_url_cache(project_root)
  end

  local started_at = vim.uv.hrtime()
  local cached_routes = read_cached_grape_routes(cache_file)
  if cached_routes then
    if grape_cache_is_stale(project_root, cache_file) then
      log.warn("Grape routes might be stale, run :Restman rails grape refresh")
    end
    M._last_cache_read_ns = vim.uv.hrtime() - started_at
    callback(cached_routes)
    return
  end

  load_from_command(project_root, cache_file, callback)
end

function M.open(opts)
  M.load_routes(opts, function(routes)
    if not routes or #routes == 0 then
      return
    end
    open_picker(routes)
  end)
end

M._get_grape_cache_file = get_grape_cache_file
M._parse_grape_route_line = parse_grape_route_line
M._parse_grape_routes_output = parse_grape_routes_output
M._format_grape_route_for_picker = format_grape_route_for_picker

return M
