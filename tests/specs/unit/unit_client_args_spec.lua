local client = require 'curlonaut.client'

describe('client.build_args', function()
  it('includes method, url, verbose and the status writer', function()
    local args = client.build_args('http://x', 'POST', { ['Content-Type'] = 'application/json' }, '{"a":1}', nil, true)
    local joined = table.concat(args, '\n')
    assert.truthy(joined:find('-X\nPOST', 1, true))
    assert.truthy(joined:find('http://x', 1, true))
    assert.truthy(joined:find('__CURLONAUT_STATUS__', 1, true))
    assert.truthy(joined:find('-d\n{"a":1}', 1, true))
  end)

  it('omits the status writer when asked', function()
    local args = client.build_args('http://x', 'GET', {}, nil, nil, false)
    assert.falsy(table.concat(args, '\n'):find('__CURLONAUT_STATUS__', 1, true))
  end)

  it('drops the manual Content-Type for multipart uploads', function()
    local args = client.build_args('http://x', 'POST', { ['Content-Type'] = 'multipart/form-data' }, nil, {
      { name = 'a', value = 'b' },
    }, true)
    local joined = table.concat(args, '\n')
    assert.falsy(joined:find('Content%-Type'))
    assert.truthy(joined:find('-F\na=b', 1, true))
  end)

  it('does not mutate the caller headers table', function()
    local headers = { ['Content-Type'] = 'multipart/form-data' }
    client.build_args('http://x', 'POST', headers, nil, { { name = 'a', value = 'b' } }, true)
    assert.equals('multipart/form-data', headers['Content-Type'])
  end)
end)

describe('client.build_command_lines', function()
  it('shell-quotes arguments containing spaces', function()
    local joined = table.concat(client.build_command_lines('http://x', 'POST', {}, 'a b', nil), '\n')
    assert.truthy(joined:find("'a b'", 1, true))
  end)

  it('never includes the internal status writer', function()
    local joined = table.concat(client.build_command_lines('http://x'), '\n')
    assert.falsy(joined:find('__CURLONAUT_STATUS__', 1, true))
  end)
end)
