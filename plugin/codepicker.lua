if vim.g.loaded_codepicker then
	return
end
vim.g.loaded_codepicker = 1

local codepicker = require("codepicker")

-- Command: :CodePickerAsk "Query" (Focus Current File)
-- Command: :CodePickerAsk --all "Query" (Whole Repo)
vim.api.nvim_create_user_command("CodePickerAsk", function(opts)
	local args = opts.args
	local options = { all = false }

	if args:match("^%-%-all") then
		options.all = true
		args = args:gsub("^%-%-all%s*", "")
	end

	if args == "" then
		print("❌ Please provide a query.")
		return
	end
	codepicker.ask(args, options)
end, { nargs = "+" })

-- Edit is always focused on current file
vim.api.nvim_create_user_command("CodePickerEdit", function(opts)
	if opts.args == "" then
		print("❌ Please provide instructions.")
		return
	end
	codepicker.refactor(opts.args)
end, { nargs = "+" })
