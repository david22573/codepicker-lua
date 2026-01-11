if vim.g.loaded_codepicker then
	return
end
vim.g.loaded_codepicker = true

local codepicker = require("codepicker")
local config = require("codepicker.config")
local server = require("codepicker.server")
local log = require("codepicker.log")
local job = require("codepicker.job")

-- Initialize with defaults
config.setup()

-- Command: :CodePickerAsk "Query"
vim.api.nvim_create_user_command("CodePickerAsk", function(opts)
	local args = vim.trim(opts.args)

	if args == "" then
		vim.notify("❌ Please provide a query.", vim.log.levels.ERROR)
		return
	end

	local options = {
		overwrite = false,
	}

	-- Parse -y flag (overwrite context)
	if args:match("%-y") then
		options.overwrite = true
		args = args:gsub("%-y%s*", "")
		args = vim.trim(args)
	end

	codepicker.ask(args, options)
end, {
	nargs = "+",
	desc = "Ask AI about the codebase",
	complete = function(_, line)
		-- Simple completion suggestions
		local suggestions = {
			"explain this code",
			"how does this work",
			"find bugs in this file",
			"suggest improvements",
			"add documentation",
		}
		return suggestions
	end,
})

-- Command: :CodePickerEdit "Instructions"
vim.api.nvim_create_user_command("CodePickerEdit", function(opts)
	local args = vim.trim(opts.args)

	if args == "" then
		vim.notify("❌ Please provide refactoring instructions.", vim.log.levels.ERROR)
		return
	end

	codepicker.refactor(args)
end, {
	nargs = "+",
	desc = "Refactor current file with AI",
	complete = function(_, line)
		local suggestions = {
			"add error handling",
			"add comments",
			"optimize performance",
			"add type annotations",
			"simplify this code",
			"add unit tests",
		}
		return suggestions
	end,
})

-- Command: :CodePickerStatus - Check daemon status
vim.api.nvim_create_user_command("CodePickerStatus", function()
	if server.is_running() then
		local uptime = server.get_uptime()
		print(string.format("✅ Server running (uptime: %.1fs) at %s", uptime, server.url("/ask")))

		-- Run health check
		server.wait_ready(function(healthy)
			vim.schedule(function()
				if healthy then
					print("✅ Health check passed")
				else
					print("⚠️  Health check failed - server may not be responding")
				end
			end)
		end, 2000)
	else
		print("❌ Server not running. It will start automatically on first use.")
	end
end, {
	desc = "Check codepicker server status",
})

-- Command: :CodePickerRestart - Restart daemon
vim.api.nvim_create_user_command("CodePickerRestart", function()
	print("🔄 Restarting server...")
	server.stop()
	vim.defer_fn(function()
		if server.start() then
			print("✅ Server restarted successfully")
		else
			print("❌ Failed to restart server")
		end
	end, 500)
end, {
	desc = "Restart codepicker server",
})

-- Command: :CodePickerLogs - View logs
vim.api.nvim_create_user_command("CodePickerLogs", function()
	local log_path = log.get_log_path()

	if vim.fn.filereadable(log_path) == 0 then
		print("No logs found at: " .. log_path)
		return
	end

	vim.cmd("split " .. log_path)
	vim.bo.buftype = "nofile"
	vim.bo.bufhidden = "wipe"
	vim.bo.swapfile = false

	-- Auto-scroll to bottom
	vim.cmd("normal! G")
end, {
	desc = "View codepicker logs",
})

-- Command: :CodePickerClearLogs - Clear logs
vim.api.nvim_create_user_command("CodePickerClearLogs", function()
	log.clear()
	print("✅ Logs cleared")
end, {
	desc = "Clear codepicker logs",
})

-- Command: :CodePickerStop - Stop server
vim.api.nvim_create_user_command("CodePickerStop", function()
	if server.is_running() then
		server.stop()
		job.stop_all()
		print("🛑 Server stopped")
	else
		print("Server is not running")
	end
end, {
	desc = "Stop codepicker server",
})
