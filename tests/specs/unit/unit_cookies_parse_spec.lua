local cookies = require 'curlonaut.cookies'

describe('cookies.parse_cookies', function()
  it('parses Netscape cookie lines, including #HttpOnly_ entries', function()
    local content = table.concat({
      '# Netscape HTTP Cookie File',
      '.example.com\tTRUE\t/\tFALSE\t0\tsession\tabc',
      '#HttpOnly_.example.com\tTRUE\t/\tTRUE\t1893456000\tsecret\txyz',
      '',
    }, '\n')

    local parsed = cookies.parse_cookies(content)
    assert.equals(2, #parsed)
    assert.equals('session', parsed[1].name)
    assert.equals('abc', parsed[1].value)
    assert.is_false(parsed[1].httponly)
    assert.equals('secret', parsed[2].name)
    assert.is_true(parsed[2].httponly)
  end)

  it('ignores comments and malformed lines', function()
    local parsed = cookies.parse_cookies('# comment\nnot-a-cookie\n')
    assert.equals(0, #parsed)
  end)
end)

describe('cookies.format_cookies', function()
  it('marks an empty jar', function()
    local text = table.concat(cookies.format_cookies {}, '\n')
    assert.truthy(text:find('empty', 1, true))
  end)

  it('renders cookie fields', function()
    local text = table.concat(cookies.format_cookies {
      { domain = '.example.com', name = 'session', value = 'abc', path = '/', https = 'FALSE', expires = '0', httponly = true },
    }, '\n')
    assert.truthy(text:find('session', 1, true))
    assert.truthy(text:find('abc', 1, true))
    assert.truthy(text:find('HttpOnly: TRUE', 1, true))
    assert.truthy(text:find('Expires:  Session', 1, true))
  end)
end)
