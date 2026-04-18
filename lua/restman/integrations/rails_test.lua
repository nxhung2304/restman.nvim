local project_root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h:h:h")
package.path = project_root .. "/lua/?.lua;" .. package.path

local rails = require("restman.integrations.rails")

local function test_case(description, test_fn)
  local success, err = pcall(test_fn)
  if success then
    print("✅ " .. description)
  else
    print("❌ " .. description .. ": " .. tostring(err))
  end
end

local function assert_eq(actual, expected, context)
  if actual ~= expected then
    error(string.format("%s: expected '%s' but got '%s'", context or "assertion", expected, actual))
  end
end

local function assert_truthy(value, context)
  if not value then
    error(string.format("%s: value is falsy", context or "assertion"))
  end
end

print("\n=== Rails Integration Tests (Issue #15) ===\n")

test_case("Parse route line with prefix", function()
  local route = rails._parse_route_line("users GET /users(.:format) users#index")
  assert_truthy(route, "route should parse")
  assert_eq(route.verb, "GET", "verb")
  assert_eq(route.path, "/users", "path")
  assert_eq(route.action, "users#index", "action")
end)

test_case("Parse route line without prefix", function()
  local route = rails._parse_route_line("PATCH/PUT  /users/:id(.:format)  users#update")
  assert_truthy(route, "route should parse")
  assert_eq(route.verb, "PATCH", "verb")
  assert_eq(route.path, "/users/:id", "path")
end)

test_case("Ignore header row", function()
  local route = rails._parse_route_line("Prefix Verb URI Pattern Controller#Action")
  assert_eq(route, nil, "header should be ignored")
end)

