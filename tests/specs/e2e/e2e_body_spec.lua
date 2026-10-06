local e2e = require 'tests.helpers.e2e'

describe('e2e: request bodies', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('strips whole-line // comments from JSON bodies but keeps // in strings', function()
    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: application/json',
      '',
      '{',
      '  // strip me',
      '  "msg": "a // b",',
      '  "url": "http://x/a//b"',
      '}',
    }, '\n'))

    e2e.run_and_wait()
    local body = e2e.echo_result().body

    assert.falsy(body:find('strip me', 1, true))
    assert.truthy(body:find('a // b', 1, true))
    assert.truthy(body:find('http://x/a//b', 1, true))
  end)

  it('normalizes urlencoded bodies and applies {{$omit}}', function()
    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: application/x-www-form-urlencoded',
      '',
      'username=john',
      '&password={{$omit}}',
      '&age=30',
    }, '\n'))

    e2e.run_and_wait()
    assert.equals('username=john&age=30', e2e.echo_result().body)
  end)

  it('uploads multipart files with the correct content type', function()
    local file = e2e.write_file('avatar.txt', 'hello-file-content')
    e2e.write_http(table.concat({
      'POST ' .. e2e.url '/echo',
      'Content-Type: multipart/form-data',
      '',
      'description=hi',
      'avatar=< ' .. file,
    }, '\n'))

    e2e.run_and_wait()
    local result = e2e.echo_result()

    assert.truthy(result.body:find('hello%-file%-content'))
    assert.truthy(result.body:find('description', 1, true))
    assert.truthy((result.content_type or ''):find('multipart/form%-data'))
  end)
end)
