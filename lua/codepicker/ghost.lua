local M = {}
local config = require("codepicker.config")
local ui = require("codepicker.ui")
local job = require("codepicker.job")
local log = require("codepicker.log")

function M.write(query)
	-- 1. Prepare the UI
	local buf = ui.create_scratch_buf("markdown")
	local win = ui.create_float_at_cursor(buf)

	if not buf or not win then
		log.error("Failed to create Ghost Writer UI")
		return
	end

	-- 2. Construct CLI Command
	-- We use the CLI directly to get the "Smart Mode" features
	local cmd = {
		config.options.cmd, -- "codepicker"
		"ask",
		query,
		"--raw", -- Stream raw text (no headers)
		"--smart", -- Use the Planner
	}

	-- Optional: Add focus if a file is open
	local current_file = vim.fn.expand("%:p")
	if current_file ~= "" then
		table.insert(cmd, "--focus")
		table.insert(cmd, current_file)
	end

	ui.append_text(buf, "≡ƒºá Thinking...\n\n")

	-- 3. Run the Job
	local captured_output = {}

	job.run(cmd, function(line)
		-- Stream to buffer
		ui.append_text(buf, line .. "\n")
		table.insert(captured_output, line)
	end, function(code)
		if code == 0 then
			-- On Success: Map keys to Apply or Close
			M.set_ghost_keymaps(buf, win, table.concat(captured_output, "\n"))
			ui.append_text(buf, "\n\n---\n[Ctrl+Enter] Apply  [Esc] Discard")
		else
			ui.append_text(buf, "\n❌ Failed (Exit Code: " .. code .. ")")
		end
	end)
end

function M.set_ghost_keymaps(buf, win, content)
	local opts = { noremap = true, silent = true, buffer = buf }

	-- CLOSE / DECLINE
	vim.keymap.set("n", "<Esc>", function()
		vim.api.nvim_win_close(win, true)
	end, opts)

	-- APPLY (Insert at cursor position in ORIGINAL window)
	vim.keymap.set("n", "<C-CR>", function()
		-- 1. Close float
		vim.api.nvim_win_close(win, true)

		-- 2. Strip Markdown (Simple version)
		local clean_code = content
		if content:match("^```") then
			-- Remove first and last lines if they look like code fences
			local lines = vim.split(content, "\n")
			if #lines >= 2 then
				table.remove(lines, 1) -- Remove ```go
				-- Remove trailing backticks if present
				if lines[#lines]:match("^```") then
					table.remove(lines, #lines)
				end
				clean_code = table.concat(lines, "\n")
			end
		end

		-- 3. Insert into main buffer
		local lines = vim.split(clean_code, "\n")
		local row, _ = unpack(vim.api.nvim_win_get_cursor(0))
		vim.api.nvim_buf_set_lines(0, row, row, false, lines)

		print("≡ƒôï Code Applied!")
	end, opts)
end

return M

