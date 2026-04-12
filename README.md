# Restman.nvim

**REST client for Neovim** — Send HTTP requests directly from your editor with syntax highlighting, pretty-printed responses, and seamless integration.

**Triết lý:** One-key experience, frictionless. Đặt con trỏ trên dòng request → bấm 1 phím → nhận kết quả trong floating window.

## Features

- ✅ **Multiple request formats:** HTTP-style, cURL, DSL
- ✅ **Async HTTP client** with timeout, headers, query params, form data, JSON body
- ✅ **Response viewer** with syntax highlighting (JSON/HTML/XML)
- ✅ **Floating window** + split/vsplit/tab modes
- ✅ **Environment support** with variable substitution
- ✅ **Request history** with LRU buffer management (10 buffers max)
- ✅ **Telescope picker** for environment/history selection (with fallback to `vim.ui.select`)
- ✅ **Keymaps** for easy navigation and response inspection
- ✅ **Pretty-printed JSON** with proper syntax highlighting

## Requirements

- Neovim ≥ 0.10
- `curl` in PATH
- (Optional) Telescope for enhanced picker experience

## Installation

Using `lazy.nvim`:

```lua
{
  "nxhung2304/restman.nvim",
  config = function()
    require("restman").setup()
  end,
}
```

Using `packer.nvim`:

```lua
use {
  "nxhung2304/restman.nvim",
  config = function()
    require("restman").setup()
  end,
}
```

## Quick Start

### 1. Create a request file

Create a file named `requests.http`:

```http
GET https://jsonplaceholder.typicode.com/posts/1
```

### 2. Send the request

- Position cursor on the request line
- Press `<leader>rs` (default keymap)
- Or run `:Restman send`

### 3. View response

Float window opens showing:
- Status line: `200 OK   •   142ms   •   1.2 KB`
- Separators and toggle hints
- Pretty-printed JSON body

**Navigate response:**
- `q` or `<Esc>` — Close
- `H` — Toggle headers
- `B` — Show body
- `R` — Show raw
- `y` — Copy body to clipboard
- `yy` — Copy full response
- `<CR>` — Save body to file
- `s`/`v`/`t` — Promote to split/vsplit/tab

## Request Formats

### HTTP-style (recommended)

```http
GET https://api.example.com/users

POST https://api.example.com/users
Content-Type: application/json
Authorization: Bearer token123

{
  "name": "John",
  "email": "john@example.com"
}
```

### cURL format

```bash
curl -X GET https://jsonplaceholder.typicode.com/posts/1

curl -X POST https://api.example.com/users \
  -H "Content-Type: application/json" \
  -d '{"name":"John"}'
```

### Query parameters

```http
GET https://jsonplaceholder.typicode.com/posts?userId=1&_limit=5
```

### Form data

```http
POST https://api.example.com/form
Content-Type: application/x-www-form-urlencoded

field1=value1&field2=value2
```

## Commands

| Command | Action |
|---------|--------|
| `:Restman send` | Send request at cursor |
| `:Restman repeat` | Re-send last request |
| `:Restman env` | Switch environment |
| `:Restman history` | Open response history picker |
| `:Restman cancel` | Cancel in-flight request |
| `:Restman health` | Show plugin diagnostics |

### Command completion

Type `:Restman <Tab>` to see available subcommands.

## Default Keymaps

| Keymap | Action |
|--------|--------|
| `<leader>rs` | Send request (normal + visual) |
| `<leader>rr` | Repeat last request |
| `<leader>re` | Select environment |
| `<leader>rh` | Open history |
| `<leader>rc` | Cancel request |

## Configuration

Default configuration (can be overridden in `setup()`):

```lua
require("restman").setup({
  keymaps = {
    send = "<leader>rs",
    repeat_last = "<leader>rr",
    env = "<leader>re",
    history = "<leader>rh",
    cancel = "<leader>rc",
  },
  response_view = {
    default_view = "float",  -- "float" | "split" | "vsplit" | "tab"
    float = {
      relative = "editor",
      width = 0.8,   -- 80% of editor width
      height = 0.7,  -- 70% of editor height
      border = "rounded",
    },
    split = {
      position = "right",
      size = 80,  -- column width
    },
  },
  timeout = 30,  -- request timeout in seconds
  history = {
    enabled = true,
    max_entries = 100,
  },
})
```

## Environment Variables

Create `.env.json` in your project root:

```json
{
  "default": "development",
  "environments": {
    "development": {
      "base_url": "http://localhost:3000",
      "variables": {
        "TOKEN": "dev-token-123",
        "API_KEY": "dev-key"
      },
      "headers": {
        "Authorization": "Bearer {{TOKEN}}"
      }
    },
    "production": {
      "base_url": "https://api.example.com",
      "variables": {
        "TOKEN": "prod-token-xyz"
      }
    }
  }
}
```

