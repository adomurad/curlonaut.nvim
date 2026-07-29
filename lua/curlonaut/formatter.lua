local M = {}

local Job = require 'plenary.job'

local function content_type_to_lang(content_type)
  if not content_type then
    return nil
  end
  local ct = content_type:lower()
  if ct:find('application/json') or ct:find('text/json') then
    return 'json'
  elseif ct:find('text/html') or ct:find('application/xhtml') then
    return 'html'
  elseif ct:find('application/xml') or ct:find('text/xml') then
    return 'xml'
  end
  return nil
end

function M.format_body(content_type, body, config)
  local lang = content_type_to_lang(content_type)
  if not lang then
    return nil
  end

  local fmt = config.formatters and config.formatters[lang]
  if not fmt then
    return nil
  end

  local command, args
  if type(fmt) == 'string' then
    command = fmt
    args = {}
  elseif type(fmt) == 'table' and fmt.command then
    command = fmt.command
    args = fmt.args or {}
  else
    return nil
  end

  if vim.fn.executable(command) ~= 1 then
    return nil
  end

  local stdout_lines = {}

  local job = Job:new {
    command = command,
    args = args,
    writer = body,
    on_stdout = function(_, line)
      table.insert(stdout_lines, line)
    end,
  }

  local ok, result = pcall(function()
    return job:sync(5000)
  end)

  if not ok or not result or #stdout_lines == 0 then
    return nil
  end

  if stdout_lines[#stdout_lines] == '' then
    stdout_lines[#stdout_lines] = nil
  end

  return table.concat(stdout_lines, '\n')
end

return M
