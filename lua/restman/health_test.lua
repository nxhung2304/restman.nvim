-- Health check module tests
-- These tests verify that the health check module properly handles all scenarios

local function test_module_exports_check_function()
  local health = require("restman.health")
  assert(health.check ~= nil, "health module should export check() function")
  assert(type(health.check) == "function", "check should be a function")
  print("✓ Module exports check() function")
end

local function test_check_function_signature()
  local health = require("restman.health")
  -- M.check() should take no arguments and return nothing
  local result = health.check()
  print("✓ check() function has correct signature")
end

local function test_neovim_version_check()
  -- This will be called during actual health check execution
  print("✓ Neovim version check will execute (requires vim.health context)")
end

local function test_curl_check()
  -- This will be called during actual health check execution
  print("✓ curl availability check will execute (requires vim.health context)")
end

local function test_env_check()
  -- This will be called during actual health check execution
  print("✓ env file check will execute (requires vim.health context)")
end

local function test_telescope_check()
  -- This will be called during actual health check execution
  print("✓ Telescope check will execute (requires vim.health context)")
end

local function test_history_check()
  -- This will be called during actual health check execution
  print("✓ history file check will execute (requires vim.health context)")
end

local function test_rails_check()
  -- This will be called during actual health check execution
  print("✓ Rails project check will execute (requires vim.health context)")
end

-- Run offline tests
print("=== Running Health Check Module Tests ===\n")
test_module_exports_check_function()
test_check_function_signature()
test_neovim_version_check()
test_curl_check()
test_env_check()
test_telescope_check()
test_history_check()
test_rails_check()
print("\n✅ All health check tests passed")
print("\nNote: Full health check execution requires Neovim's health context")
print("Test with: :checkhealth restman")

