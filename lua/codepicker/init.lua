local M = {}
local config = require("codepicker.config")

-- REVIEW MODE KEYMAPS
-- 1. Normal Mode <C-Enter>: Accepts current block & formats
-- 2. Visual Mode <C-Enter>: Accepts ONLY selected lines & formats
local function set_review_keymaps(buf, diff_win, scratch_win)
	local opts = { noremap = true, silent = true, buffer = buf }

	-- NORMAL MODE: Accept Whole Block
	vim.keymap.set("n", "<C-CR>", function()
		vim.cmd("normal! do") -- Diff Obtain
		vim.cmd("update") -- Save
		vim.lsp.buf.format() -- Auto-Format via LSP
		print("✅ Block Accepted & Formatted.")
	end, opts)

	-- VISUAL MODE: Accept Partial Selection
	vim.keymap.set("v", "<C-CR>", function()
		-- Escape visual mode to set marks '< and '>
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

		vim.schedule(function()
			-- Apply diffget strictly to the selection
			vim.cmd("'<,'>diffget")
			vim.cmd("update")
			vim.lsp.buf.format()
			print("✅ Selection Accepted & Formatted.")
		end)
	end, opts)

	-- DECLINE: Close Review
	vim.keymap.set({ "n", "v" }, "<C-BS>", function()
		vim.cmd("diffoff")
		if vim.api.nvim_win_is_valid(scratch_win) then
			vim.api.nvim_win_close(scratch_win, true)
		end
		print("❌ Review Cancelled.")
	end, opts)

	print("REVIEW: <C-Enter> to Accept (Normal/Visual) | <C-Backspace> to Decline")
end

local function setup_diff_view(original_buf, new_buf)
	-- Setup Right Window (AI Proposal)
	local ai_wins = vim.fn.win_findbuf(new_buf)
	if #ai_wins > 0 then
		local win = ai_wins[1]
		vim.api.nvim_set_current_win(win)
		vim.cmd("diffthis")
	end

	-- Setup Left Window (Your Code)
	local orig_wins = vim.fn.win_findbuf(original_buf)
	if #orig_wins > 0 then
		local win = orig_wins[1]
		vim.api.nvim_set_current_win(win)
		vim.cmd("diffthis")

		-- Attach keymaps to YOUR buffer
		set_review_keymaps(original_buf, original_buf, ai_wins[1])
	end
end

-- Strip markdown code fences
local function clean_fences(line)
	if line:match("^```") then
		return nil
	end
	return line
end

-- CHAT MODE (Ask)
function M.ask(query, opts)
	opts = opts or {}
	local use_all_files = opts.all or false
	local current_file = vim.fn.expand("%:p")

	local cmd = { config.options.cmd, "ask", query, "--model", config.options.model }

	if not use_all_files and current_file ~= "" then
		table.insert(cmd, "--focus")
		table.insert(cmd, current_file)
		print("🔍 Scanning current file only...")
	else
		print("🌍 Scanning entire repo...")
	end

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

	vim.fn.jobstart(cmd, {
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

-- EDIT MODE (Refactor)
function M.refactor(instruction)
	local current_buf = vim.api.nvim_get_current_buf()
	local current_file = vim.fn.expand("%:p")
	local file_type = vim.bo.filetype

	if current_file == "" then
		print("❌ Save the file first!")
		return
	end

	local new_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(new_buf, "filetype", file_type)

	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, new_buf)

	-- Strict Prompt for Code Only
	local strict_prompt = string.format(
		"Refactor file: %s.\nINSTRUCTION: %s\n"
			.. "CRITICAL: Output ONLY valid code. No markdown. No text. Keep indentation clean.",
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

	local function append_raw(text)
		vim.schedule(function()
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

	vim.fn.jobstart(cmd, {
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
				setup_diff_view(current_buf, new_buf)
			end)
		end,
	})
end

return M
