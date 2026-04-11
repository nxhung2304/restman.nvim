local config = require("restman.config")
local log = require("restman.log")

local M = {}

---@class RestmanModule
---@field setup function Setup function
---@field config RestmanConfig Current configuration

---Check Neovim version
---@return boolean True if Neovim version >= 0.10
local function check_version()
  local version = vim.version()
  local required = { 0, 10, 0 }

  if version.major > required[1] then
    return true
  end
  if version.major == required[1] and version.minor >= required[2] then
    return true
  end

  return false
end

---Setup restman.nvim
---@param user_config? RestmanConfig User configuration
---@return boolean success True if setup succeeded
function M.setup(user_config)
  if not check_version() then
    log.error("restman.nvim requires Neovim >= 0.10. Current version: " .. vim.version().string)
    return false
  end

  M.config = config.merge(user_config)
  log.info("restman.nvim loaded successfully")

  return true
end

---Module API export
M.log = log
M.config_module = config

return M
