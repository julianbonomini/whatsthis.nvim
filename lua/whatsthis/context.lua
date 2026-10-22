-- Works out what the user is asking about: a selection, the definition behind a call, or the
-- function/method/class around the cursor.

local config = require("whatsthis.config")

local M = {}

local DECLARATION_TYPES = {
  -- TypeScript / JavaScript
  function_declaration = true,
  generator_function_declaration = true,
  method_definition = true,
  class_declaration = true,
  abstract_class_declaration = true,
  interface_declaration = true,
  type_alias_declaration = true,
  enum_declaration = true,
  method_signature = true,
  abstract_method_signature = true,
  function_signature = true,
  -- Python
  function_definition = true,
  class_definition = true,
  -- Go
  method_declaration = true,
  type_declaration = true,
  -- Rust
  function_item = true,
  impl_item = true,
  struct_item = true,
  enum_item = true,
  trait_item = true,
}

-- `const foo = () => {}` is a declaration only at the top level; inside a function body a
-- `const` line is just a statement and the enclosing function is the better answer.
local TOP_LEVEL_ONLY = {
  lexical_declaration = true,
  variable_declaration = true,
}

local WRAPPERS = {
  export_statement = true,
  decorated_definition = true,
}

---@class whatsthis.Source
---@field path string
---@field lines string[]
---@field root? TSNode

---@param buf integer
---@return whatsthis.Source
local function source_from_buffer(buf)
  local source = {
    path = vim.api.nvim_buf_get_name(buf),
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false),
  }
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if ok and parser then
    source.root = parser:parse()[1]:root()
  end
  return source
end

-- Parses a file without loading it into a buffer, so peeking at a definition never attaches
-- language servers or fires autocommands for a file the user did not open.
---@param path string
---@return whatsthis.Source?
local function source_from_path(path)
  local loaded = vim.fn.bufnr(path)
  if loaded ~= -1 and vim.api.nvim_buf_is_loaded(loaded) then
    return source_from_buffer(loaded)
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then
    return nil
  end
  local source = { path = path, lines = lines }
  local ft = vim.filetype.match({ filename = path, contents = lines })
  local lang = ft and vim.treesitter.language.get_lang(ft)
  if lang then
    local parsed, parser = pcall(vim.treesitter.get_string_parser, table.concat(lines, "\n"), lang)
    if parsed and parser then
      source.root = parser:parse()[1]:root()
    end
  end
  return source
end

local function is_declaration(node)
  local type = node:type()
  if DECLARATION_TYPES[type] then
    return true
  end
  if TOP_LEVEL_ONLY[type] then
    local parent = node:parent()
    return parent == nil or parent:parent() == nil or WRAPPERS[parent:type()] == true
  end
  return false
end

---@param source whatsthis.Source
---@return TSNode?
local function enclosing_declaration(source, row, col)
  if not source.root then
    return nil
  end
  local node = source.root:named_descendant_for_range(row, col, row, col)
  while node and not is_declaration(node) do
    node = node:parent()
  end
  if node and node:parent() and WRAPPERS[node:parent():type()] then
    node = node:parent()
  end
  return node
end

local function rel(path)
  return vim.fn.fnamemodify(path, ":~:.")
end

---@class whatsthis.Target
---@field label string shown while waiting
---@field location string path:start-end
---@field code string
---@field inside? string signature of the declaration a selection sits in
---@field called_from? string the line the user was on when explaining a definition elsewhere

---@param source whatsthis.Source
---@return whatsthis.Target?
local function target_from_declaration(source, row, col)
  local node = enclosing_declaration(source, row, col)
  if not node then
    return nil
  end
  local srow, _, erow = node:range()
  local last = math.min(erow, srow + config.options.max_lines - 1)
  local code = table.concat(vim.list_slice(source.lines, srow + 1, last + 1), "\n")
  return {
    label = vim.trim(source.lines[srow + 1] or ""):sub(1, 60),
    location = ("%s:%d-%d"):format(rel(source.path), srow + 1, last + 1),
    code = code,
  }
end

---@param buf integer
---@param first integer 1-based
---@param last integer 1-based
---@param lines string[]
---@return whatsthis.Target
function M.from_selection(buf, first, last, lines)
  local source = source_from_buffer(buf)
  local target = {
    label = "selection",
    location = ("%s:%d-%d"):format(rel(source.path), first, last),
    code = table.concat(lines, "\n"),
  }
  local node = enclosing_declaration(source, first - 1, 0)
  if node then
    local srow, _, erow = node:range()
    if srow + 1 < first or erow + 1 > last then
      target.inside = vim.trim(source.lines[srow + 1] or "")
    end
  end
  return target
end

-- Resolves the cursor position asynchronously: if go-to-definition points somewhere else, that
-- definition is explained; otherwise the declaration around the cursor is.
---@param buf integer
---@param win integer
---@param cb fun(target: whatsthis.Target?)
function M.from_cursor(buf, win, cb)
  local cursor = vim.api.nvim_win_get_cursor(win)
  local row, col = cursor[1] - 1, cursor[2]
  local function here()
    cb(target_from_declaration(source_from_buffer(buf), row, col))
  end

  local client = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/definition" })[1]
  if not client then
    return here()
  end

  local done = false
  local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
  local _, request_id = client:request("textDocument/definition", params, function(_, result)
    if done then
      return
    end
    done = true
    local loc = result and (result.uri and result or result[1])
    if not loc then
      return here()
    end
    local range = loc.targetSelectionRange or loc.range
    local path = vim.uri_to_fname(loc.targetUri or loc.uri)
    local on_itself = path == vim.api.nvim_buf_get_name(buf)
      and range.start.line == row
      and col >= range.start.character
      and col <= range["end"].character
    if on_itself then
      return here()
    end
    local source = source_from_path(path)
    local target = source and target_from_declaration(source, range.start.line, range.start.character)
    if not target then
      return here()
    end
    target.called_from = vim.trim(vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or "")
    cb(target)
  end, buf)

  -- While a language server is still loading its project, definitions can take minutes;
  -- explaining the code under the cursor right away beats waiting.
  vim.defer_fn(function()
    if not done then
      done = true
      if request_id then
        client:cancel_request(request_id)
      end
      here()
    end
  end, config.options.lsp_timeout_ms)
end

---@param target whatsthis.Target
---@return string
function M.prompt(target)
  local parts = { "What does this do?", "", "File: " .. target.location }
  if target.inside then
    table.insert(parts, ("Inside: `%s`"):format(target.inside))
  end
  if target.called_from then
    table.insert(parts, ("Called from: `%s`"):format(target.called_from))
  end
  vim.list_extend(parts, { "", "```", target.code, "```" })
  return table.concat(parts, "\n")
end

return M
