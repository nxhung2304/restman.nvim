local health = require('vim.health')
local M = {}

---Check Neovim version requirement
local function check_neovim_version()
  local version = vim.version()
  local required_major, required_minor = 0, 10
  local version_str = string.format("%d.%d.%d", version.major, version.minor, version.patch)

  if version.major > required_major or (version.major == required_major and version.minor >= required_minor) then
    health.ok("Neovim " .. version_str)
  else
    health.warn("Neovim " .. version_str .. " (requires ≥ 0.10)")
  end
end

---Check curl CLI availability
local function check_curl_executable()
  if vim.fn.executable("curl") == 1 then
    local ok, output = pcall(function()
      return vim.fn.system("curl --version 2>&1"):match("curl ([0-9.]+)")
    end)
    if ok and output then
      health.ok(string.format("curl %s", output))
    else
      health.ok("curl available")
    end
  else
    health.error("curl not found (required for sending requests)")
  end
end

---Check environment file and active env
local function check_env_file()
  -- Find project root locally
  local ok, env_module = pcall(require, "restman.env")
  if not ok then
    health.info("Environment: unable to load env module")
    return
  end

  local project_root = env_module._find_project_root(vim.uv.cwd())
  if not project_root then
    health.info("Environment: no .env.json (working outside git repository)")
    return
  end

  local env_file = project_root .. "/.env.json"
  if vim.fn.filereadable(env_file) == 0 then
    health.warn(string.format("Environment: .env.json not found at %s", env_file))
  else
    local file_ok, data = pcall(function()
      return vim.fn.readfile(env_file)
    end)
    if file_ok and #data > 0 then
      local content = table.concat(data, "")
      local json_ok, json_data = pcall(vim.json.decode, content)
      if json_ok and json_data then
        local var_count = 0
        for _ in pairs(json_data) do
          var_count = var_count + 1
        end
        health.ok(string.format("Environment: loaded (%d variables)", var_count))
      else
        health.warn(string.format("Environment: invalid JSON at %s", env_file))
      end
    else
      health.warn(string.format("Environment: .env.json empty at %s", env_file))
    end
  end
end

---Check Telescope availability (optional)
local function check_telescope()
  local ok = pcall(require, "telescope.pickers")
  if ok then
    health.ok("Telescope available")
  else
    health.info("Telescope not found. Fallback to vim.ui.select")
  end
end

---Check template generator
local function check_template_generator()
  local ok, template_module = pcall(require, "restman.template")
  if not ok then
    health.warn("Template generator: unable to load template module")
    return
  end

  local methods = template_module.list_methods()
  if methods and #methods > 0 then
    health.ok(string.format("Template generator: %d methods available", #methods))
  else
    health.warn("Template generator: no methods found")
  end
end

---Check history file
local function check_history_file()
  local ok, config_module = pcall(require, "restman.config")
  if not ok then
    health.info("History: unable to load config module")
    return
  end

  local cfg = config_module.get()
  local history_path = cfg.history.file or (vim.fn.stdpath("data") .. "/restman/history.json")

  if vim.fn.filereadable(history_path) == 0 then
    health.info("History: not created yet (0 entries, 0 B)")
    return
  end

  local file_ok, data = pcall(function()
    return vim.fn.readfile(history_path)
  end)
  if file_ok and #data > 0 then
    local content = table.concat(data, "")
    local json_ok, json_data = pcall(vim.json.decode, content)
    if json_ok and json_data then
      local entry_count = #json_data
      local stat = vim.loop.fs_stat(history_path)
      local size_kb = stat and (stat.size / 1024) or 0
      health.ok(string.format("History: %d entries, %.1f KB", entry_count, size_kb))
    else
      health.warn(string.format("History: invalid JSON at %s", history_path))
    end
  else
    health.info("History: file empty (0 entries, 0 B)")
  end
end

---Check if Rails project
local function check_rails_project()
  local ok, env_module = pcall(require, "restman.env")
  if not ok then
    health.info("Rails: unable to load env module")
    return
  end

  local project_root = env_module._find_project_root(vim.uv.cwd())
  if not project_root then
    health.info("Rails: not a Rails project (no git root)")
    return
  end

  local config_routes = project_root .. "/config/routes.rb"
  if vim.fn.filereadable(config_routes) == 1 then
    health.ok("Rails project detected")
  else
    health.info("Rails: not a Rails project (config/routes.rb not found)")
  end
end

---Run all health checks
function M.check()
  health.start("restman.nvim")

  local checks = {
    check_neovim_version,
    check_curl_executable,
    check_env_file,
    check_telescope,
    check_template_generator,
    check_history_file,
    check_rails_project,
  }

  for _, check_fn in ipairs(checks) do
    local ok, err = pcall(check_fn)
    if not ok then
      health.warn(string.format("Check failed: %s", err))
    end
  end
end

return M
