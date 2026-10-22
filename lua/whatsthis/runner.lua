local config = require("whatsthis.config")

local M = {}

---@return string[]? argv
---@return string? err
function M.argv()
  local opts = config.options
  local runner = opts.runners[opts.runner]
  if not runner or type(runner.build) ~= "function" then
    return nil, ("unknown runner %q"):format(tostring(opts.runner))
  end
  return runner.build(opts.system_prompt, runner)
end

---@param prompt string
---@param on_done fun(ok: boolean, text: string)
---@return vim.SystemObj?
function M.run(prompt, on_done)
  local argv, err = M.argv()
  if not argv then
    on_done(false, err)
    return nil
  end
  local ok, proc = pcall(vim.system, argv, {
    stdin = prompt,
    text = true,
    -- Outside any project, so the CLI does not pick up project instruction files.
    cwd = vim.fn.stdpath("cache"),
  }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        on_done(true, res.stdout or "")
      elseif res.signal ~= 0 then
        -- killed because the popup closed; nobody is waiting for the answer
        return
      else
        on_done(false, vim.trim((res.stderr ~= "" and res.stderr or res.stdout) or ""))
      end
    end)
  end)
  if not ok then
    on_done(false, ("could not start `%s`: %s"):format(argv[1], proc))
    return nil
  end
  return proc
end

return M
