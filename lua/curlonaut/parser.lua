local M = {}

---@class SimpleRestParsedRequest
---@field method string
---@field url string
---@field headers table<string, string>
---@field body string|nil
---@field form_fields table[]|nil
---@field response_extractors table[]|nil

---Extract the first child node of a given type.
---@param node TSNode
---@param type string
---@return TSNode|nil
local function get_child(node, type)
  for child, _ in node:iter_children() do
    if child:type() == type then
      return child
    end
  end
end

---Collect all child nodes of a given type.
---@param node TSNode
---@param type string
---@return TSNode[]
local function get_children(node, type)
  local result = {}
  for child, _ in node:iter_children() do
    if child:type() == type then
      table.insert(result, child)
    end
  end
  return result
end

---Get the text of a node from a buffer.
---@param node TSNode
---@param bufnr integer
---@return string
local function get_text(node, bufnr)
  return vim.treesitter.get_node_text(node, bufnr)
end

---Parse a treesitter `request` node into structured data.
---@param request_node TSNode
---@param bufnr? integer
---@return SimpleRestParsedRequest|nil
function M.parse_request(request_node, bufnr)
  bufnr = bufnr or 0
  local method_node = get_child(request_node, 'method')
  local url_node = get_child(request_node, 'target_url')

  if not method_node or not url_node then
    return nil
  end

  local method = get_text(method_node, bufnr):upper()
  local url = get_text(url_node, bufnr)

  local headers = {}
  local header_nodes = get_children(request_node, 'header')
  for _, header_node in ipairs(header_nodes) do
    local name_node = get_child(header_node, 'header_entity')
    local value_node = get_child(header_node, 'value')
    if name_node and value_node then
      local name = vim.trim(get_text(name_node, bufnr))
      local value = vim.trim(get_text(value_node, bufnr))
      headers[name] = value
    end
  end

  local body = nil
  for child, _ in request_node:iter_children() do
    local t = child:type()
    if t:match('_body$') then
      body = get_text(child, bufnr)
      break
    end
  end

  -- Normalize www-form-urlencoded bodies: strip newlines before '&' and all
  -- trailing newlines.
  if body then
    for key, value in pairs(headers) do
      if key:lower() == 'content-type'
        and value:lower():find('application/x-www-form-urlencoded', 1, true) then
        body = body:gsub('\r?\n&', '&')
        body = body:gsub('[\r\n]+$', '')
        break
      end
    end
  end

  -- Parse multipart/form-data body into structured form fields.
  local form_fields = nil
  if body then
    for key, value in pairs(headers) do
      if key:lower() == 'content-type'
        and value:lower():find('multipart/form-data', 1, true) then
        form_fields = {}
        for line in body:gmatch('[^\r\n]+') do
          local name, val = line:match('^([^=]+)=(.*)$')
          if name then
            name = vim.trim(name)
            val = vim.trim(val)
            if val:match('^<') then
              -- File upload: < ./path or < ./path;type=mime/type
              local file_path = val:sub(2):match('^%s*(.*)$')
              local mime_type
              local semi_pos = file_path:find(';')
              if semi_pos then
                local rest = file_path:sub(semi_pos + 1)
                mime_type = rest:match('^%s*type%s*=%s*(.+)$') or rest
                file_path = vim.trim(file_path:sub(1, semi_pos - 1))
              end
              table.insert(form_fields, { name = name, file = file_path, type = mime_type })
            else
              table.insert(form_fields, { name = name, value = val })
            end
          end
        end
        body = nil
        break
      end
    end
  end

  -- Parse response extractors embedded in the body text.
  -- Treesitter lumps everything after the headers into one body node, so we
  -- scan the raw body string for lines like @var = @response.body.foo and
  -- strip them out before sending the body over the wire.
  local response_extractors = {}
  if body then
    local body_lines = {}
    for line in body:gmatch('[^\r\n]+') do
      local name, target = line:match('^@([A-Za-z_][A-Za-z0-9_]*)%s*=%s*(@response%.[A-Za-z0-9_.%[%]-]+)%s*$')
      if name and target then
        table.insert(response_extractors, { name = name, target = target })
      else
        table.insert(body_lines, line)
      end
    end
    body = table.concat(body_lines, '\n')
    if body == '' then
      body = nil
    end
  end

  return {
    method = method,
    url = url,
    headers = headers,
    body = body,
    form_fields = form_fields,
    response_extractors = response_extractors,
  }
end

return M
