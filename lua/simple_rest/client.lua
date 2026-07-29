local M = {}

local Job = require 'plenary.job'

---@class SimpleRestResponse
---@field status integer
---@field body string
---@field stderr string

---Send an HTTP request using curl.
---@param url string
---@param method? string defaults to "GET"
---@param headers? table<string, string>
---@param body? string
---@param on_chunk? fun(line: string)
---@param on_done? fun(result: SimpleRestResponse)
M.send = function(url, method, headers, body, on_chunk, on_done)
  method = method or 'GET'

  local args = {
    '-s', -- silent
    '-X', method,
    url,
    '-w', '\n%{http_code}', -- write HTTP code at the end
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
        on_done({
          status = tonumber(http_code) or 0,
          body = table.concat(stdout_lines, '\n'),
          stderr = table.concat(stderr_lines, '\n'),
        })
      end
    end,
  }):start()
end

return M
