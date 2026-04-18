local M = {}

---@class RestmanConfig
---@field keymaps table Keymaps configuration
---@field response_view ResponseViewConfig Response viewer configuration
---@field timeout number Request timeout in seconds (default: 30)
---@field history HistoryConfig History configuration
---@field rails RailsConfig Rails integration configuration

---@class ResponseViewConfig
---@field default_view "float"|"split"|"vsplit"|"tab" Default view for response
---@field float table Float window config
---@field split table Split window config

---@class HistoryConfig
---@field enabled boolean Enable history persistence
---@field file? string Path to history file (auto-generated if nil)
---@field max_entries number Maximum history entries (default: 100)
---@field deduplicate boolean Remove previous entry for same file:line before inserting (default: true)

---@class RailsConfig
---@field cache_file? string Path to cache file (auto-generated if nil)
---@field grape_cache_file? string Path to grape route cache file (auto-generated if nil)
---@field command string Command to list routes (default: "bin/rails routes")
---@field grape_command string Command to list grape routes (default: "bundle exec rake grape:routes")
---@field grape_description_format string Format for Grape route description in picker (default: " → %s")
---                                      Use %s as placeholder for description text

---@type RestmanConfig
M.defaults = {
  keymaps = {
    send = "<leader>rs",
    repeat_last = "<leader>rr",
    env = "<leader>re",
    history = "<leader>rh",
    cancel = "<leader>rc",
  },

  response_view = {
    default_view = "float",
    float = {
      relative = "editor",
      width = 0.8,
      height = 0.7,
      row = 0.5 - (0.7 / 2),
      col = 0.5 - (0.8 / 2),
      border = "rounded",
    },
    split = {
      position = "right",
      size = 80,
    },
  },

  timeout = 30,

  history = {
    enabled = true,
    file = nil, -- Will use default: vim.fn.stdpath("data") .. "/restman/history.json"
    max_entries = 100,
    deduplicate = true,
  },

  rails = {
    cache_file = nil, -- Will use default: vim.fn.stdpath("cache") .. "/restman/rails_routes.txt"
    grape_cache_file = nil, -- Will use default: project_root .. "/.cache/restman/rails_grape_routes.txt"
    command = "bin/rails routes",
    grape_command = "bundle exec rake grape:routes",
    grape_description_format = " → %s", -- Format: %s = description text
  },
}

-- Cached merged config
M._cached_config = nil

---Merge user config with defaults
---@param user_config? RestmanConfig User configuration
---@return RestmanConfig Merged configuration
function M.merge(user_config)
  if not user_config then
    return vim.deepcopy(M.defaults)
  end

  local result = vim.deepcopy(M.defaults)

  for key, value in pairs(user_config) do
    if type(value) == "table" and type(result[key]) == "table" then
      result[key] = vim.tbl_extend("force", result[key], value)
    else
      result[key] = value
    end
  end

  M._cached_config = result
  return result
end

---Get current config (returns cached merged config or defaults)
---@return RestmanConfig Current configuration
function M.get()
  return M._cached_config or vim.deepcopy(M.defaults)
end

return M
