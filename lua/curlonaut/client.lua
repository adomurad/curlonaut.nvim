local M = {}

local Job = require 'plenary.job'

---@class SimpleRestResponse
---@field status integer
---@field body string
---@field request_headers table<string, string>
---@field response_headers table<string, string>
---@field stderr string

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
---@return string[]
function M.build_args(url, method, headers, body, form_fields, include_status_writer)
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
    table.insert(args, '\n%{http_code}') -- write HTTP code at the end
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
---@return string[]
function M.build_command_lines(url, method, headers, body, form_fields)
  local args = M.build_args(url, method, headers, body, form_fields, false)
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
---@param on_chunk? fun(line: string)
---@param on_stderr_chunk? fun(line: string)
---@param on_done? fun(result: SimpleRestResponse)
M.send = function(url, method, headers, body, form_fields, on_chunk, on_stderr_chunk, on_done)
  local args = M.build_args(url, method, headers, body, form_fields)

  local stdout_lines = {}
  local stderr_lines = {}
  local request_headers = {}
  local response_headers = {}

  Job:new({
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
      local http_code = stdout_lines[#stdout_lines] or ''
      stdout_lines[#stdout_lines] = nil

      if code ~= 0 then
        vim.schedule(function()
          vim.notify('Request failed with code ' .. code, vim.log.levels.ERROR)
        end)
      end

      if on_done then
        on_done {
          status = tonumber(http_code) or 0,
          body = table.concat(stdout_lines, '\n'),
          request_headers = request_headers,
          response_headers = response_headers,
          stderr = table.concat(stderr_lines, '\n'),
        }
      end
    end,
  }):start()
end

return M
