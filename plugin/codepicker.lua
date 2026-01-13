if vim.g.loaded_codepicker then
	return
end
vim.g.loaded_codepicker = true

local codepicker = require("codepicker")
local config = require("codepicker.config")
local server = require("codepicker.server")
local log = require("codepicker.log")
local job = require("codepicker.job")
local ghost = require("codepicker.ghost")

config.setup()

vim.api.nvim_create_user_command("CodePickerAsk", function(opts)
	local args = vim.trim(opts.args)
	if args == "" then
		vim.notify("❌ Please provide a query", vim.log.levels.ERROR)
		return
	end
	codepicker.ask(args, {})
end, { nargs = "+" })

vim.api.nvim_create_user_command("CodePickerEdit", function(opts)
	local args = vim.trim(opts.args)
	if args == "" then
		vim.notify("❌ Please provide instructions", vim.log.levels.ERROR)
		return
	end
	codepicker.refactor(args, { visual = opts.range > 0 })
end, { nargs = "+", range = true })

vim.api.nvim_create_user_command("CodePickerGhost", function(opts)
	local args = vim.trim(opts.args)
	if args == "" then
		vim.notify("❌ Please provide a query", vim.log.levels.ERROR)
		return
	end
	ghost.write(args)
end, { nargs = "+" })

vim.api.nvim_create_user_command("CodePickerStatus", function()
	if server.is_running() then
		print("✅ Server running")
	else
		print("❌ Server not running")
	end
end, {})

vim.api.nvim_create_user_command("CodePickerStop", function()
	server.stop()
	job.stop_all()
	print("🛑 Server stopped")
end, {})
