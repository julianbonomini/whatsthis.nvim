local config = require("whatsthis.config")
local context = require("whatsthis.context")
local runner = require("whatsthis.runner")
local ui = require("whatsthis.ui")

local M = {}

---@type whatsthis.Popup?
local current

---@param opts? table see `whatsthis.Config`
function M.setup(opts)
  config.setup(opts)
end

---@param popup whatsthis.Popup
---@param target whatsthis.Target?
local function explain_target(popup, target)
  if not popup:is_open() then
    return
  end
  if not target then
    popup:set({ "_Nothing to explain here: no function, method or class around the cursor._" })
    return
  end
  popup:set({ ("_Explaining `%s`…_"):format(target.label) })

  local started = vim.uv.now()
  local proc = runner.run(context.prompt(target), function(ok, text)
    local lines = ok and vim.split(vim.trim(text), "\n")
      or { ("**%s failed**"):format(config.options.runner), "", text }
    vim.list_extend(lines, { "", ("_%s · %.1fs_"):format(target.location, (vim.uv.now() - started) / 1000) })
    popup:set(lines)
  end)
  if proc then
    popup:on_close(function()
      if not proc:is_closing() then
        proc:kill("sigterm")
      end
    end)
  end
end

---@class whatsthis.ExplainOpts
---@field range? { [1]: integer, [2]: integer } 1-based line range, as from a `:'<,'>` command

-- Explains the selection (visual mode or `range`), the definition behind the call under the
-- cursor, or the function/method/class around the cursor. Calling it again while a popup is
-- open moves into the popup, like pressing `K` twice.
---@param opts? whatsthis.ExplainOpts
function M.explain(opts)
  opts = opts or {}
  if current and current:is_open() and vim.api.nvim_get_current_win() ~= current.win then
    current:focus()
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local win = vim.api.nvim_get_current_win()
  local mode = vim.fn.mode()

  local selection
  if mode:match("^[vV\22]") then
    local s, e = vim.fn.getpos("v"), vim.fn.getpos(".")
    selection = {
      first = math.min(s[2], e[2]),
      last = math.max(s[2], e[2]),
      lines = vim.fn.getregion(s, e, { type = mode }),
    }
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
  elseif opts.range then
    selection = {
      first = opts.range[1],
      last = opts.range[2],
      lines = vim.api.nvim_buf_get_lines(buf, opts.range[1] - 1, opts.range[2], false),
    }
  end

  current = ui.open({ "_Looking…_" })
  local popup = current
  if selection then
    explain_target(popup, context.from_selection(buf, selection.first, selection.last, selection.lines))
  else
    context.from_cursor(buf, win, function(target)
      explain_target(popup, target)
    end)
  end
end

return M
