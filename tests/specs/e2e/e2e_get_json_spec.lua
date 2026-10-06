local e2e = require 'tests.helpers.e2e'

describe('e2e: GET + response extractors', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('renders the status and extracts JSON body values into session vars', function()
    e2e.write_http(table.concat({
      '@base = ' .. e2e.url '/json',
      '',
      '###',
      '',
      'GET {{base}}',
      '',
      '@TOKEN = @response.body.token',
      '@ID = @response.body.items[0].id',
    }, '\n'))

    e2e.goto_line 'GET '
    local lines = e2e.run_and_wait()
    local joined = table.concat(lines, '\n')

    assert.truthy(joined:find('Status: 200', 1, true))
    assert.truthy(joined:find('abc123', 1, true))

    local session = require('curlonaut.env').session_vars
    assert.equals('abc123', session.TOKEN)
    assert.equals('7', session.ID)
  end)
end)
