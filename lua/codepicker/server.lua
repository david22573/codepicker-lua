-- lua/codepicker/server.lua
local M = {}
local config = require("codepicker.config")
local log = require("codepicker.log")
local job_id = nil
local start_time = nil
function M.start()
	if job_id then
		log.debug("Server already running")
		return true
	end
	-- Check if binary exists
	if vim.fn.executable(config.options.cmd) == 0 then
		log.error("codepicker binary not found: " .. config.options.cmd)
		return false
	end
	local cmd = { config.options.cmd, "serve", "--port", tostring(config.options.port) }
	job_id = vim.fn.jobstart(cmd, {
		detach = false,
		on_stdout = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					log.debug("Server: " .. line)
				end
			end
		end,
		on_stderr = function(_, data)
			for _, line in ipairs(data) do
				if line ~= "" then
					-- FIX: Log as INFO/WARN so you can see startup errors even if debug=false
					log.warn("Server stderr: " .. line)
				end
			end
		end,
		on_exit = function(_, code, _)
			local was_running = job_id ~= nil
			job_id = nil
			start_time = nil
			if was_running then
				if code == 0 or code == 143 then -- 143 = SIGTERM
					log.info("Server stopped gracefully")
				else
					log.error("Server exited with code: " .. code)
				end
			end
		end,
	})
	if job_id > 0 then
		start_time = vim.loop.now()
		log.info("Started codepicker server on port " .. config.options.port)
		return true
	else
		log.error("Failed to start codepicker server")
		job_id = nil
		start_time = nil
		return false
	end
end
function M.stop()
	if job_id then
		vim.fn.jobstop(job_id)
		job_id = nil
		start_time = nil
		log.info("Stopped codepicker server")
	end
end
function M.is_running()
	return job_id ~= nil
end
function M.get_uptime()
	if not start_time then
		return 0
	end
	return (vim.loop.now() - start_time) / 1000
end
function M.url(path)
	-- FIX: Use 127.0.0.1 instead of localhost to avoid IPv6 resolution timeouts
	return string.format("http://127.0.0.1:%d%s", config.options.port, path)
end
function M.wait_ready(cb, timeout)
	timeout = timeout or config.options.timeout.server_start
	local start = vim.loop.now()
	local attempts = 0
	local max_attempts = math.floor(timeout / 200)
	local done = false
	local function poll()
		if done then
			return
		end
		-- Check if we've timed out
		local elapsed = vim.loop.now() - start
		if elapsed > timeout then
			done = true
			log.error("Server readiness check timed out after " .. elapsed .. "ms")
			cb(false)
			return
		end
		attempts = attempts + 1
		log.debug("Server health check attempt " .. attempts)
		local check_job = vim.fn.jobstart({
			"curl",
			"-s",
			"-o",
			"/dev/null",
			"-w",
			"%{http_code}",
			"--max-time",
			"2",
			M.url("/health"),
		}, {
			on_stdout = function(_, data)
				if done then
					return
				end
				local code = table.concat(data, "")
				log.debug("Health check response: " .. code)
				-- Accept 2xx or 404 (server is up, endpoint may not exist)
				if code:match("^[24]%d%d$") then
					done = true
					log.info("Server is ready")
					cb(true)
				end
			end,
			on_exit = function(_, exit_code)
				if done then
					return
				end
				if exit_code == 0 then
					-- stdout handler will process the response
					return
				end
				-- Connection failed, retry
				if attempts < max_attempts then
					vim.defer_fn(poll, 200)
				else
					done = true
					log.error("Server failed to become ready after " .. attempts .. " attempts")
					cb(false)
				end
			end,
		})
		if check_job <= 0 then
			done = true
			log.error("Failed to start health check job")
			cb(false)
		end
	end
	poll()
end
return M
