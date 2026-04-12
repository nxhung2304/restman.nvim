-- Commands & keymaps — :Restman dispatcher and subcommand handlers

local M = {}
local log = require("restman.log")

-- Module state: last request sent
M._last = nil

---Register the :Restman user command
function M.register()
  vim.api.nvim_create_user_command("Restman", M._dispatch, {
    nargs = "*",
    range = true,
    complete = M._complete,
    desc = "Restman REST client",
  })
end

---Main command dispatcher
---@param opts table Command options from nvim_create_user_command
local function _dispatch(opts)
  local sub = opts.fargs[1]

  if sub == "send" then
    M._send(opts)
  elseif sub == "repeat" then
    M._repeat()
  elseif sub == "env" then
    M._env()
  elseif sub == "history" then
    M._history()
  elseif sub == "cancel" then
    M._cancel()
  elseif sub == "rails" then
    M._rails(opts)
  elseif sub == "health" then
    vim.cmd("checkhealth restman")
  else
    if sub then
      log.warn("Restman: unknown subcommand '" .. tostring(sub) .. "'")
    else
      log.info("Restman: available subcommands: send, repeat, env, history, cancel, rails, health")
    end
  end
end

---Send request subcommand
---@param opts table Command options with range support
function M._send(opts)
  local http_client = require("restman.http_client")
  local buffer = require("restman.ui.buffer")
  local view = require("restman.ui.view")
  local parser = require("restman.parser")
  local env = require("restman.env")
  local config = require("restman.config")

  local function do_send()
    local bufnr = 0  -- Current buffer
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local visual_block = nil

    -- Range support: collect visual block as body
    if opts.range > 0 then
      local vlines = vim.api.nvim_buf_get_lines(bufnr, opts.line1 - 1, opts.line2, false)
      visual_block = table.concat(vlines, "\n")
      line = opts.line1
    end

    -- Parse request
    parser.parse_current_line(bufnr, line, { visual_block = visual_block }, function(request)
      if not request then
        log.warn("Restman: no request found at cursor")
        return
      end

      -- Apply environment
      request = env.apply_to(request)
      M._last = { request = request }

      -- Send request
      http_client.send(request, function(response)
        -- Schedule on main thread
        vim.schedule(function()
          local resp_bufnr = buffer.create(request, response)
          local cfg = config.get()
          view.open(resp_bufnr, cfg.response_view.default_view)
        end)
      end)
    end)
  end

  -- Check for pending request
  if http_client.is_pending() then
    vim.ui.input({ prompt = "Cancel previous request? [y/N] " }, function(input)
      if input and input:lower() == "y" then
        http_client.cancel()
        do_send()
      end
    end)
    return
  end

  do_send()
end

---Repeat last request subcommand
function M._repeat()
  if not M._last then
    log.warn("Restman: no previous request to repeat")
    return
  end

  local http_client = require("restman.http_client")
  local buffer = require("restman.ui.buffer")
  local view = require("restman.ui.view")
  local config = require("restman.config")

  http_client.send(M._last.request, function(response)
    vim.schedule(function()
      local resp_bufnr = buffer.create(M._last.request, response)
      local cfg = config.get()
      view.open(resp_bufnr, cfg.response_view.default_view)
    end)
  end)
end

---Select environment subcommand
function M._env()
  local picker = require("restman.ui.picker")
  local env = require("restman.env")

  picker.pick({
    items = env.list(),
    title = "Select Environment",
    format = function(name)
      return name
    end,
    on_select = function(name)
      if not env.set_active(name) then
        log.warn("Restman: environment '" .. name .. "' not found")
      else
        log.info("Restman: switched to environment '" .. name .. "'")
      end
    end,
  })
end

---History subcommand (stub for issue #14)
function M._history()
  log.info("Restman: history not implemented yet, see issue #14")
end

---Cancel request subcommand
function M._cancel()
  local http_client = require("restman.http_client")
  if http_client.is_pending() then
    http_client.cancel()
    log.info("Restman: request cancelled")
  else
    log.info("Restman: no request in flight")
  end
end

---Rails subcommand (stub for issue #15)
---@param opts table Command options
function M._rails(opts)
  local sub_sub = opts.fargs[2]
  if sub_sub == "refresh" then
    log.info("Restman: rails refresh not implemented yet, see issue #15")
  else
    log.info("Restman: rails not implemented yet, see issue #15")
  end
end

---Tab completion for :Restman command
---@param arg string Current argument being completed
---@param line string Full command line
---@param pos number Cursor position in line
---@return string[] List of completions
function M._complete(_arg, line, _pos)
  local args = vim.split(line, "%s+")

  -- Subcommand completion
  if #args <= 2 then
    return { "send", "repeat", "env", "history", "cancel", "rails", "health" }
  end

  -- Sub-subcommand completion (e.g., rails refresh)
  if args[2] == "rails" then
    return { "refresh" }
  end

  return {}
end

---Register default keymaps
---@param cfg RestmanConfig Configuration table
function M.register_keymaps(cfg)
  local km = cfg.keymaps
  local opts = { silent = true, noremap = true }

  vim.keymap.set({ "n", "v" }, km.send, "<cmd>Restman send<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: send request" }))
  vim.keymap.set("n", km.repeat_last, "<cmd>Restman repeat<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: repeat last" }))
  vim.keymap.set("n", km.env, "<cmd>Restman env<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: select env" }))
  vim.keymap.set("n", km.history, "<cmd>Restman history<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: history" }))
  vim.keymap.set("n", km.cancel, "<cmd>Restman cancel<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: cancel" }))
end

-- Expose dispatcher for command registration
M._dispatch = _dispatch

return M
