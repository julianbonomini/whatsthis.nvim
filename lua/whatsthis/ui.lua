local config = require("whatsthis.config")

local M = {}

---@class whatsthis.Popup
---@field buf integer
---@field win integer
---@field source_win integer
local Popup = {}
Popup.__index = Popup

local function wrapped_height(lines, width)
  local height = 0
  for _, line in ipairs(lines) do
    height = height + math.max(1, math.ceil(vim.fn.strdisplaywidth(line) / width))
  end
  return height
end

function Popup:_layout(lines)
  local opts = config.options.window
  local widest = 0
  for _, line in ipairs(lines) do
    widest = math.max(widest, vim.fn.strdisplaywidth(line))
  end
  -- Align with the start of the code on the cursor line, so the popup reads as a note on that
  -- line instead of covering whatever sits to the right of the cursor.
  local cursor = vim.api.nvim_win_get_cursor(self.source_win)
  local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(self.source_win), cursor[1] - 1, cursor[1], false)[1] or ""
  local code_col = math.max(0, (line:find("%S") or 1) - 1)
  local info = vim.fn.getwininfo(self.source_win)[1]
  local room = info.width - info.textoff - vim.fn.strdisplaywidth(line:sub(1, code_col)) - 2

  local width = math.max(20, math.min(widest, opts.max_width, room))
  local max_height = math.max(3, math.floor(vim.o.lines * opts.max_height))
  local height = math.min(wrapped_height(lines, width), max_height)

  -- Open below the cursor unless that would run off the screen.
  local screen_row = vim.fn.screenpos(self.source_win, cursor[1], cursor[2] + 1).row
  local below = screen_row + height + 2 <= vim.o.lines - vim.o.cmdheight
  return {
    relative = "win",
    win = self.source_win,
    bufpos = { cursor[1] - 1, code_col },
    anchor = below and "NW" or "SW",
    row = below and 1 or 0,
    col = 0,
    width = width,
    height = height,
  }
end

---@param lines string[]
function Popup:set(lines)
  if not self:is_open() then
    return
  end
  vim.bo[self.buf].modifiable = true
  vim.api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  vim.bo[self.buf].modifiable = false
  vim.api.nvim_win_set_config(self.win, self:_layout(lines))
end

function Popup:is_open()
  return vim.api.nvim_win_is_valid(self.win)
end

function Popup:focus()
  if self:is_open() then
    vim.api.nvim_set_current_win(self.win)
  end
end

function Popup:close()
  if self:is_open() then
    vim.api.nvim_win_close(self.win, true)
  end
end

---@param cb fun()
function Popup:on_close(cb)
  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(self.win),
    once = true,
    callback = cb,
  })
end

---@param lines string[]
---@return whatsthis.Popup
function M.open(lines)
  local self = setmetatable({ source_win = vim.api.nvim_get_current_win() }, Popup)
  local source_buf = vim.api.nvim_get_current_buf()

  self.buf = vim.api.nvim_create_buf(false, true)
  vim.bo[self.buf].bufhidden = "wipe"
  vim.bo[self.buf].filetype = "markdown"

  -- Defined on every open because a colorscheme change clears highlight groups; `default`
  -- keeps any colors the user set.
  vim.api.nvim_set_hl(0, "WhatsThisBorder", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "WhatsThisTitle", { link = "Title", default = true })

  local layout = self:_layout(lines)
  layout.border = config.options.window.border
  layout.title = { { " What's this? ", "WhatsThisTitle" } }
  layout.title_pos = "left"
  layout.style = "minimal"
  layout.focusable = true
  layout.noautocmd = true
  self.win = vim.api.nvim_open_win(self.buf, false, layout)
  vim.wo[self.win].wrap = true
  vim.wo[self.win].linebreak = true
  vim.wo[self.win].conceallevel = 2
  vim.wo[self.win].winhighlight = "FloatBorder:WhatsThisBorder"
  self:set(lines)

  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      self:close()
    end, { buffer = self.buf, nowait = true })
  end

  -- Like hover: moving away closes the popup, unless the user jumped into it.
  local group = vim.api.nvim_create_augroup("whatsthis_popup_" .. self.win, { clear = true })
  vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
    group = group,
    buffer = source_buf,
    callback = function()
      if vim.api.nvim_get_current_win() ~= self.win then
        self:close()
      end
    end,
  })
  self:on_close(function()
    pcall(vim.api.nvim_del_augroup_by_id, group)
  end)

  return self
end

return M
