-- lua/codepicker/init.lua
local M = {}
local config = require("codepicker.config")

-- Helper: Set up the Diff Window
local function setup_diff_view(original_buf, new_buf)
	-- 1. Move to the new buffer window (generated code)
	local win_ids = vim.fn.win_findbuf(new_buf)
	if #win_ids > 0 then
		vim.api.nvim_set_current_win(win_ids[1])
	end
	vim.cmd("diffthis") -- Enable diff mode

	-- 2. Jump back to original window and enable diff
	local orig_wins = vim.fn.win_findbuf(original_buf)
	if #orig_wins > 0 then
		vim.api.nvim_set_current_win(orig_wins[1])
		vim.cmd("diffthis")
	end
end

-- Helper: Strip markdown code fences (```go, ```, etc)
local function clean_fences(line)
	if line:match("^```") then
		return nil
	end
	return line
end

-- 1. CHAT MODE (:CodePickerAsk)
function M.ask(query)
	-- Create scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_win_set_option(0, "wrap", true)

	local function append_text(text)
		vim.schedule(function()
			local last_line_idx = vim.api.nvim_buf_line_count(buf) - 1
			local last_line = vim.api.nvim_buf_get_lines(buf, last_line_idx, last_line_idx + 1, false)[1]
			local lines = vim.split(text, "\n")

			vim.api.nvim_buf_set_lines(buf, last_line_idx, -1, false, { last_line .. lines[1] })
			if #lines > 1 then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { unpack(lines, 2) })
			end
		end)
	end

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "🤖 Agent is thinking...", "---" })

	-- Run codepicker binary
	vim.fn.jobstart({
		config.options.cmd,
		"ask",
		query,
		"--model",
		config.options.model,
	}, {
		on_stdout = function(_, data)
			if data then
				for _, c in ipairs(data) do
					if c ~= "" then
						append_text(c)
					end
				end
			end
		end,
		on_exit = function()
			vim.schedule(function()
				append_text("\n\n✅ Done.")
			end)
		end,
	})
end

-- 2. EDIT MODE (:CodePickerEdit)
function M.refactor(instruction)
	local current_buf = vim.api.nvim_get_current_buf()
	local current_file = vim.fn.expand("%:p") -- Full path
	local file_type = vim.bo.filetype

	if current_file == "" then
		print("❌ Please save the file first!")
		return
	end

	-- Create "Proposed Change" buffer
	local new_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(new_buf, "filetype", file_type)

	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, new_buf)

	-- Prompt Engineering to force raw code
	local strict_prompt = string.format(
		"Refactor request for file: %s.\n\nINSTRUCTION: %s\n\n"
			.. "CRITICAL RULE: Output ONLY the valid code for this entire file. "
			.. "Do NOT use markdown formatting. Do NOT add explanations. Just the code.",
		current_file,
		instruction
	)

	local function append_raw(text)
		vim.schedule(function()
			-- Strip code fences on the fly if the AI disobeys
			local clean_text = clean_fences(text)
			if not clean_text then
				return
			end

			local last_line_idx = vim.api.nvim_buf_line_count(new_buf) - 1
			local last_line = vim.api.nvim_buf_get_lines(new_buf, last_line_idx, last_line_idx + 1, false)[1]
			local lines = vim.split(clean_text, "\n")

			vim.api.nvim_buf_set_lines(new_buf, last_line_idx, -1, false, { last_line .. lines[1] })
			if #lines > 1 then
				vim.api.nvim_buf_set_lines(new_buf, -1, -1, false, { unpack(lines, 2) })
			end
		end)
	end

	vim.fn.jobstart({
		config.options.cmd,
		"ask",
		strict_prompt,
		"--model",
		config.options.model,
	}, {
		on_stdout = function(_, data)
			if data then
				for _, c in ipairs(data) do
					if c ~= "" then
						append_raw(c)
					end
				end
			end
		end,
		on_exit = function()
			vim.schedule(function()
				if config.options.edit.diff_view then
					setup_diff_view(current_buf, new_buf)
					print("✨ Refactor ready. Use 'do' (Diff Obtain) to accept changes.")
				else
					print("✨ Refactor complete.")
				end
			end)
		end,
	})
end

return M
