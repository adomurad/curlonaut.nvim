local M = {}

local window = require 'curlonaut.window'
local notifier = require 'curlonaut.notifier'
local core = require 'curlonaut.core'
local parser = require 'curlonaut.parser'
local client = require 'curlonaut.client'
local env = require 'curlonaut.env'
local extractors = require 'curlonaut.extractors'
local renderer = require 'curlonaut.renderer'

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

local valid_args = { 'Open', 'Close', 'Toggle', 'RunRequest', 'CopyCurl', 'CancelRequest' }

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
    elseif args.args == 'CancelRequest' then
      M.cancel_request()
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

function M.cancel_request()
  if client.cancel() then
    notifier.stop('Request cancelled')
    window.set_tab_lines('simple', { '# Request cancelled', '' })
    window.set_tab_lines('full', { '# Request cancelled', '' })
    vim.notify('[curlonaut] Request cancelled', vim.log.levels.INFO)
  else
    vim.notify('[curlonaut] No active request to cancel', vim.log.levels.WARN)
  end
end

function M.goto_next_request()
  core.goto_request(0, 'next', vim.v.count1)
end

function M.goto_prev_request()
  core.goto_request(0, 'prev', vim.v.count1)
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

  -- Merge file-level and per-request curl flags (per-request wins on conflicts)
  local file_flags = parser.get_file_curl_flags(bufnr)
  local req_flags = parsed.curl_flags or {}
  parsed.curl_flags = vim.list_extend(vim.deepcopy(file_flags), req_flags)
  for i, flag in ipairs(parsed.curl_flags) do
    parsed.curl_flags[i] = env.substitute(flag, env_table)
  end

  return parsed
end

---Resolve multipart file paths and validate they exist.
---@param parsed SimpleRestParsedRequest
---@param bufnr integer
---@return boolean ok
local function validate_multipart_files(parsed, bufnr)
  if not parsed.form_fields or #parsed.form_fields == 0 then
    return true
  end

  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  local http_dir = bufpath ~= '' and vim.fn.fnamemodify(bufpath, ':h') or vim.fn.getcwd()

  for _, field in ipairs(parsed.form_fields) do
    if field.file then
      local filepath = field.file
      -- Resolve relative paths against the .http file's directory
      if not filepath:match('^/') and not filepath:match('^~') then
        filepath = vim.fn.fnamemodify(http_dir .. '/' .. filepath, ':p')
      end

      if vim.fn.filereadable(filepath) ~= 1 then
        vim.notify(
          '[curlonaut] Multipart file not found: ' .. field.file .. ' (resolved to: ' .. filepath .. ')',
          vim.log.levels.ERROR
        )
        return false
      end

      field.file = filepath
    end
  end

  return true
end

function M.run_request()
  local parsed = prepare_request()
  if not parsed then
    return
  end

  -- Cancel any previous request before starting a new one
  if client.cancel() then
    notifier.stop('Previous request cancelled')
  end

  local bufnr = vim.api.nvim_get_current_buf()

  if not validate_multipart_files(parsed, bufnr) then
    return
  end

  local req = core.get_request_at_cursor()
  local start_row, start_col, end_row, end_col = req:range()
  core.flash_request(bufnr, start_row, start_col, end_row, end_col)

  -- Build curl command lines for the Curl tab
  local curl_lines = client.build_command_lines(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields,
    parsed.curl_flags
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
    parsed.curl_flags,
    nil, -- on_stdout_chunk (we collect body at the end)
    function(line)
      -- on_stderr_chunk - stream verbose output live to Verbose tab
      vim.schedule(function()
        window.append_tab_lines('verbose', { line })
      end)
    end,
    function(result)
      vim.schedule(function()
        if not result then
          -- Cancelled — UI already updated by cancel_request(), just stop highlighting
          window.highlight_tab 'verbose'
          return
        end

        notifier.stop('Done! Status: ' .. result.status .. ' | ' .. result.time_ms .. 'ms')

        extractors.evaluate(parsed, result, env.session_vars)

        local full_lines, full_ct = renderer.render_full(parsed, result, M.config)
        window.set_tab_lines('full', full_lines)
        window.highlight_tab('full', full_ct)

        local simple_lines, simple_ct = renderer.render_simple(parsed, result, M.config)
        window.set_tab_lines('simple', simple_lines)
        window.highlight_tab('simple', simple_ct)

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

  local bufnr = vim.api.nvim_get_current_buf()
  if not validate_multipart_files(parsed, bufnr) then
    return
  end

  local curl_lines = client.build_command_lines(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields,
    parsed.curl_flags
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
