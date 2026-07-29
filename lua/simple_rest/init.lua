local M = {}

local window = require 'simple_rest.window'
local notifier = require 'simple_rest.notifier'
local core = require 'simple_rest.core'

local valid_args = { 'Open', 'Close', 'Toggle', 'RunRequestUnderCursor' }

---@param arg_lead string
---@param cmd_line string
---@param cursor_pos integer
---@return string[]
local function complete_my_cmd(arg_lead, cmd_line, cursor_pos)
  local matches = {}
  for _, arg in ipairs(valid_args) do
    if arg:find('^' .. arg_lead) then
      table.insert(matches, arg)
    end
  end
  return matches
end

local function create_user_commands()
  vim.api.nvim_create_user_command('SimpleRest', function(args)
    if args.args == '' then
      print 'Error: SimpleRest requires an argument (Open, Close, Toggle, RunRequestUnderCursor)'
      return
    end

    if args.args == 'Open' then
      M.open_results()
    elseif args.args == 'Close' then
      M.close_results()
    elseif args.args == 'Toggle' then
      M.toggle_results()
    elseif args.args == 'RunRequestUnderCursor' then
      M.run_request_under_cursor()
    else
      print 'Error: wrong arg!'
    end
  end, {
    desc = 'Simple Rest',
    nargs = 1,
    complete = complete_my_cmd,
  })
end

function M.setup()
  create_user_commands()
end

function M.open_results()
  window.open()
end

function M.close_results()
  window.close()
end

function M.toggle_results()
  window.toggle()
end

function M.run_request_under_cursor()
  local req = core.get_request_at_cursor()
  if not req then
    vim.notify('No request found under cursor', vim.log.levels.WARN)
    return
  end

  local text = vim.treesitter.get_node_text(req, 0)
  local bufnr = vim.api.nvim_get_current_buf()
  local start_row, start_col, end_row, end_col = req:range()

  core.flash_request(bufnr, start_row, start_col, end_row, end_col)

  window.open()
  window.clear()
  window.set_lines {
    '# Parsed Request',
    '---',
    '',
    text,
    '',
    '---',
    'HTTP execution not yet implemented.',
  }

  -- TODO: next step - parse the request and execute with client.lua
end

return M
