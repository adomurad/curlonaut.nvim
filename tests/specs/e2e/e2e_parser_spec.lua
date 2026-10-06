local e2e = require 'tests.helpers.e2e'

describe('e2e: parser and body handling', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('joins multiline URLs into a single request target', function()
    e2e.write_http(table.concat({
      'GET ' .. e2e.url '/echo',
      '  ?q=neovim',
      '  &limit=10',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('/echo?q=neovim&limit=10', e2e.echo_result().path)
  end)

  it('applies per-file @curl flags', function()
    e2e.write_http(table.concat({
      '# @curl --user-agent file-agent',
      '',
      '###',
      '',
      'GET ' .. e2e.url '/echo',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('file-agent', e2e.echo_result().headers['user-agent'])
  end)

  it('lets per-request @curl flags override per-file flags', function()
    e2e.write_http(table.concat({
      '# @curl --user-agent file-agent',
      '',
      '###',
      '',
      '# @curl --user-agent req-agent',
      '',
      'GET ' .. e2e.url '/echo',
    }, '\n'))

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('req-agent', e2e.echo_result().headers['user-agent'])
  end)

  it('only strips whole-line // comments from JSON bodies', function()
    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: application/json',
      '',
      '{',
      '  "a": 1, // trailing stays',
      '  // leading goes',
      '  "b": "x//y"',
      '}',
    }, '\n'))

    e2e.goto_line 'POST '
    e2e.run_and_wait()
    local body = e2e.echo_result().body

    assert.truthy(body:find('// trailing stays', 1, true))
    assert.falsy(body:find('// leading goes', 1, true))
    assert.truthy(body:find('x//y', 1, true))
  end)

  it('omits a query parameter marked with {{$omit}}', function()
    e2e.write_http('GET ' .. e2e.url '/echo?active={{$omit}}&limit=10')

    e2e.goto_line 'GET '
    e2e.run_and_wait()

    assert.equals('/echo?limit=10', e2e.echo_result().path)
  end)

  it('omits a multipart field marked with {{$omit}}', function()
    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: multipart/form-data',
      '',
      'description=hi',
      'avatar={{$omit}}',
    }, '\n'))

    e2e.goto_line 'POST '
    e2e.run_and_wait()
    local body = e2e.echo_result().body

    assert.truthy(body:find('description', 1, true))
    assert.falsy(body:find('avatar', 1, true))
  end)

  it('honours an explicit multipart MIME type override', function()
    local file = e2e.write_file('report.pdf', 'PDFDATA')
    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: multipart/form-data',
      '',
      'report=< ' .. file .. ';type=application/pdf',
    }, '\n'))

    e2e.goto_line 'POST '
    e2e.run_and_wait()
    local body = e2e.echo_result().body

    assert.truthy(body:find('application/pdf', 1, true))
    assert.truthy(body:find('PDFDATA', 1, true))
  end)

  it('errors before sending when a multipart file is missing', function()
    e2e.reset_hits()
    local before = e2e.server_hits()

    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: multipart/form-data',
      '',
      'avatar=< /nonexistent/curlonaut-missing.png',
    }, '\n'))

    local messages = e2e.capture_notifications(function()
      e2e.goto_line 'POST '
      e2e.run_and_expect_no_response()
    end)

    local found = false
    for _, msg in ipairs(messages) do
      if msg:find('Multipart file not found', 1, true) then
        found = true
      end
    end
    assert.is_true(found)
    assert.equals(before, e2e.server_hits())
  end)
end)
