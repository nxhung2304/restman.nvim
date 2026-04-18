local function test_check_function_exists()
  local health = require("restman.health")
  assert(health.check ~= nil, "health.check() should be exported")
  assert(type(health.check) == "function", "health.check should be a function")
  print("✓ health.check() exists")
end

local function test_check_runs_without_error()
  local health = require("restman.health")
  -- This should not throw an error
  local ok = pcall(function()
    health.check()
  end)
  assert(ok, "health.check() should run without error")
  print("✓ health.check() runs without error")
end

-- Run tests
test_check_function_exists()
test_check_runs_without_error()

print("\n✅ All health module tests passed")
