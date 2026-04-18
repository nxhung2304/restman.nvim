local M = {}

---Check Neovim version requirement
local function check_neovim_version()
  local version = vim.version()
  local required_major, required_minor = 0, 10

  if version.major > required_major or (version.major == required_major and version.minor >= required_minor) then
    vim.health.report_ok(string.format("Neovim %s", version.string))
  else
    vim.health.report_warn(string.format("Neovim %s (requires ≥ 0.10)", version.string))
  end
end

---Check curl CLI availability
local function check_curl_executable()
  if vim.fn.executable("curl") == 1 then
    local ok, output = pcall(function()
      return vim.fn.system("curl --version 2>&1"):match("curl ([0-9.]+)")
    end)
    if ok and output then
      vim.health.report_ok(string.format("curl %s", output))
    else
      vim.health.report_ok("curl available")
    end
  else
    vim.health.report_error("curl not found (required for sending requests)")
  end
end

---Check environment file and active env
local function check_env_file()
  -- Find project root locally
  local ok, env_module = pcall(require, "restman.env")
  if not ok then
    vim.health.report_info("Environment: unable to load env module")
    return
  end

  local project_root = env_module._find_project_root(vim.uv.cwd())
  if not project_root then
    vim.health.report_info("Environment: no .env.json (working outside git repository)")
    return
  end

  local env_file = project_root .. "/.env.json"
  if vim.fn.filereadable(env_file) == 0 then
    vim.health.report_warn(string.format("Environment: .env.json not found at %s", env_file))
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
        vim.health.report_ok(string.format("Environment: loaded (%d variables)", var_count))
      else
        vim.health.report_warn(string.format("Environment: invalid JSON at %s", env_file))
      end
    else
      vim.health.report_warn(string.format("Environment: .env.json empty at %s", env_file))
    end
  end
end

---Check Telescope availability (optional)
local function check_telescope()
  local ok = pcall(require, "telescope.pickers")
  if ok then
    vim.health.report_ok("Telescope available")
  else
    vim.health.report_info("Telescope not found. Fallback to vim.ui.select")
  end
end

---Check history file
local function check_history_file()
  local ok, config_module = pcall(require, "restman.config")
  if not ok then
    vim.health.report_info("History: unable to load config module")
    return
  end

  local cfg = config_module.get()
  local history_path = cfg.history.file or (vim.fn.stdpath("data") .. "/restman/history.json")

  if vim.fn.filereadable(history_path) == 0 then
    vim.health.report_info("History: not created yet (0 entries, 0 B)")
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
      vim.health.report_ok(string.format("History: %d entries, %.1f KB", entry_count, size_kb))
    else
      vim.health.report_warn(string.format("History: invalid JSON at %s", history_path))
    end
  else
    vim.health.report_info("History: file empty (0 entries, 0 B)")
  end
end

---Check if Rails project
local function check_rails_project()
  local ok, env_module = pcall(require, "restman.env")
  if not ok then
    vim.health.report_info("Rails: unable to load env module")
    return
  end

  local project_root = env_module._find_project_root(vim.uv.cwd())
  if not project_root then
    vim.health.report_info("Rails: not a Rails project (no git root)")
    return
  end

  local config_routes = project_root .. "/config/routes.rb"
  if vim.fn.filereadable(config_routes) == 1 then
    vim.health.report_ok("Rails project detected")
  else
    vim.health.report_info("Rails: not a Rails project (config/routes.rb not found)")
  end
end

---Run all health checks
function M.check()
  -- Ensure vim.health is available in this context
  if not (vim and vim.health and vim.health.report_start) then
    error("vim.health not properly initialized - ensure this is called by Neovim's health system")
  end

  vim.health.report_start("restman.nvim")

  local checks = {
    check_neovim_version,
    check_curl_executable,
    check_env_file,
    check_telescope,
    check_history_file,
    check_rails_project,
  }

  for _, check_fn in ipairs(checks) do
    local ok, err = pcall(check_fn)
    if not ok then
      vim.health.report_warn(string.format("Check failed: %s", err))
    end
  end

  vim.health.report_finish()
end

return M
