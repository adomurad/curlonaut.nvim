local M = {}

local window = require 'curlonaut.window'
local notifier = require 'curlonaut.notifier'
local core = require 'curlonaut.core'
local parser = require 'curlonaut.parser'
local client = require 'curlonaut.client'
local formatter = require 'curlonaut.formatter'
local env = require 'curlonaut.env'

--[[
  Config example:
    require('curlonaut').setup({
      formatters = {
        json = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.json' } },
        html = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.html' } },
        xml  = { command = 'xmllint',   args = { '--format', '-' } },
      },
    })

  Or shorthand (no extra args):
    json = 'prettierd'
--]]
M.config = {
  formatters = {},
}

local valid_args = { 'Open', 'Close', 'Toggle', 'RunRequest', 'CopyCurl' }

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
  vim.api.nvim_create_user_command('Curlonaut', function(args)
    if args.args == '' then
      print 'Error: Curlonaut requires an argument (Open, Close, Toggle, RunRequest, CopyCurl)'
      return
    end

    if args.args == 'Open' then
      M.open_results()
    elseif args.args == 'Close' then
      M.close_results()
    elseif args.args == 'Toggle' then
      M.toggle_results()
    elseif args.args == 'RunRequest' then
      M.run_request()
    elseif args.args == 'CopyCurl' then
      M.copy_curl()
    else
      print 'Error: wrong arg!'
    end
  end, {
    desc = 'Curlonaut',
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

---Extract a value from a Lua table using a dot-path string.
---Supports array indices like `items[0]` (0-based, converted to 1-based for Lua).
---@param obj table
---@param path string
---@return any
local function extract_json_path(obj, path)
  local current = obj
  -- Match parts: either `key` or `key[index]`
  for part in path:gmatch('[^.]+') do
    local key, idx = part:match('^(.-)%[(%d+)%]$')
    if key then
      current = current[key]
      if type(current) ~= 'table' then
        return nil
      end
      current = current[tonumber(idx) + 1] -- 0-based to 1-based
    else
      current = current[part]
    end
    if current == nil then
      return nil
    end
  end
  return current
end

---Parse the request under the cursor and apply variable substitution.
---Returns the processed parsed request, or nil if parsing fails.
---@return SimpleRestParsedRequest|nil
local function prepare_request()
  local req = core.get_request_at_cursor()
  if not req then
    vim.notify('No request found under cursor', vim.log.levels.WARN)
    return nil
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local parsed = parser.parse_request(req, bufnr)
  if not parsed then
    vim.notify('Failed to parse request', vim.log.levels.ERROR)
    return nil
  end

  -- Load env and substitute variables in URL, headers, body, and form fields
  local env_table = env.build_env_table(bufnr)
  parsed.url = env.substitute(parsed.url, env_table)
  for key, value in pairs(parsed.headers) do
    parsed.headers[key] = env.substitute(value, env_table)
  end
  if parsed.body then
    parsed.body = env.substitute(parsed.body, env_table)
  end
  if parsed.form_fields then
    for _, field in ipairs(parsed.form_fields) do
      if field.value then
        field.value = env.substitute(field.value, env_table)
      end
      if field.file then
        field.file = env.substitute(field.file, env_table)
      end
    end
  end

  return parsed
end

function M.run_request()
  local parsed = prepare_request()
  if not parsed then
    return
  end

  local req = core.get_request_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local start_row, start_col, end_row, end_col = req:range()
  core.flash_request(bufnr, start_row, start_col, end_row, end_col)

  -- Build curl command lines for the Curl tab
  local curl_lines = client.build_command_lines(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields
  )

  -- Open results window if closed; if already open, stay on current tab
  if not window.is_open() then
    window.open 'simple'
  end
  window.clear_tab 'simple'
  window.clear_tab 'full'
  window.clear_tab 'verbose'
  window.clear_tab 'curl'

  -- Simple tab: placeholder until request completes
  window.set_tab_lines('simple', {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
    '...',
  })

  -- Full tab: placeholder with request info upfront
  local full_placeholder = {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
  }
  if next(parsed.headers) then
    table.insert(full_placeholder, '## Headers')
    for name, value in pairs(parsed.headers) do
      table.insert(full_placeholder, name .. ': ' .. value)
    end
    table.insert(full_placeholder, '')
  end
  table.insert(full_placeholder, '...')
  window.set_tab_lines('full', full_placeholder)

  -- Verbose tab: header only (content streams in live)
  window.set_tab_lines('verbose', { '# Verbose Output', '' })

  -- Curl tab: ready-to-copy command
  window.set_tab_lines('curl', curl_lines)

  notifier.start('Running ' .. parsed.method .. ' ' .. parsed.url)

  client.send(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields,
    nil, -- on_stdout_chunk (we collect body at the end)
    function(line)
      -- on_stderr_chunk - stream verbose output live to Verbose tab
      vim.schedule(function()
        window.append_tab_lines('verbose', { line })
      end)
    end,
    function(result)
      vim.schedule(function()
        notifier.stop('Done! Status: ' .. result.status .. ' | ' .. result.time_ms .. 'ms')

        -- Evaluate response extractors and store in session vars
        if parsed.response_extractors and #parsed.response_extractors > 0 then
          for _, extractor in ipairs(parsed.response_extractors) do
            local target = extractor.target -- e.g. "@response.body.token" or "@response.headers.x-request-id"
            local var_name = extractor.name
            local val = nil

            if target:match('^@response%.body%.') then
              local json_path = target:sub(16) -- remove "@response.body."
              local ok, body_table = pcall(vim.json.decode, result.body)
              if ok and body_table then
                val = extract_json_path(body_table, json_path)
              else
                vim.notify(
                  '[curlonaut] Extractor "' .. var_name .. '" failed: response is not valid JSON',
                  vim.log.levels.WARN
                )
              end
            elseif target:match('^@response%.headers%.') then
              local header_name = target:sub(19) -- remove "@response.headers."
              val = result.response_headers[header_name]
              if not val then
                -- case-insensitive fallback
                for k, v in pairs(result.response_headers) do
                  if k:lower() == header_name:lower() then
                    val = v
                    break
                  end
                end
              end
              if not val then
                vim.notify(
                  '[curlonaut] Extractor "' .. var_name .. '" failed: header "' .. header_name .. '" not found',
                  vim.log.levels.WARN
                )
              end
            else
              vim.notify(
                '[curlonaut] Unknown extractor target: ' .. target,
                vim.log.levels.WARN
              )
            end

            if val ~= nil then
              env.session_vars[var_name] = tostring(val)
              vim.notify(
                '[curlonaut] Set ' .. var_name .. ' = ' .. tostring(val),
                vim.log.levels.INFO
              )
            else
              env.session_vars[var_name] = ''
            end
          end
        end

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
        table.insert(full_lines, 'Time: ' .. result.time_ms .. 'ms')
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
          'Time: ' .. result.time_ms .. 'ms',
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

function M.copy_curl()
  local parsed = prepare_request()
  if not parsed then
    return
  end

  local curl_lines = client.build_command_lines(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields
  )
  local curl_cmd = table.concat(curl_lines, '\n')

  -- Try to copy to the system clipboard; fall back to primary, then unnamed.
  local copied = false
  for _, reg in ipairs { '+', '*', '"' } do
    local ok = pcall(vim.fn.setreg, reg, curl_cmd)
    if ok then
      copied = true
    end
  end

  if copied then
    vim.notify('[curlonaut] Copied curl command to clipboard', vim.log.levels.INFO)
  else
    vim.notify('[curlonaut] Failed to copy curl command', vim.log.levels.ERROR)
  end
end

return M
