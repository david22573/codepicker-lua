-- plugin/codepicker.lua
if vim.g.loaded_codepicker then
	return
end
vim.g.loaded_codepicker = 1

local codepicker = require("codepicker")

-- Command: :CodePickerAsk "How does this work?"
vim.api.nvim_create_user_command("CodePickerAsk", function(opts)
	if opts.args == "" then
		print("❌ Please provide a query.")
		return
	end
	codepicker.ask(opts.args)
end, { nargs = "+" })

-- Command: :CodePickerEdit "Rename variable X to Y"
vim.api.nvim_create_user_command("CodePickerEdit", function(opts)
	if opts.args == "" then
		print("❌ Please provide instructions.")
		return
	end
	codepicker.refactor(opts.args)
end, { nargs = "+" })
