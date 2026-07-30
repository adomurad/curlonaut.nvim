local M = {}

---@class SimpleRestParsedRequest
---@field method string
---@field url string
---@field headers table<string, string>
---@field body string|nil
---@field form_fields table[]|nil
---@field response_extractors table[]|nil
---@field curl_flags string[]|nil

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

---Extract @curl whitespace-split flags from comment children of a node.
---@param node TSNode
---@param bufnr integer
---@return string[]
local function extract_curl_flags(node, bufnr)
  local flags = {}
  for child, _ in node:iter_children() do
    if child:type() == 'comment' then
      local id_node = get_child(child, 'identifier')
      if id_node and get_text(id_node, bufnr) == 'curl' then
        local value_node = get_child(child, 'value')
        if value_node then
          local value = vim.trim(get_text(value_node, bufnr))
          for flag in value:gmatch('%S+') do
            table.insert(flags, flag)
          end
        end
      end
    end
  end
  return flags
end

---Extract @curl flags from a request node's parent section.
---Comments before the request line are children of `section`, not `request`.
---@param request_node TSNode
---@param bufnr integer
---@return string[]
local function extract_section_curl_flags(request_node, bufnr)
  local flags = {}
  local section = request_node:parent()
  if not section or section:type() ~= 'section' then
    return flags
  end
  local req_id = request_node:id()
  for child, _ in section:iter_children() do
    -- Only collect comments that appear before this request node
    if child:type() == 'comment' and child:id() ~= req_id then
      -- Ensure it's not inside another request in the same section
      local is_before = false
      for sib, _ in section:iter_children() do
        if sib:id() == req_id then
          break
        end
        if sib:id() == child:id() then
          is_before = true
          break
        end
      end
      if is_before then
        local id_node = get_child(child, 'identifier')
        if id_node and get_text(id_node, bufnr) == 'curl' then
          local value_node = get_child(child, 'value')
          if value_node then
            local value = vim.trim(get_text(value_node, bufnr))
            for flag in value:gmatch('%S+') do
              table.insert(flags, flag)
            end
          end
        end
      end
    end
  end
  return flags
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
  local url = get_text(url_node, bufnr):gsub('[\r\n]+%s*', '')

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
  -- Empty lines in the body are preserved.
  local response_extractors = {}
  if body then
    local body_lines = {}
    for line in (body .. '\n'):gmatch('([^\r\n]*)\r?\n') do
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

  local curl_flags = extract_curl_flags(request_node, bufnr)
  local section_flags = extract_section_curl_flags(request_node, bufnr)
  -- Pre-request section flags come first, then in-request flags
  local all_flags = vim.deepcopy(section_flags)
  for _, f in ipairs(curl_flags) do
    table.insert(all_flags, f)
  end

  return {
    method = method,
    url = url,
    headers = headers,
    body = body,
    form_fields = form_fields,
    response_extractors = response_extractors,
    curl_flags = all_flags,
  }
end

---Collect file-level @curl directives from sections before the first request.
---@param bufnr integer
---@return string[]
function M.get_file_curl_flags(bufnr)
  bufnr = bufnr or 0
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr, 'http')
  if not ok then
    return {}
  end
  parser:parse()
  local tree = parser:trees()[1]
  if not tree then
    return {}
  end

  local flags = {}
  for section, _ in tree:root():iter_children() do
    if section:type() == 'section' then
      -- Stop at first section that contains a request or separator
      local has_request = false
      for child, _ in section:iter_children() do
        local t = child:type()
        if t == 'request' or t == 'request_separator' then
          has_request = true
          break
        end
      end
      if has_request then
        break
      end
      -- Extract @curl from this section's comments
      for child, _ in section:iter_children() do
        if child:type() == 'comment' then
          local id_node = get_child(child, 'identifier')
          if id_node and get_text(id_node, bufnr) == 'curl' then
            local value_node = get_child(child, 'value')
            if value_node then
              local value = vim.trim(get_text(value_node, bufnr))
              for flag in value:gmatch('%S+') do
                table.insert(flags, flag)
              end
            end
          end
        end
      end
    end
  end
  return flags
end

return M