Use variables in requests:

```http
GET {{base_url}}/users
Authorization: Bearer {{TOKEN}}
X-API-Key: {{API_KEY}}
```

## Response Buffer Keymaps

When response window is open, these keys are available:

| Key | Action |
|-----|--------|
| `q`, `<Esc>` | Close response |
| `H` | Toggle headers view |
| `B` | Show body only |
| `R` | Toggle raw/pretty view |
| `y` | Yank body to clipboard |
| `yy` | Yank full response to clipboard |
| `<CR>` | Save body to file (prompts for path) |
| `s` | Promote to split window |
| `v` | Promote to vsplit window |
| `t` | Promote to tab window |
| `<C-o>` | Open response history picker |

## Examples

### GET request with query params

```http
GET https://jsonplaceholder.typicode.com/posts?userId=1&_limit=3
```

### POST with JSON body

```http
POST https://jsonplaceholder.typicode.com/posts
Content-Type: application/json

{
  "title": "Test Post",
  "body": "This is a test",
  "userId": 1
}
```

### PUT with authorization

```http
PUT https://api.example.com/users/123
Authorization: Bearer eyJhbGc...
Content-Type: application/json

{
  "name": "Updated Name",
  "email": "new@example.com"
}
```

### Multiline body with visual selection

Select lines with `V`, then `:Restman send` to use selection as body:

```http
POST https://api.example.com/data
Content-Type: application/json

{selected lines become the request body}
```

## Limitations & Roadmap

### Current (v1.0 MVP - Issues #9-#13)
✅ Buffer management (LRU eviction)  
✅ Response rendering (prettify, syntax highlight)  
✅ View layer (float/split/promote)  
✅ Picker abstraction (Telescope + fallback)  
✅ Commands dispatcher & keymaps  
✅ HTTP client (async curl)  
✅ Environment loader & variable substitution  
✅ Request parser (HTTP/cURL/DSL formats)  

### Future (Issues #14-#16)
📋 Response history persistence  
📋 Rails routes integration  
📋 Health check / curl version detection  

## Troubleshooting

### "Plugin loaded. Subcommands not yet implemented."

This is the old stub message. Make sure you:
1. Have the latest code (`git pull`)
2. Called `require("restman").setup()` in your config
3. Restarted Neovim or reloaded config (`:source %`)

### "ENOENT: no such file or directory (cmd): '-sS'"

Curl is not in your PATH or Neovim can't find it. Verify:
```bash
which curl
echo $PATH
```

In Neovim, check with:
```vim
:lua print(vim.fn.system("which curl"))
```

### Response shows "Unknown" status text

This is normal for non-standard status codes. Common codes (200, 404, 500, etc.) are always recognized.

### Float window doesn't appear

Try these alternatives:
```vim
:Restman send    " try again
:Restman send | set splitright | split  " use split instead
```

Check `:messages` for error details.

## Development

### Running tests

```bash
nvim --headless -c "luafile lua/restman/ui/buffer_test.lua" -c "qa!"
```

### Project structure

```
restman.nvim/
├── lua/restman/
│   ├── init.lua                 # Entry point, setup()
│   ├── config.lua              # Configuration schema
│   ├── log.lua                 # Logging utility
│   ├── http_client.lua         # Async curl wrapper
│   ├── env.lua                 # Environment loader
│   ├── parser/                 # Request parsers
│   │   ├── init.lua            # Dispatcher
│   │   ├── http.lua            # HTTP-style parser
│   │   ├── curl.lua            # cURL parser
│   │   └── ...
│   └── ui/
│       ├── buffer.lua          # Buffer management (LRU)
│       ├── render.lua          # Response formatting
│       ├── view.lua            # Window management
│       └── picker.lua          # Picker abstraction
├── plugin/
│   └── restman.lua            # Plugin entry
├── lua/telescope/
│   └── _extensions/
│       └── restman.lua        # Telescope extension
└── specs/
    ├── story.md               # Full specification
    ├── example/
    │   └── v1-usage.md       # Usage examples
    └── issues/                # Individual issue specs
```

### Key modules

- **parser**: Parse HTTP requests from multiple formats
- **http_client**: Send requests asynchronously via curl
- **env**: Load `.env.json` and substitute variables
- **ui.buffer**: Manage response buffers with LRU eviction
- **ui.render**: Format responses with syntax highlighting
- **ui.view**: Open/close/promote response windows
- **ui.picker**: Abstract picker (Telescope/vim.ui.select)
- **commands**: Main dispatcher and keymaps

## License

MIT

## Contributing

Issues and PRs welcome! Check `specs/story.md` for architecture and DoD criteria.

---

Made with ❤️ for frictionless REST testing in Neovim
