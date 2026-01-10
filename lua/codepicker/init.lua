local M = {}
local config = require("codepicker.config")
local ui = require("codepicker.ui")
local job = require("codepicker.job")

-- Utility to clean markdown fences for Refactor mode
local function clean_line(line)
	-- Remove ```go, ```lua, or just ```
	local cleaned = line:gsub("^```%w*", ""):gsub("^```", "")
	if cleaned == "" and line ~= "" then
		return nil
	end -- Skip the fence lines entirely
	return line
end

function M.ask(query, opts)
	opts = opts or {}
	local use_all = opts.all or false
	local current_file = vim.fn.expand("%:p")

	-- 1. Build Command
	local cmd = { config.options.cmd, "ask", query, "--model", config.options.model }

	if not use_all and current_file ~= "" then
		table.insert(cmd, "--focus")
		table.insert(cmd, current_file)
		print("🔍 Asking about active file...")
	else
		print("🌍 Asking about codebase...")
	end

	-- 2. Setup UI
	local buf = ui.create_scratch_buf("markdown")
	ui.open_split(buf)

	-- Write initial loading state
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Thinking..." })

	-- 3. Run Job
	local line_count = 0
	job.run(cmd, function(line)
		-- On first valid line, clear "Thinking..."
		if line_count == 0 then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
		end

		-- Append line safely
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { line })
		line_count = line_count + 1
	end, function()
		print("✅ Done.")
	end)
end

function M.refactor(instruction)
	local current_buf = vim.api.nvim_get_current_buf()
	local current_file = vim.fn.expand("%:p")
	local filetype = vim.bo[current_buf].filetype

	if current_file == "" then
		print("❌ Save the file first!")
		return
	end

	-- 1. Build Command
	local strict_prompt = string.format(
		"Refactor file: %s.\nINSTRUCTION: %s\nCRITICAL: Output ONLY valid code. No markdown fences. No conversational text.",
		current_file,
		instruction
	)

	local cmd = {
		config.options.cmd,
		"ask",
		strict_prompt,
		"--model",
		config.options.model,
		"--focus",
		current_file,
	}

	-- 2. Setup UI
	local new_buf = ui.create_scratch_buf(filetype)
	ui.open_split(new_buf)
	vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, { "Generating code..." })

	-- 3. Run Job
	local line_count = 0
	job.run(cmd, function(line)
		local cleaned = clean_line(line)
		if cleaned then
			if line_count == 0 then
				vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, {})
			end
			vim.api.nvim_buf_set_lines(new_buf, -1, -1, false, { cleaned })
			line_count = line_count + 1
		end
	end, function()
		-- 4. Enable Diff View on finish
		ui.setup_diff_view(current_buf, new_buf)
		print("✅ Review changes: <C-Enter> to accept.")
	end)
end

function M.setup(opts)
	config.setup(opts)
end

return M
