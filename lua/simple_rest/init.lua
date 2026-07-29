local M = {}

local window = require 'simple_rest.window'
local notifier = require 'simple_rest.notifier'
local core = require 'simple_rest.core'
local parser = require 'simple_rest.parser'
local client = require 'simple_rest.client'
local formatter = require 'simple_rest.formatter'

--[[
  Config example:
    require('simple_rest').setup({
      formatters = {
        json = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/simple_rest_response.json' } },
        html = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/simple_rest_response.html' } },
        xml  = { command = 'xmllint',   args = { '--format', '-' } },
      },
    })

  Or shorthand (no extra args):
    json = 'prettierd'
--]]
M.config = {
  formatters = {},
}

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

---@param opts? table
function M.setup(opts)
  opts = opts or {}
  if opts.formatters then
    M.config.formatters = vim.tbl_extend('force', M.config.formatters, opts.formatters)
  end
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

  -- Open results window if closed; if already open, stay on current tab
  if not window.is_open() then
    window.open 'simple'
  end
  window.clear_tab 'simple'
  window.clear_tab 'full'
  window.clear_tab 'verbose'

  -- Simple tab: placeholder until request completes
  window.set_tab_lines('simple', {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
    '...',
  })

  -- Verbose tab: header only (content streams in live)
  window.set_tab_lines('verbose', { '# Verbose Output', '' })

  notifier.start('Running ' .. parsed.method .. ' ' .. parsed.url)

  client.send(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    nil, -- on_stdout_chunk (we collect body at the end)
    function(line)
      -- on_stderr_chunk - stream verbose output live to Verbose tab
      vim.schedule(function()
        window.append_tab_lines('verbose', { line })
      end)
    end,
    function(result)
      vim.schedule(function()
        notifier.stop('Done! Status: ' .. result.status)

        -- Determine content-type for formatting and highlighting
        local content_type = result.response_headers['Content-Type']
          or result.response_headers['content-type']

        -- Try to format body
        local formatted_body = formatter.format_body(content_type, result.body, M.config)
        local body_to_show = formatted_body or result.body

        -- Build Full tab entirely from parsed verbose data
        local full_lines = {
          '# Request',
          parsed.method .. ' ' .. parsed.url,
          '',
        }

        if next(result.request_headers) then
          table.insert(full_lines, '## Headers')
          for name, value in pairs(result.request_headers) do
            table.insert(full_lines, name .. ': ' .. value)
          end
          table.insert(full_lines, '')
        end

        table.insert(full_lines, '')
        table.insert(full_lines, '# Response')
        table.insert(full_lines, 'Status: ' .. result.status)
        table.insert(full_lines, '')

        table.insert(full_lines, '## Headers')
        for name, value in pairs(result.response_headers) do
          table.insert(full_lines, name .. ': ' .. value)
        end

        table.insert(full_lines, '')
        table.insert(full_lines, '## Body')
        table.insert(full_lines, '')

        -- Add body lines
        for body_line in (body_to_show .. '\n'):gmatch '([^\n]*)\n' do
          table.insert(full_lines, body_line)
        end

        window.set_tab_lines('full', full_lines)
        window.highlight_tab('full', content_type)

        -- Build Simple tab: request + response (no request headers)
        local simple_lines = {
          '# Request',
          parsed.method .. ' ' .. parsed.url,
          '',
          '# Response',
          'Status: ' .. result.status,
          '',
        }

        table.insert(simple_lines, '## Headers')
        for name, value in pairs(result.response_headers) do
          table.insert(simple_lines, name .. ': ' .. value)
        end

        table.insert(simple_lines, '')
        table.insert(simple_lines, '## Body')
        table.insert(simple_lines, '')

        for body_line in (body_to_show .. '\n'):gmatch '([^\n]*)\n' do
          table.insert(simple_lines, body_line)
        end

        window.set_tab_lines('simple', simple_lines)
        window.highlight_tab('simple', content_type)

        -- Highlight the verbose buffer once the stream is complete
        window.highlight_tab 'verbose'
      end)
    end
  )
end

return M
