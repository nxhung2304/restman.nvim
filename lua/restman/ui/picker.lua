-- UI Picker layer — abstraction for Telescope + vim.ui.select fallback

local M = {}
local log = require("restman.log")

-- Cache telescope availability (nil=unchecked, true/false after first check)
M._has_telescope = nil
M._current_mode = "float"

---Check if Telescope is available (cached)
---@return boolean True if telescope.pickers is available
local function check_telescope()
  if M._has_telescope == nil then
    local ok = pcall(require, "telescope.pickers")
    M._has_telescope = ok
  end
  return M._has_telescope
end

---Pick an item from a list (Telescope if available, vim.ui.select as fallback)
---@param opts table Options: { items, format, on_select, on_secondary?, title }
function M.pick(opts)
  opts = opts or {}

  if check_telescope() then
    -- Telescope path
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")

    pickers
      .new({}, {
        prompt_title = opts.title or "Select",
        finder = finders.new_table({
          results = opts.items,
          entry_maker = function(item)
            return {
              value = item,
              display = opts.format and opts.format(item) or tostring(item),
              ordinal = opts.format and opts.format(item) or tostring(item),
            }
          end,
        }),
        sorter = conf.generic_sorter({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel and opts.on_select then
              opts.on_select(sel.value)
            end
          end)
          map("i", "<C-o>", function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if sel and opts.on_secondary then
              opts.on_secondary(sel.value)
            end
          end)
          return true
        end,
      })
      :find()
  else
    -- Fallback: vim.ui.select
    if opts.on_secondary then
      log.info("picker: upgrade to Telescope for <C-o> secondary action support")
    end
    vim.ui.select(opts.items, {
      prompt = opts.title,
      format_item = opts.format or tostring,
    }, function(choice)
      if choice and opts.on_select then
        opts.on_select(choice)
      end
    end)
  end
end

---Open picker for response buffer list
function M.open_buffer_list()
  local buffer = require("restman.ui.buffer")
  local entries = buffer.list()

  if #entries == 0 then
    log.info("picker: no response buffers in history")
    return
  end

  M.pick({
    items = entries,
    title = "Response Buffers",
    format = function(entry)
      local req = entry.request
      return string.format("[%d] %s %s", entry.index, req.method or "?", req.url or "?")
    end,
    on_select = function(entry)
      local view = require("restman.ui.view")
      local mode = (view._current and view._current.mode) or M._current_mode
      view.open(entry.bufnr, mode)
    end,
  })
end

return M
