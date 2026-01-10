local M = {}

-- Stream Parser to handle partial chunks and strip CLI noise
local function create_stream_handler(on_line)
	local buffer = ""
	-- Known noise lines from the Go tool to ignore
	local ignore_patterns = {
		"^%s*🤖 AI Response:",
		"^%s*─+$", -- Matches the separator line "──────"
		"^%s*Context generated:", -- Optional status log from CLI
	}

	return function(data)
		if not data then
			return
		end

		-- Neovim sends a table of strings (chunks).
		-- The last item is usually partial, or empty if stream ended cleanly.
		for i, chunk in ipairs(data) do
			buffer = buffer .. chunk
			if i < #data then
				-- We have a newline, process the line
				local lines = vim.split(buffer, "\n")
				for j = 1, #lines - 1 do
					local line = lines[j]

					-- Check if line is "noise"
					local is_noise = false
					for _, pat in ipairs(ignore_patterns) do
						if line:match(pat) then
							is_noise = true
							break
						end
					end

					if not is_noise then
						on_line(line)
					end
				end
				-- The last part is the new partial buffer
				buffer = lines[#lines]
			end
		end
	end
end

function M.run(cmd, on_chunk, on_exit)
	local stdout_handler = create_stream_handler(on_chunk)

	local job_id = vim.fn.jobstart(cmd, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			stdout_handler(data)
		end,
		on_exit = function()
			if on_exit then
				on_exit()
			end
		end,
	})

	if job_id <= 0 then
		print("❌ Failed to start codepicker job")
	end
	return job_id
end

return M
