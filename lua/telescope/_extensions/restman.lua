-- Telescope extension for Restman

local env = require("restman.env")
local log = require("restman.log")
local picker = require("restman.ui.picker")
local rails = require("restman.integrations.rails")
local telescope = require("telescope")

return telescope.register_extension({
  exports = {
    history = function()
      -- Stub: history picker will be implemented in issue #14
      log.info("history: not implemented yet, see issue #14")
    end,
    env = function()
      -- Environment picker
      picker.pick({
        items = env.list(),
        title = "Select Environment",
        format = function(name)
          return name
        end,
        on_select = env.set_active,
      })
    end,
    rails_routes = function()
      rails.open()
    end,
  },
})
