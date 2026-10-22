local M = {}

function M.check()
  local config = require("whatsthis.config")
  local runner = require("whatsthis.runner")
  local health = vim.health

  health.start("whatsthis.nvim")

  if vim.fn.has("nvim-0.11") == 1 then
    health.ok("Neovim " .. tostring(vim.version()))
  else
    health.error("Neovim 0.11 or newer is required")
  end

  local argv, err = runner.argv()
  if not argv then
    health.error(err)
    return
  end
  local name = config.options.runner
  if vim.fn.executable(argv[1]) == 1 then
    health.ok(("runner %q: `%s` found at %s"):format(name, argv[1], vim.fn.exepath(argv[1])))
  else
    health.error(("runner %q: `%s` is not on your PATH"):format(name, argv[1]), {
      "Install it, or pick another runner with `setup({ runner = ... })`",
    })
  end
end

return M
