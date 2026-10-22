if vim.g.loaded_whatsthis then
  return
end
vim.g.loaded_whatsthis = true

vim.api.nvim_create_user_command("WhatsThis", function(args)
  require("whatsthis").explain(args.range > 0 and { range = { args.line1, args.line2 } } or nil)
end, { range = true, desc = "Explain the code under the cursor with AI" })

vim.keymap.set({ "n", "x" }, "<Plug>(WhatsThis)", function()
  require("whatsthis").explain()
end, { desc = "Explain the code under the cursor with AI" })
