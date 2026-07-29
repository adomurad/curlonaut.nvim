local M = {}

local Job = require 'plenary.job'

---@class SimpleRestResponse
---@field status integer
---@field body string
---@field request_headers table<string, string>
---@field response_headers table<string, string>
---@field stderr string

---Send an HTTP request using curl.
---@param url string
---@param method? string defaults to "GET"
---@param headers? table<string, string>
---@param body? string
---@param on_chunk? fun(line: string)
---@param on_stderr_chunk? fun(line: string)
---@param on_done? fun(result: SimpleRestResponse)
M.send = function(url, method, headers, body, on_chunk, on_stderr_chunk, on_done)
  method = method or 'GET'

  local args = {
    '-v', -- verbose
    '-s', -- silent (suppress progress meter, but -v still works)
    '-X',
    method,
    url,
    '-w',
    '\n%{http_code}', -- write HTTP code at the end
  }

  if headers then
    for key, value in pairs(headers) do
      table.insert(args, '-H')
      table.insert(args, key .. ': ' .. value)
    end
  end

  if body and body ~= '' then
    table.insert(args, '-d')
    table.insert(args, body)
  end

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
