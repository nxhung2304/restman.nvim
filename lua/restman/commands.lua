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
    if opts.fargs[2] == "clear" then
      M._history_clear()
    else
      M._history()
    end
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
    local bufnr = 0 -- Current buffer
    local line = vim.api.nvim_win_get_cursor(0)[1]
    local visual_block = nil

    -- Range support: collect visual block as body
    if opts.range > 0 then
      local vlines = vim.api.nvim_buf_get_lines(bufnr, opts.line1 - 1, opts.line2, false)

      -- Scan visual block for request line (can be at any position)
      local found_request_line = false
      local request_line_idx = nil -- Index in vlines (1-based)

      for i, vline in ipairs(vlines) do
        local actual_line_number = opts.line1 + i - 1
        if parser.parse(vline, actual_line_number, vim.api.nvim_buf_get_name(bufnr)) then
          line = actual_line_number
          found_request_line = true
          request_line_idx = i
          break
        end
      end

      -- If not found in selection, scan upward from before selection
      if not found_request_line then
        for scan_line = opts.line1 - 1, math.max(1, opts.line1 - 50), -1 do
          local candidate_lines = vim.api.nvim_buf_get_lines(bufnr, scan_line - 1, scan_line, false)
          if #candidate_lines > 0 then
            local parser_result =
              parser.parse(candidate_lines[1], scan_line, vim.api.nvim_buf_get_name(bufnr))
            if parser_result then
              line = scan_line
              found_request_line = true
              break
            end
          end
        end
      end

      if not found_request_line then
        log.warn("Restman: no request line found in or above visual selection")
        return
      end

      -- Extract body from visual block
      if request_line_idx then
        -- Request line found within visual block: extract body after request line + headers
        local body_start_idx = request_line_idx + 1
        -- Skip header lines until blank line or JSON/XML start
        for i = request_line_idx + 1, #vlines do
          local line_content = vim.trim(vlines[i])
          if line_content == "" or line_content:match("^[{%[]") or line_content:match("^<") then
            body_start_idx = i
            break
          end
        end
        -- Reconstruct body from body_start_idx onward
        local body_lines = {}
        for i = body_start_idx, #vlines do
          table.insert(body_lines, vlines[i])
        end
        visual_block = table.concat(body_lines, "\n")
      else
        -- Request line is above selection: entire visual block is body
        visual_block = table.concat(vlines, "\n")
      end
    end

    -- Parse request
    parser.parse_current_line(bufnr, line, { visual_block = visual_block }, function(request)
      if not request then
        log.warn("Restman: no request found at cursor")
        return
      end

      env.apply_to_async(request, function(resolved_request)
        M._last = { request = resolved_request }

        -- Send request
        http_client.send(resolved_request, function(response)
          -- Schedule on main thread
          vim.schedule(function()
            local resp_bufnr = buffer.create(resolved_request, response)
            local cfg = config.get()
            view.open(resp_bufnr, cfg.response_view.default_view)
            -- Persist to history (only on successful response with a status code)
            if response.status then
              local history = require("restman.history")
              history.append(resolved_request, response, resp_bufnr)
            end
          end)
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
  local request
  if M._last then
    request = M._last.request
  else
    -- Fallback to history when RAM state is lost (e.g. after restart)
    local history = require("restman.history")
    local last_entry = history.last()
    if not last_entry or not last_entry.request then
      log.warn("Restman: no previous request to repeat")
      return
    end
    request = last_entry.request
  end

  local http_client = require("restman.http_client")
  local buffer = require("restman.ui.buffer")
  local view = require("restman.ui.view")
  local config = require("restman.config")

  http_client.send(request, function(response)
    vim.schedule(function()
      local resp_bufnr = buffer.create(request, response)
      local cfg = config.get()
      view.open(resp_bufnr, cfg.response_view.default_view)
      if response.status then
        local history = require("restman.history")
        history.append(request, response, resp_bufnr)
      end
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

---History subcommand — open history picker
function M._history()
  local history = require("restman.history")
  history.open_picker()
end

---Clear all history entries
function M._history_clear()
  local history = require("restman.history")
  history.clear()
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
  local rails = require("restman.integrations.rails")
  rails.open({ refresh = opts.fargs[2] == "refresh" })
end

---Tab completion for :Restman command
---@param arg string Current argument being completed
---@param line string Full command line
---@return string[] List of completions
function M._complete(arg, line)
  local args = vim.split(line, "%s+")

  local function filter(candidates)
    if arg == "" then
      return candidates
    end
    return vim.tbl_filter(function(s)
      return s:sub(1, #arg) == arg
    end, candidates)
  end

  -- Subcommand completion
  if #args <= 2 then
    return filter({ "send", "repeat", "env", "history", "cancel", "rails", "health" })
  end

  -- Sub-subcommand completion (e.g., rails refresh, history clear)
  if args[2] == "rails" then
    return filter({ "refresh" })
  end
  if args[2] == "history" then
    return filter({ "clear" })
  end

  return {}
end

---Register default keymaps
---@param cfg RestmanConfig Configuration table
function M.register_keymaps(cfg)
  local km = cfg.keymaps
  local opts = { silent = true, noremap = true }

  -- Normal mode: use <cmd> for silent execution
  vim.keymap.set(
    "n",
    km.send,
    "<cmd>Restman send<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: send request" })
  )
  -- Visual mode: use : prefix to preserve visual range
  vim.keymap.set(
    "v",
    km.send,
    ":Restman send<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: send request" })
  )
  vim.keymap.set(
    "n",
    km.repeat_last,
    "<cmd>Restman repeat<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: repeat last" })
  )
  vim.keymap.set(
    "n",
    km.env,
    "<cmd>Restman env<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: select env" })
  )
  vim.keymap.set(
    "n",
    km.history,
    "<cmd>Restman history<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: history" })
  )
  vim.keymap.set(
    "n",
    km.cancel,
    "<cmd>Restman cancel<CR>",
    vim.tbl_extend("force", opts, { desc = "Restman: cancel" })
  )
end

-- Expose dispatcher for command registration
M._dispatch = _dispatch

return M
