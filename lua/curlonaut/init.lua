local M = {}

local window = require 'curlonaut.window'
local notifier = require 'curlonaut.notifier'
local core = require 'curlonaut.core'
local parser = require 'curlonaut.parser'
local client = require 'curlonaut.client'
local env = require 'curlonaut.env'
local extractors = require 'curlonaut.extractors'
local renderer = require 'curlonaut.renderer'
local cookies = require 'curlonaut.cookies'

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

local valid_args = { 'Open', 'Close', 'Toggle', 'RunRequest', 'CopyCurl', 'CancelRequest', 'ClearCookies', 'EditCookies' }

-- Live progress state
local spinner_chars = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local progress_timer = nil
local progress_spinner_lines = {}
local request_generation = 0

local function stop_progress_timer(gen)
  if gen ~= request_generation then
    return
  end
  if progress_timer and progress_timer:is_active() then
    progress_timer:stop()
  end
  progress_timer = nil
  progress_spinner_lines = {}
  window.clear_winbar_extra()
end

local function start_progress_timer(gen)
  if gen ~= request_generation then
    return
  end
  local spinner_idx = 1
  local start_ms = vim.loop.now()
  progress_timer = vim.loop.new_timer()
  progress_timer:start(
    100,
    100,
    vim.schedule_wrap(function()
      if gen ~= request_generation then
        return
      end
      spinner_idx = (spinner_idx % #spinner_chars) + 1
      local elapsed = (vim.loop.now() - start_ms) / 1000
      local text = string.format('%s %.2fs', spinner_chars[spinner_idx], elapsed)
      if progress_spinner_lines.simple then
        window.update_tab_line('simple', progress_spinner_lines.simple, text)
      end
      if progress_spinner_lines.full then
        window.update_tab_line('full', progress_spinner_lines.full, text)
      end
      window.set_winbar_extra(text)
    end)
  )
end

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
    elseif args.args == 'ClearCookies' then
      M.clear_cookies()
    elseif args.args == 'EditCookies' then
      M.edit_cookies()
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

  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = vim.api.nvim_create_augroup('CurlonautCleanup', { clear = true }),
    callback = function()
      cookies.cleanup_all()
    end,
  })
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

function M.clear_cookies()
  local bufnr = vim.api.nvim_get_current_buf()
  -- If called from the cookies results tab, look up the source .http buffer.
  local source_buf = vim.b[bufnr].curlonaut_source_bufnr
  if source_buf then
    bufnr = source_buf
  end

  if cookies.clear_jar(bufnr) then
    vim.notify('[curlonaut] Cookie jar cleared', vim.log.levels.INFO)
    window.clear_tab 'cookies'
    window.set_tab_lines('cookies', { '# Cookie Jar', '', '(D = clear, e = edit)', '', '(cleared)' })
  else
    vim.notify('[curlonaut] No cookie jar for this buffer', vim.log.levels.WARN)
  end
end

function M.edit_cookies()
  local bufnr = vim.api.nvim_get_current_buf()
  -- If called from the cookies results tab, look up the source .http buffer.
  local source_buf = vim.b[bufnr].curlonaut_source_bufnr
  if source_buf then
    bufnr = source_buf
  end

  local path = cookies.get_edit_path(bufnr)
  if not path then
    vim.notify('[curlonaut] No cookie jar for this buffer', vim.log.levels.WARN)
    return
  end
  if vim.fn.filereadable(path) ~= 1 then
    vim.notify('[curlonaut] Cookie jar file does not exist yet', vim.log.levels.WARN)
    return
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

function M.goto_next_request()
  core.goto_request(0, 'next', vim.v.count1)
end

function M.goto_prev_request()
  core.goto_request(0, 'prev', vim.v.count1)
end

local dynamic_vars = require 'curlonaut.dynamic_vars'

---Strip query parameters whose value equals the OMIT_SENTINEL.
---@param url string
---@param sentinel string
---@return string
local function filter_query_string_omit(url, sentinel)
  local q_pos = url:find('?')
  if not q_pos then
    return url
  end
  local base = url:sub(1, q_pos)
  local query = url:sub(q_pos + 1)
  local kept = {}
  for part in query:gmatch('[^&]+') do
    local eq_pos = part:find('=')
    if eq_pos then
      local value = part:sub(eq_pos + 1)
      if value ~= sentinel then
        table.insert(kept, part)
      end
    else
      table.insert(kept, part)
    end
  end
  local result = table.concat(kept, '&')
  if result == '' then
    return url:sub(1, q_pos - 1)
  end
  return base .. result
end

---Strip key=value pairs whose value equals the OMIT_SENTINEL from a urlencoded body.
---@param body string|nil
---@param sentinel string
---@return string|nil
local function filter_urlencoded_body_omit(body, sentinel)
  if not body then
    return nil
  end
  local kept = {}
  for part in body:gmatch('[^&]+') do
    local eq_pos = part:find('=')
    if eq_pos then
      local value = part:sub(eq_pos + 1)
      if value ~= sentinel then
        table.insert(kept, part)
      end
    else
      table.insert(kept, part)
    end
  end
  local result = table.concat(kept, '&')
  if result == '' then
    return nil
  end
  return result
