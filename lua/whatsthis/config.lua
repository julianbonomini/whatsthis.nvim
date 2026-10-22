local M = {}

---@class whatsthis.Runner
---@field build fun(system_prompt: string, runner: whatsthis.Runner): string[] argv; the prompt is sent on stdin
---@field model? string

---@class whatsthis.Config
---@field runner string key into `runners`
---@field runners table<string, whatsthis.Runner>
---@field system_prompt string
---@field max_lines integer longest code block sent to the model
---@field lsp_timeout_ms integer how long to wait for go-to-definition before explaining the code under the cursor instead
---@field window { border: string|string[], max_width: integer, max_height: number }
M.defaults = {
  runner = "pi",
  runners = {
    pi = {
      model = "anthropic/claude-haiku-5-5",
      build = function(system_prompt, runner)
        return {
          "pi", "-p",
          "--model", runner.model,
          "--thinking", "off",
          -- Everything pi would otherwise load at startup adds latency to a one-off question.
          "--no-tools", "--no-context-files", "--no-extensions", "--no-skills",
          "--no-prompt-templates", "--no-themes", "--no-session", "--offline", "--no-approve",
          "--system-prompt", system_prompt,
        }
      end,
    },
    claude = {
      model = "haiku",
      build = function(system_prompt, runner)
        return {
          "claude", "-p",
          "--model", runner.model,
          -- Replacing Claude Code's default system prompt, tools and settings roughly halves latency.
          "--tools", "",
          "--strict-mcp-config",
          "--setting-sources", "",
          "--no-session-persistence",
          "--system-prompt", system_prompt,
        }
      end,
    },
  },
  system_prompt = table.concat({
    "You explain code to a senior engineer who is reading it in their editor.",
    "Reply in markdown: one sentence saying what it does, then at most 4 short bullets",
    "covering inputs, output and side effects (DB, network, async, mutation). Under 80 words.",
    "No preamble, no restating the code, no suggestions.",
  }, " "),
  max_lines = 300,
  lsp_timeout_ms = 1500,
  window = {
    border = "rounded",
    max_width = 100,
    -- fraction of the editor height
    max_height = 0.5,
  },
}

---@type whatsthis.Config
M.options = vim.deepcopy(M.defaults)

---@param opts? table
function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
end

return M
