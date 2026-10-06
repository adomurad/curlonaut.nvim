local e2e = require 'tests.helpers.e2e'

describe('e2e: cookie jar', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('persists cookies between requests in the same file', function()
    e2e.write_http(table.concat({
      '# @cookie-jar',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/set-cookie',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/check-cookie',
    }, '\n'))

    e2e.goto_line '/set-cookie'
    e2e.run_and_wait()

    e2e.goto_line '/check-cookie'
    e2e.run_and_wait()

    assert.truthy(e2e.echo_result().cookie:find('session=xyz', 1, true))

    local cookies_tab = table.concat(e2e.tab_lines 'cookies', '\n')
    assert.truthy(cookies_tab:find('session', 1, true))
    assert.truthy(cookies_tab:find('xyz', 1, true))
  end)
end)
