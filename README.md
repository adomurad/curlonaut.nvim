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
          vim.cmd 'Curlonaut RunRequestUnderCursor'
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
| `:Curlonaut RunRequestUnderCursor` | Execute the request at cursor |

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

## Environment Variables

Variable resolution priority (highest first):

1. Inline `@variable = value` declarations in the `.http` file
2. Variables from the `.env` file specified via `# @env-file ./path`
3. Shell environment variables

Use `{{VAR_NAME}}` anywhere in the URL, headers, or body.

## Health Check

Run `:checkhealth curlonaut` to verify dependencies.
