local M = {}

local window = require 'simple_rest.window'
local notifier = require 'simple_rest.notifier'
local core = require 'simple_rest.core'
local parser = require 'simple_rest.parser'
local client = require 'simple_rest.client'

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

  local bufnr = vim.api.nvim_get_current_buf()
  local start_row, start_col, end_row, end_col = req:range()

  core.flash_request(bufnr, start_row, start_col, end_row, end_col)

  local parsed = parser.parse_request(req, bufnr)
  if not parsed then
    vim.notify('Failed to parse request', vim.log.levels.ERROR)
    return
  end

  window.open()
  window.clear()

  -- Show request summary
  local lines = {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
  }

  if parsed.body then
    table.insert(lines, 'Body:')
    for body_line in (parsed.body .. '\n'):gmatch '([^\n]*)\n' do
      table.insert(lines, body_line)
    end
    table.insert(lines, '')
  end

  table.insert(lines, '---')
  table.insert(lines, '')
  table.insert(lines, '# Verbose Output')
  table.insert(lines, '---')
  table.insert(lines, '')

  window.set_lines(lines)

  notifier.start('Running ' .. parsed.method .. ' ' .. parsed.url)

  client.send(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    nil, -- on_stdout_chunk (we collect body at the end)
    function(line)
      -- on_stderr_chunk - stream verbose output live
      vim.schedule(function()
        window.append_lines { line }
      end)
    end,
    function(result)
      vim.schedule(function()
        notifier.stop('Done! Status: ' .. result.status)

        local result_lines = {
          '',
          '---',
          '',
          '# Response',
          'Status: ' .. result.status,
          '',
          '## Response Headers',
        }

        for name, value in pairs(result.response_headers) do
          table.insert(result_lines, name .. ': ' .. value)
        end

        table.insert(result_lines, '')
        table.insert(result_lines, '## Body')
        table.insert(result_lines, '')

        -- Add body lines
        for body_line in (result.body .. '\n'):gmatch '([^\n]*)\n' do
          table.insert(result_lines, body_line)
        end

        window.append_lines(result_lines)
      end)
    end
  )
end

return M