test_case("Parse full routes output", function()
  local routes = rails._parse_routes_output(table.concat({
    "Prefix Verb URI Pattern Controller#Action",
    "users GET /users(.:format) users#index",
    " PATCH/PUT /users/:id(.:format) users#update",
    "DELETE /users/:id(.:format) users#destroy",
  }, "\n"))

  assert_eq(#routes, 3, "route count")
  assert_eq(routes[2].verb, "PATCH", "second verb")
  assert_eq(routes[3].action, "users#destroy", "third action")
end)

test_case("Detect Grape mount in routes.rb", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local config_dir = tmp .. "/config"
  vim.fn.mkdir(config_dir, "p")
  local routes_file = config_dir .. "/routes.rb"
  vim.fn.writefile({"Rails.application.routes.draw do", "  mount Api::Base => '/'", "end"}, routes_file)

  assert_truthy(rails.detect_grape_mount(tmp), "should detect mounted Grape API")
end)

test_case("Detect stale cache by mtime", function()
  local tmp = vim.fn.tempname()
  vim.fn.mkdir(tmp, "p")
  local routes_file = tmp .. "/routes.rb"
  local cache_file = tmp .. "/rails_routes.txt"

  vim.fn.writefile({ "Rails.application.routes.draw do", "end" }, routes_file)
  vim.wait(20)
  vim.fn.writefile({ "users GET /users users#index" }, cache_file)
  assert_eq(rails._cache_is_stale(routes_file, cache_file), false, "new cache should not be stale")

  vim.wait(20)
  vim.fn.writefile({ "Rails.application.routes.draw do", "resources :users", "end" }, routes_file)
  assert_eq(rails._cache_is_stale(routes_file, cache_file), true, "updated routes should be stale")
end)

test_case("Format function for Rails controller#action", function()
  local route = {
    verb = "GET",
    path = "/users",
    action = "users#index"
  }
  local formatted = rails._format_route_for_picker(route, " → %s")
  -- Should keep original format for controller#action routes
  assert_truthy(formatted:find("GET"), "verb should be in output")
  assert_truthy(formatted:find("/users"), "path should be in output")
  assert_truthy(formatted:find("users#index"), "action should be in output")
  assert_eq(formatted:find("→"), nil, "arrow format should NOT be applied to controller#action")
end)

test_case("Format function for Grape description (arrow format)", function()
  local route = {
    verb = "POST",
    path = "/oauth/token",
    action = "Requires for an access token"  -- Description without "#"
  }
  local formatted = rails._format_route_for_picker(route, " → %s")
  -- Should apply arrow format for descriptions
  assert_truthy(formatted:find("POST"), "verb should be in output")
  assert_truthy(formatted:find("/oauth/token"), "path should be in output")
  assert_truthy(formatted:find("→"), "arrow should be in formatted output")
  assert_truthy(formatted:find("Requires for an access token"), "description should be in output")
end)

test_case("Format function with custom description format", function()
  local route = {
    verb = "POST",
    path = "/api/v1/auth",
    action = "User authentication endpoint"  -- Description
  }
  local formatted = rails._format_route_for_picker(route, " | %s")
  -- Should use pipe format instead of arrow
  assert_truthy(formatted:find("POST"), "verb should be in output")
  assert_truthy(formatted:find("/api/v1/auth"), "path should be in output")
  assert_truthy(formatted:find("|"), "pipe should be in formatted output")
  assert_truthy(formatted:find("User authentication endpoint"), "description should be in output")
end)

test_case("Format function with bracket description format", function()
  local route = {
    verb = "DELETE",
    path = "/users/:id",
    action = "Remove user account"
  }
  local formatted = rails._format_route_for_picker(route, " [%s]")
  -- Should use bracket format
  assert_truthy(formatted:find("DELETE"), "verb should be in output")
  assert_truthy(formatted:find("/users/:id"), "path should be in output")
  assert_truthy(formatted:find("%["), "opening bracket should be in output")
  assert_truthy(formatted:find("%]"), "closing bracket should be in output")
  assert_truthy(formatted:find("Remove user account"), "description should be in output")
end)

test_case("Merge routes removes duplicates correctly", function()
  local base_routes = {
    { verb = "GET", path = "/users", action = "users#index" },
    { verb = "POST", path = "/users", action = "users#create" },
    { verb = "PUT", path = "/api/user", action = "Grape description here" },  -- Duplicate with different action
  }
  local extra_routes = {
    { verb = "PUT", path = "/api/user", action = "users#update" },  -- Duplicate (verb+path same)
    { verb = "DELETE", path = "/users/:id", action = "users#destroy" },
  }

  local merged = rails._merge_routes(base_routes, extra_routes)
  -- Should have 4 routes: GET /users, POST /users, PUT /api/user, DELETE /users/:id
  assert_eq(#merged, 4, "merged should have 4 routes (1 duplicate removed)")

  -- Verify correct routes are present
  local verb_paths = {}
  for _, route in ipairs(merged) do
    table.insert(verb_paths, route.verb .. " " .. route.path)
  end
  assert_truthy(table.concat(verb_paths, ","):find("GET /users"), "GET /users should be present")
  assert_truthy(table.concat(verb_paths, ","):find("POST /users"), "POST /users should be present")
  assert_truthy(table.concat(verb_paths, ","):find("PUT /api/user"), "PUT /api/user should be present")
  assert_truthy(table.concat(verb_paths, ","):find("DELETE /users/:id"), "DELETE /users/:id should be present")
end)

test_case("Sort routes prioritizes /api paths", function()
  local routes = {
    { verb = "GET", path = "/users", action = "users#index" },
    { verb = "GET", path = "/api/v1/users", action = "api_users#index" },
    { verb = "GET", path = "/admin/users", action = "admin_users#index" },
    { verb = "GET", path = "/api/v2/products", action = "api_products#index" },
  }

  local sorted = rails._sort_routes_by_api(routes)
  -- First two should have /api in path
  assert_truthy(sorted[1].path:find("/api"), "first route should have /api")
  assert_truthy(sorted[2].path:find("/api"), "second route should have /api")
  -- Last two should NOT have /api in path
  assert_eq(sorted[3].path:find("/api"), nil, "third route should NOT have /api")
  assert_eq(sorted[4].path:find("/api"), nil, "fourth route should NOT have /api")
end)

print("\n=== Rails Integration Tests Complete ===\n")
