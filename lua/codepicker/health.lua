local M = {}

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error
local info = health.info or health.report_info

function M.check()
	start("CodePicker")

	-- Check if codepicker binary exists
	local config = require("codepicker.config")
	local cmd = config.options.cmd

	if vim.fn.executable(cmd) == 1 then
		ok("codepicker binary found: " .. cmd)

		-- Try to get version
		local version_output = vim.fn.system(cmd .. " --version 2>&1")
		if vim.v.shell_error == 0 then
			info("Version: " .. vim.trim(version_output))
		end
	else
		error("codepicker binary not found: " .. cmd)
		info("Install from: https://github.com/your-repo/codepicker")
	end

	-- Check if curl is available
	if vim.fn.executable("curl") == 1 then
		ok("curl found")
	else
		error("curl not found - required for HTTP requests")
	end

	-- Check server status
	local server = require("codepicker.server")
	if server.is_running() then
		ok("Server is running")
		info("Uptime: " .. string.format("%.1fs", server.get_uptime()))
		info("URL: " .. server.url("/ask"))

		-- Try health check
		server.wait_ready(function(healthy)
			vim.schedule(function()
				if healthy then
					ok("Server health check passed")
				else
					warn("Server health check failed")
				end
			end)
		end, 2000)
	else
		info("Server is not running (will auto-start on first use)")
	end

	-- Check configuration
	start("Configuration")

	local port = config.options.port
	if port >= 1024 and port <= 65535 then
		ok("Port: " .. port)
	else
		warn("Port out of recommended range: " .. port)
	end

	if config.options.model then
		info("Model: " .. config.options.model)
	else
		info("Model: using server default")
	end

	-- Check keymappings
	start("Keymappings")
	info("Accept: " .. config.options.mappings.accept)
	info("Decline: " .. config.options.mappings.decline)

	-- Check log file
	start("Logging")
	local log = require("codepicker.log")
	local log_path = log.get_log_path()

	if vim.fn.filereadable(log_path) == 1 then
		local size = vim.fn.getfsize(log_path)
		ok("Log file exists: " .. log_path)
		info("Size: " .. size .. " bytes")

		if size > 1024 * 1024 then
			warn("Log file is large (>1MB). Consider running :CodePickerClearLogs")
		end
	else
		info("No log file yet: " .. log_path)
	end

	-- Check dependencies
	start("Dependencies")

	-- Check Neovim version
	local nvim_version = vim.version()
	if nvim_version.minor >= 8 then
		ok("Neovim version: " .. vim.version().major .. "." .. vim.version().minor)
	else
		warn("Neovim 0.8+ recommended, you have: " .. vim.version().major .. "." .. vim.version().minor)
	end
end

return M
