local dv = require 'curlonaut.dynamic_vars'

describe('dynamic_vars', function()
  it('generates a v4 UUID', function()
    local out = dv.substitute('{{$uuid}}', {})
    assert.truthy(out:match '^%x%x%x%x%x%x%x%x%-%x%x%x%x%-4%x%x%x%-[89ab]%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')
  end)

  it('honours the range for $randomInt', function()
    for _ = 1, 50 do
      local out = dv.substitute('{{$randomInt 5 6}}', {})
      local n = tonumber(out)
      assert.is_true(n == 5 or n == 6)
    end
  end)

  it('produces a requested number of hex characters', function()
    local out = dv.substitute('{{$randomHex 32}}', {})
    assert.equals(32, #out)
    assert.truthy(out:match '^%x+$')
  end)

  it('base64-encodes an env variable by name', function()
    assert.equals('dXNlcjpwYXNz', dv.substitute('{{$base64 CREDS}}', { CREDS = 'user:pass' }))
  end)

  it('base64-encodes literal text when no env var matches', function()
    assert.equals('dXNlcjpwYXNz', dv.substitute('{{$base64 user:pass}}', {}))
  end)

  it('returns the omit sentinel for $omit', function()
    assert.equals(dv.OMIT_SENTINEL, dv.substitute('{{$omit}}', {}))
  end)

  it('substitutes an empty string for unknown providers', function()
    assert.equals('', dv.substitute('{{$does_not_exist}}', {}))
  end)
end)
