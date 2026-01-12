local M = {}

-- Active jobs registry for cleanup
local active_jobs = {}

-- Lazy load log to avoid circular dependency
local function get_log()
	return require("codepicker.log")
end

function M.run(cmd, on_line, on_exit)
	local buffer = "" -- Holds partial line from previous chunk

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, data)
			if not data then
				return
			end

			-- Neovim sends data as {"line1", "line2", "partial_line"}
			-- We append the previous partial buffer to the first new chunk
			if #data > 0 then
				data[1] = buffer .. data[1]
			end

			-- The last element is always a partial line (or empty string if line ended perfectly)
			-- We save it for the next event
			if #data > 0 then
				buffer = table.remove(data, #data)
			end

			-- Everything remaining in 'data' is a complete line
			for _, line in ipairs(data) do
				on_line(line)
			end
		end,
		on_stderr = function(_, data)
			if not data then
				return
			end
			for _, chunk in ipairs(data) do
				-- FIX: Use debug log to prevent UI blocking ("Press ENTER")
				if chunk ~= "" and vim.trim(chunk) ~= "" then
					get_log().debug("CLI: " .. chunk)
				end
			end
		end,
		on_exit = function(id, code)
			-- Flush any remaining buffer as a final line
			if buffer ~= "" then
				on_line(buffer)
			end

			active_jobs[id] = nil
			if code ~= 0 then
				get_log().debug("Job exited with code: " .. code)
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
	return job_id
end

function M.stop(job_id)
	if job_id and active_jobs[job_id] then
		vim.fn.jobstop(job_id)
		active_jobs[job_id] = nil
	end
end

function M.stop_all()
	for job_id, _ in pairs(active_jobs) do
		vim.fn.jobstop(job_id)
	end
	active_jobs = {}
end

return M
