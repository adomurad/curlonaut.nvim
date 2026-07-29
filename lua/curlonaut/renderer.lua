local M = {}

local formatter = require 'curlonaut.formatter'

---@param headers table<string, string>
---@return string[]
local function header_lines(headers)
  local lines = {}
  for name, value in pairs(headers) do
    table.insert(lines, name .. ': ' .. value)
  end
  return lines
end

---@param body string
---@return string[]
local function body_lines(body)
  local lines = {}
  for line in (body .. '\n'):gmatch '([^\n]*)\n' do
    table.insert(lines, line)
  end
  return lines
end

---@param parsed SimpleRestParsedRequest
---@param result SimpleRestResponse
---@param config table
---@return string[] lines
---@return string|nil content_type
function M.render_full(parsed, result, config)
  local content_type = result.response_headers['Content-Type']
    or result.response_headers['content-type']

  local formatted_body = formatter.format_body(content_type, result.body, config)
  local body_to_show = formatted_body or result.body

  local lines = {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
  }

  if next(result.request_headers) then
    table.insert(lines, '## Headers')
    for _, line in ipairs(header_lines(result.request_headers)) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
  end

  table.insert(lines, '')
  table.insert(lines, '# Response')
  table.insert(lines, 'Status: ' .. result.status)
  table.insert(lines, 'Time: ' .. result.time_ms .. 'ms')
  table.insert(lines, '')

  table.insert(lines, '## Headers')
  for _, line in ipairs(header_lines(result.response_headers)) do
    table.insert(lines, line)
  end

  table.insert(lines, '')
  table.insert(lines, '## Body')
  table.insert(lines, '')

  for _, line in ipairs(body_lines(body_to_show)) do
    table.insert(lines, line)
  end

  return lines, content_type
end

---@param parsed SimpleRestParsedRequest
---@param result SimpleRestResponse
---@param config table
---@return string[] lines
---@return string|nil content_type
function M.render_simple(parsed, result, config)
  local content_type = result.response_headers['Content-Type']
    or result.response_headers['content-type']

  local formatted_body = formatter.format_body(content_type, result.body, config)
  local body_to_show = formatted_body or result.body

  local lines = {
    '# Request',
    parsed.method .. ' ' .. parsed.url,
    '',
    '# Response',
    'Status: ' .. result.status,
    'Time: ' .. result.time_ms .. 'ms',
    '',
  }

  table.insert(lines, '## Headers')
  for _, line in ipairs(header_lines(result.response_headers)) do
    table.insert(lines, line)
  end

  table.insert(lines, '')
  table.insert(lines, '## Body')
  table.insert(lines, '')

  for _, line in ipairs(body_lines(body_to_show)) do
    table.insert(lines, line)
  end

  return lines, content_type
end

return M
