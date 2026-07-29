# curlonaut.nvim

A rest client for NVIM.

Uses .rest / .http files and curl to send the requests.

This is a simple project - mainly suited to solve my needs.

## Installation

### lazy.nvim

```lua
{
  'adomurad/curlonaut.nvim',
  ft = { 'http', 'rest' },
  config = function()
    require('curlonaut').setup {
      formatters = {
        json = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.json' } },
        html = { command = 'prettierd', args = { '--stdin-filepath', '/tmp/curlonaut_response.html' } },
        xml  = { command = 'xmllint',   args = { '--format', '-' } },
      },
    }

    vim.api.nvim_create_autocmd('FileType', {
      pattern = { 'http', 'rest' },
      callback = function(args)
        vim.keymap.set('n', '<CR>', function()
          vim.cmd 'Curlonaut RunRequest'
        end, { buffer = args.buf, desc = 'Run REST request under cursor' })
      end,
    })
  end,
}
```

## Commands

| Command | Action |
|---|---|
| `:Curlonaut Open` | Open the results panel |
| `:Curlonaut Close` | Close the results panel |
| `:Curlonaut Toggle` | Toggle the results panel |
| `:Curlonaut RunRequest` | Execute the request under cursor |
| `:Curlonaut CopyCurl` | Copy the shell-escaped curl command under cursor to clipboard (does not run) |

The results panel has four tabs: **Simple** (response only), **Full** (request + response), **Verbose** (live curl stderr), and **Curl** (the exact shell-safe curl command used, ready to copy and paste into a terminal).

## .http File Format

```http
# @env-file ./.env.local

@base_url = https://api.example.com

###

GET {{base_url}}/users

###

POST {{base_url}}/users
Content-Type: application/json

{
  "name": "Ada"
}
```

### URL-encoded body

```http
POST {{base_url}}/login
Content-Type: application/x-www-form-urlencoded

username=john
&password=secret
&age=30
```

Formatting newlines before `&` and at the end of the body are stripped automatically.

### Multipart / File upload

```http
POST {{base_url}}/upload
Content-Type: multipart/form-data

description=hello
avatar=< ./avatar.png
report=< ./report.pdf;type=application/pdf
```

Use `< ./path` for file uploads. Append `;type=mime/type` to override the MIME type.

### Response extractors

After a request completes you can pull values from the response body or headers and save them as session-scoped variables for later requests.

```http
POST {{base_url}}/login
Content-Type: application/json

{
  "username": "admin",
  "password": "secret"
}

@ACCESS_TOKEN = @response.body.token
@REQUEST_ID = @response.headers.x-request-id

GET {{base_url}}/users
Authorization: Bearer {{ACCESS_TOKEN}}
```

- `@response.body.path` — JSON dot-path, supports arrays like `items[0].id`
- `@response.headers.name` — case-insensitive header lookup

## Environment Variables

Variable resolution priority (highest first):

1. Response extractors (`@var = @response.body...` set after a request)
2. Inline `@variable = value` declarations in the `.http` file
3. Variables from the `.env` file specified via `# @env-file ./path`
4. Shell environment variables

Use `{{VAR_NAME}}` anywhere in the URL, headers, or body.

## Health Check

Run `:checkhealth curlonaut` to verify dependencies.
