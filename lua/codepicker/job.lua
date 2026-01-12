local M = {}
-- Active jobs registry for cleanup
local active_jobs = {}
-- Lazy load log to avoid circular dependency
local function get_log()
	return require("codepicker.log")
end
function M.run(cmd, on_line, on_exit)
	local buffer = ""
	-- We don't need to rely on the return variable for the callback anymore
	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data)
			if not data then
				return
			end
			-- Concatenate all chunks
			for _, chunk in ipairs(data) do
				if chunk ~= "" then
					buffer = buffer .. chunk
				end
			end
			-- Process complete lines only
			while buffer:find("\n") do
				local idx = buffer:find("\n")
				local line = buffer:sub(1, idx - 1)
				buffer = buffer:sub(idx + 1)

				-- FIX: Pass all lines through.
				-- Logic for filtering fences/empty lines belongs in the consumer (init.lua), not here.
				on_line(line)
			end
		end,
on_stderr = function(_, data)
			if not data then
				return
			end
			for _, chunk in ipairs(data) do
				-- FIX: Check for empty strings and use debug() instead of error()
				if chunk ~= "" and vim.trim(chunk) ~= "" then
					-- Using debug() writes to the log file but DOES NOT trigger a notification
					-- This prevents the "Press ENTER" wall of text
					get_log().debug("CLI progress: " .. chunk)
				end
			end
		end,
		on_exit = function(id, code)
			-- Flush remaining buffer
			if buffer ~= "" then
				on_line(buffer)
			end
			-- Cleanup: Use 'id' instead of 'job_id'
			active_jobs[id] = nil
			if code ~= 0 then
				get_log().error("Job exited with code: " .. code)
			else
				get_log().debug("Job completed successfully")
			end
			if on_exit then
				on_exit(code)
			end
		end,
	})
	if job_id <= 0 then
		get_log().error("Failed to start job")
		return nil
	end
	active_jobs[job_id] = true
	get_log().debug("Started job: " .. job_id)
	return job_id
end
function M.stop(job_id)
	if job_id and active_jobs[job_id] then
		vim.fn.jobstop(job_id)
		active_jobs[job_id] = nil
		get_log().debug("Stopped job: " .. job_id)
	end
end
function M.stop_all()
	for job_id, _ in pairs(active_jobs) do
		vim.fn.jobstop(job_id)
	end
	active_jobs = {}
	get_log().debug("Stopped all jobs")
end
return M
