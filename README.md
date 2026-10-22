# whatsthis.nvim

Press one key on any code in Neovim and get a short AI explanation of what it does, in a popup next to the cursor. No chat, no typing, no API key: it runs through a coding CLI you already have ([pi](https://github.com/badlogic/pi-mono) or [Claude Code](https://docs.anthropic.com/en/docs/claude-code)).

It decides what you are asking about:

| Cursor on… | Explains |
|---|---|
| A visual selection | The selection, with the signature of the function it sits in |
| A call to something defined elsewhere | **That definition**, found through your language server, without opening its file |
| A function, method or class (signature or body) | The whole function, method or class |

The second row is the point of the plugin: put the cursor on `retryWithBackoff(...)` in the file you are reading and learn what it does, without jumping away.

Answers are a one-sentence summary plus a few bullets on inputs, output and side effects. A typical answer takes 3 to 5 seconds.

## Requirements

- Neovim 0.11 or newer
- One of these CLIs on your `PATH`, logged in:
  - [pi](https://github.com/badlogic/pi-mono) (default), with access to an Anthropic model
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`claude`)
- A treesitter parser for your language, to find the function or class around the cursor
- A language server, to explain definitions in other files (optional: without one, the code under the cursor is explained)

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "julianbonomini/whatsthis.nvim",
  opts = {},
  keys = {
    { "<leader>ae", "<Plug>(WhatsThis)", mode = { "n", "x" }, desc = "What's this?" },
  },
}
```

The plugin sets no keymaps on its own. Loading it at startup only defines one command and one `<Plug>` mapping, so there is no need to lazy-load it, and `:checkhealth whatsthis` only finds plugins that are loaded.

## Usage

- `<Plug>(WhatsThis)` in normal or visual mode, mapped to the key of your choice.
- `:WhatsThis` explains what is under the cursor; `:'<,'>WhatsThis` explains a range of lines.

In the popup:

- Press the key again to move into the popup, to scroll or copy.
- `q` or `<Esc>` closes it. Moving the cursor away closes it too.
- Closing the popup before the answer arrives stops the CLI.

## Configuration

These are the defaults:

```lua
require("whatsthis").setup({
  runner = "pi", -- "pi" or "claude", or the name of a runner you add below
  runners = {
    pi = { model = "anthropic/claude-haiku-5-5" },
    claude = { model = "haiku" },
  },
  max_lines = 300, -- longest code block sent to the model
  lsp_timeout_ms = 1500, -- after this, explain the code under the cursor instead of its definition
  window = {
    border = "rounded",
    max_width = 100,
    max_height = 0.5, -- fraction of the editor height
  },
})
```

The instruction sent to the model is `system_prompt`; see [`config.lua`](lua/whatsthis/config.lua) for the default.

### Adding a runner

A runner is a function that returns the command to run. The prompt arrives on stdin, and the answer is read from stdout:

```lua
-- Simon Willison's `llm` CLI, with any model it supports
require("whatsthis").setup({
  runner = "llm",
  runners = {
    llm = {
      model = "gpt-4o-mini",
      build = function(system_prompt, runner)
        return { "llm", "-m", runner.model, "-s", system_prompt }
      end,
    },
  },
})
```

## Why it is fast

Coding CLIs load tools, extensions, project instruction files and a long system prompt on every call. For a one-off question none of that is needed, so whatsthis.nvim turns it all off and replaces the system prompt with a four-line one. Measured with Claude Code and Haiku: turning off tools, MCP servers and settings cut a minimal call from 4.4 to 2.0 seconds, and replacing the system prompt cut a call explaining a short function from 7.9 to 5.4 seconds. The CLI also runs outside your project, so project instruction files such as `CLAUDE.md` are never read.

## Privacy

The code being explained, its file path and, for definitions, the line you called it from, are sent to the model provider configured in your CLI. Nothing else from your project is sent.

## Health check

```vim
:checkhealth whatsthis
```

## License

MIT
