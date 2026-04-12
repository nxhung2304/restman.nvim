-- Telescope extension for Restman

local telescope = require("telescope")
local picker = require("restman.ui.picker")
local env = require("restman.env")
local log = require("restman.log")

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
  },
})
