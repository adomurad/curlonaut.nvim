local M = {}

local Job = require 'plenary.job'

---@class SimpleRestResponse
---@field status integer
---@field body string
---@field request_headers table<string, string>
---@field response_headers table<string, string>
---@field stderr string
---@field time_ms integer

local active_job = nil
local is_cancelled = false

---@class SimpleRestFormField
---@field name string
---@field value string|nil
---@field file string|nil
---@field type string|nil

---Escape a string for safe use in a POSIX shell command.
---Wraps the string in single quotes and escapes embedded single quotes.
---@param s string
---@return string
local function shell_escape(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

---Build the curl argument list for a request.
---Returns a shallow copy of headers so the original table is never mutated.
---@param url string
---@param method? string defaults to "GET"
---@param headers? table<string, string>
---@param body? string
---@param form_fields? SimpleRestFormField[]
---@param include_status_writer? boolean defaults to true; set to false for display/copy
---@param curl_flags? string[] extra curl flags (e.g. --insecure)
---@return string[]
function M.build_args(url, method, headers, body, form_fields, include_status_writer, curl_flags)
  method = method or 'GET'
  include_status_writer = include_status_writer ~= false

  local args = {
    '-v', -- verbose
    '-s', -- silent (suppress progress meter, but -v still works)
    '-X',
    method,
    url,
  }

  if include_status_writer then
    table.insert(args, '-w')
    table.insert(args, '\n__CURLONAUT_STATUS__:%{http_code}\n__CURLONAUT_TIME__:%{time_total}')
  end

  if curl_flags and #curl_flags > 0 then
    for _, flag in ipairs(curl_flags) do
      table.insert(args, flag)
    end
  end

  -- Work on a shallow copy so we don't mutate the caller's headers table.
  local headers_copy = {}
  if headers then
    for k, v in pairs(headers) do
      headers_copy[k] = v
    end
  end

  -- When using -F, curl auto-generates Content-Type with the proper boundary.
  -- Passing a manual multipart/form-data header without a boundary breaks parsing.
  if form_fields and #form_fields > 0 then
    for key, _ in pairs(headers_copy) do
      if key:lower() == 'content-type' then
        headers_copy[key] = nil
        break
      end
    end
  end

  for key, value in pairs(headers_copy) do
    table.insert(args, '-H')
    table.insert(args, key .. ': ' .. value)
  end

  if form_fields and #form_fields > 0 then
    for _, field in ipairs(form_fields) do
      if field.file then
        local form_arg = field.name .. '=@' .. field.file
        if field.type then
          form_arg = form_arg .. ';type=' .. field.type
        end
        table.insert(args, '-F')
        table.insert(args, form_arg)
      else
        table.insert(args, '-F')
        table.insert(args, field.name .. '=' .. field.value)
      end
    end
  elseif body and body ~= '' then
    table.insert(args, '-d')
    table.insert(args, body)
  end

  return args
end

---Return true if the argument needs single-quoting for POSIX shell.
---Safe unquoted characters: alphanumerics, dot, underscore, hyphen, slash,
---colon, percent, equals, at, plus, and comma.
---@param s string
---@return boolean
local function needs_quoting(s)
  return s:find('[^%w._%%=,:@+/-]') ~= nil
end

---Build a shell-safe curl command as a list of lines formatted for copy-paste
---into bash. Each argument is placed on its own line with a trailing backslash
---so the command can be pasted directly into a terminal.
---@param url string
---@param method? string
---@param headers? table<string, string>
---@param body? string
---@param form_fields? SimpleRestFormField[]
---@param curl_flags? string[]
---@return string[]
function M.build_command_lines(url, method, headers, body, form_fields, curl_flags)
  local args = M.build_args(url, method, headers, body, form_fields, false, curl_flags)
  local lines = { 'curl \\' }
  for i, arg in ipairs(args) do
    local formatted = needs_quoting(arg) and shell_escape(arg) or arg
    if i < #args then
      formatted = formatted .. ' \\'
    end
    table.insert(lines, '  ' .. formatted)
  end
  return lines
end

---Send an HTTP request using curl.
---@param url string
---@param method? string defaults to "GET"
---@param headers? table<string, string>
---@param body? string
---@param form_fields? SimpleRestFormField[]
---@param curl_flags? string[]
---@param on_chunk? fun(line: string)
---@param on_stderr_chunk? fun(line: string)
---@param on_done? fun(result: SimpleRestResponse)
M.send = function(url, method, headers, body, form_fields, curl_flags, on_chunk, on_stderr_chunk, on_done)
  local args = M.build_args(url, method, headers, body, form_fields, true, curl_flags)

  is_cancelled = false
  local stdout_lines = {}
  local stderr_lines = {}
  local request_headers = {}
  local response_headers = {}

  active_job = Job:new({
    command = 'curl',
    args = args,
    on_stdout = function(_, line)
      table.insert(stdout_lines, line)
      if on_chunk then
        on_chunk(line)
      end
    end,
    on_stderr = function(_, line)
      table.insert(stderr_lines, line)
      if on_stderr_chunk then
        on_stderr_chunk(line)
      end

      -- Parse request headers from stderr: lines starting with "> " but not request line like "> GET / HTTP/1.1"
      if line:match '^> ' and not line:match '^> %u+ ' then
        local header = line:sub(3)
        if header ~= '' then
          local colon_pos = header:find ':'
          if colon_pos then
            local name = vim.trim(header:sub(1, colon_pos - 1))
            local value = vim.trim(header:sub(colon_pos + 1))
            request_headers[name] = value
          end
        end
      end

      -- Parse response headers from stderr: lines starting with "< " but not status line like "< HTTP/1.1 200"
      if line:match '^< ' and not line:match '^< HTTP/%d' then
        local header = line:sub(3)
        if header ~= '' then
          local colon_pos = header:find ':'
          if colon_pos then
            local name = vim.trim(header:sub(1, colon_pos - 1))
            local value = vim.trim(header:sub(colon_pos + 1))
            response_headers[name] = value
          end
        end
      end
    end,
    on_exit = function(_, code)
      active_job = nil

      if is_cancelled then
        if on_done then
          on_done(nil)
        end
        return
      end

      local http_code = ''
      local time_ms = 0
      local clean_stdout = {}

      for _, line in ipairs(stdout_lines) do
        local status_match = line:match('^__CURLONAUT_STATUS__:(%d+)$')
        local time_match = line:match('^__CURLONAUT_TIME__:([%d%.]+)$')
        if status_match then
          http_code = status_match
        elseif time_match then
          time_ms = math.floor(tonumber(time_match) * 1000 + 0.5)
        else
          table.insert(clean_stdout, line)
        end
      end

      if code ~= 0 then
        vim.schedule(function()
          vim.notify('Request failed with code ' .. code, vim.log.levels.ERROR)
        end)
      end

      if on_done then
        on_done {
          status = tonumber(http_code) or 0,
          body = table.concat(clean_stdout, '\n'),
          request_headers = request_headers,
          response_headers = response_headers,
          stderr = table.concat(stderr_lines, '\n'),
          time_ms = time_ms,
        }
      end
    end,
  })
  active_job:start()
end

---Cancel the currently running curl request, if any.
---@return boolean cancelled true if a request was active and killed.
function M.cancel()
  if active_job then
    is_cancelled = true
    -- Send SIGKILL via libuv process handle
    local uv = vim.uv or vim.loop
    if active_job.handle then
      pcall(function()
        uv.process_kill(active_job.handle, 9)
      end)
    end
    active_job = nil
    return true
  end
  return false
end

return M
