local e2e = require 'tests.helpers.e2e'

describe('e2e: environment and dynamic variables', function()
  before_each(function()
    e2e.cleanup()
    e2e.start_server()
  end)

  after_each(function()
    e2e.stop_server()
    e2e.cleanup()
  end)

  it('resolves .env, inline vars and $base64', function()
    e2e.write_file('.env.test', 'FROM_FILE=filevalue\nCREDS=user:pass\n')
    e2e.write_http(table.concat({
      '# @env-file .env.test',
      '@inline = inlinevalue',
      '',
      '###',
      '',
      'POST ' .. e2e.url '/echo',
      'Content-Type: text/plain',
      'X-File: {{FROM_FILE}}',
      'X-Inline: {{inline}}',
      'X-Auth: Basic {{$base64 CREDS}}',
      '',
      'payload={{FROM_FILE}}',
    }, '\n'))

    e2e.goto_line 'POST '
    e2e.run_and_wait()
    local result = e2e.echo_result()

    assert.equals('filevalue', result.headers['x-file'])
    assert.equals('inlinevalue', result.headers['x-inline'])
    assert.equals('Basic dXNlcjpwYXNz', result.headers['x-auth'])
    assert.equals('payload=filevalue', vim.trim(result.body))
  end)
end)