end

---Remove multipart form fields whose value equals the OMIT_SENTINEL.
---@param fields table[]|nil
---@param sentinel string
---@return table[]|nil
local function filter_form_fields_omit(fields, sentinel)
  if not fields then
    return nil
  end
  local kept = {}
  for _, field in ipairs(fields) do
    if field.value ~= sentinel then
      table.insert(kept, field)
    end
  end
  if #kept == 0 then
    return nil
  end
  return kept
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

  -- Apply {{$omit}} filtering after all variable substitution is done.
  local sentinel = dynamic_vars.OMIT_SENTINEL
  parsed.url = filter_query_string_omit(parsed.url, sentinel)
  if parsed.body then
    parsed.body = filter_urlencoded_body_omit(parsed.body, sentinel)
  end
  if parsed.form_fields then
    parsed.form_fields = filter_form_fields_omit(parsed.form_fields, sentinel)
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

  -- Stop any existing progress timer before starting a new one
  if progress_timer and progress_timer:is_active() then
    progress_timer:stop()
  end
  progress_timer = nil

  request_generation = request_generation + 1
  local current_gen = request_generation

  local bufnr = vim.api.nvim_get_current_buf()

  if not validate_multipart_files(parsed, bufnr) then
    return
  end

  local req = core.get_request_at_cursor()
  local start_row, start_col, end_row, end_col = req:range()
  core.flash_request(bufnr, start_row, start_col, end_row, end_col)

  -- Cookie jar (per-file, opt-in via # @cookie-jar directive)
  local cookie_jar_path = cookies.get_jar_path(bufnr)

  -- Build curl command lines for the Curl tab
  local curl_lines = client.build_command_lines(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields,
    parsed.curl_flags,
    cookie_jar_path
  )

  -- Open results window if closed; if already open, stay on current tab
  if not window.is_open() then
    window.open 'simple'
  else
    -- Ensure winbar is up-to-date (tab list may have changed after update)
    window.refresh_winbar()
  end
  window.clear_tab 'simple'
  window.clear_tab 'full'
  window.clear_tab 'verbose'
  window.clear_tab 'curl'
  window.clear_tab 'cookies'

  -- Simple tab: placeholder with live progress line
  local simple_lines = {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
    '# Response',
    '',
  }
  progress_spinner_lines.simple = #simple_lines -- 0-based index of the line we are about to insert
  table.insert(simple_lines, '⠋ In progress... 0.00s')
  window.set_tab_lines('simple', simple_lines)

  -- Full tab: placeholder with request info upfront
  local full_lines = {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
  }
  if next(parsed.headers) then
    table.insert(full_lines, '## Headers')
    for name, value in pairs(parsed.headers) do
      table.insert(full_lines, name .. ': ' .. value)
    end
    table.insert(full_lines, '')
  end
  table.insert(full_lines, '# Response')
  table.insert(full_lines, '')
  progress_spinner_lines.full = #full_lines
  table.insert(full_lines, '⠋ In progress... 0.00s')
  window.set_tab_lines('full', full_lines)

  -- Verbose tab: header only (content streams in live)
  window.set_tab_lines('verbose', { '# Verbose Output', '' })

  -- Curl tab: ready-to-copy command
  window.set_tab_lines('curl', curl_lines)

  start_progress_timer(current_gen)

  client.send(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields,
    parsed.curl_flags,
    cookie_jar_path,
    nil, -- on_stdout_chunk (we collect body at the end)
    function(line)
      -- on_stderr_chunk - stream verbose output live to Verbose tab
      vim.schedule(function()
        window.append_tab_lines('verbose', { line })
      end)
    end,
    function(result)
      vim.schedule(function()
        stop_progress_timer(current_gen)

        if current_gen ~= request_generation then
          return
        end

        if not result then
          -- Cancelled — UI already updated by cancel_request()
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

        -- Populate cookies tab if a jar is active for this buffer
        if cookie_jar_path then
          local jar_content = cookies.read_jar(bufnr)
          local cookie_lines
          if jar_content then
            local parsed_cookies = cookies.parse_cookies(jar_content)
            cookie_lines = cookies.format_cookies(parsed_cookies)
          else
            cookie_lines = { '# Cookie Jar', '', '(empty)' }
          end
          window.set_tab_lines('cookies', cookie_lines)
          window.highlight_tab 'cookies'

          -- Remember which .http buffer this jar belongs to so clear/edit
          -- work when invoked from the cookies results tab.
          local cookies_buf = vim.fn.bufnr('curlonaut://cookies')
          if cookies_buf ~= -1 then
            vim.b[cookies_buf].curlonaut_source_bufnr = bufnr
          end
        end
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

  local cookie_jar_path = cookies.get_jar_path(bufnr)

  local curl_lines = client.build_command_lines(
    parsed.url,
    parsed.method,
    parsed.headers,
    parsed.body,
    parsed.form_fields,
    parsed.curl_flags,
    cookie_jar_path
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
