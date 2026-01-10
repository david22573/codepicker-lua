local M = {}
local config = require("codepicker.config")
local ui = require("codepicker.ui")
local job = require("codepicker.job")

-- Helper to strip markdown fences (e.g., ```lua, ```, etc.)
local function clean_markdown_fences(line)
	local cleaned = line:gsub("^```%w*", ""):gsub("^```", "")
	-- If the line was just a fence, return nil to skip it
	if cleaned == "" then
		return nil
	end
	return cleaned
end

-- Core function to run the CLI and stream to a buffer
local function stream_to_buffer(cmd, target_buf, on_finish, line_processor)
	local line_count = 0

	-- Start the job
	job.run(cmd, function(line)
		-- Process line (strip fences or keep as is)
		local content = line_processor and line_processor(line) or line

		if content then
			vim.schedule(function()
				-- Clear "Thinking..." on first real content
				if line_count == 0 then
					vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, {})
				end
				-- Append line efficiently
				vim.api.nvim_buf_set_lines(target_buf, -1, -1, false, { content })
				line_count = line_count + 1
			end)
		end
	end, on_finish)
end

function M.ask(query, opts)
	opts = opts or {}
	local use_all = opts.all or false
	local current_file = vim.fn.expand("%:p")

	-- Build Command
	local cmd = { config.options.cmd, "ask", query, "--model", config.options.model }
	if not use_all and current_file ~= "" then
		table.insert(cmd, "--focus")
		table.insert(cmd, current_file)
		print("🔍 Scanning active file...")
	else
		print("🌍 Scanning codebase...")
	end

	-- Setup UI
	local buf = ui.create_scratch_buf("markdown")
	ui.open_split(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Thinking..." })

	-- Run
	stream_to_buffer(cmd, buf, function()
		print("✅ Query complete.")
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

	-- Build Strict Prompt
	local strict_prompt = string.format(
		"Refactor file: %s.\nINSTRUCTION: %s\nCRITICAL: Output ONLY valid code. No markdown. No text.",
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

	-- Setup UI
	local new_buf = ui.create_scratch_buf(filetype)
	ui.open_split(new_buf)
	vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, { "Generating..." })

	-- Run with Fence Cleaning
	stream_to_buffer(cmd, new_buf, function()
		-- On finish, setup Diff View
		ui.setup_diff_view(current_buf, new_buf)
		print("✅ Review ready: " .. config.options.keymaps.accept .. " to accept.")
	end, clean_markdown_fences)
end

function M.setup(opts)
	config.setup(opts)
end

return M
