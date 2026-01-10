local M = {}
local config = require("codepicker.config")

-- HELPER: Check if binary exists
local function check_binary()
	if vim.fn.executable(config.options.cmd) == 0 then
		vim.notify("❌ codepicker binary not found in PATH: " .. config.options.cmd, vim.log.levels.ERROR)
		return false
	end
	return true
end

-- REVIEW MODE KEYMAPS
local function set_review_keymaps(buf, diff_win, scratch_win)
	local opts = { noremap = true, silent = true, buffer = buf }
	local maps = config.options.mappings

	-- NORMAL MODE: Accept Whole Block
	if maps.accept then
		vim.keymap.set("n", maps.accept, function()
			vim.cmd("normal! do") -- Diff Obtain
			vim.cmd("update") -- Save
			vim.lsp.buf.format() -- Auto-Format via LSP
			print("✅ Block Accepted & Formatted.")
		end, opts)
	end

	-- VISUAL MODE: Accept Partial Selection
	if maps.accept then
		vim.keymap.set("v", maps.accept, function()
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
	end

	-- DECLINE: Close Review
	if maps.decline then
		vim.keymap.set({ "n", "v" }, maps.decline, function()
			vim.cmd("diffoff")
			if vim.api.nvim_win_is_valid(scratch_win) then
				vim.api.nvim_win_close(scratch_win, true)
			end
			print("❌ Review Cancelled.")
		end, opts)
	end
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
		print(
			"REVIEW: "
				.. config.options.mappings.accept
				.. " to Accept | "
				.. config.options.mappings.decline
				.. " to Decline"
		)
	end
end

-- HELPER: Extract code block from Markdown response
local function extract_code(text)
	-- Try to match content inside triple backticks
	-- Match both ```lua and just ```
	local code = text:match("```[%w%s]*\n(.*)```")
	if code then
		return code
	end
	-- If no markdown blocks found, return stripped text or original
	-- This handles cases where models just output raw code without fences
	return text
end

-- CHAT MODE (Ask)
function M.ask(query, opts)
	if not check_binary() then
		return
	end
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

	-- Create Buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, "filetype", "markdown")
	vim.api.nvim_buf_set_option(buf, "buftype", "nofile") -- Scratch buffer
	vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe") -- Wipe on close
	vim.api.nvim_buf_set_option(buf, "swapfile", false)

	vim.cmd("vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_win_set_option(win, "wrap", true)

	local function append_text(text)
		vim.schedule(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				return
			end
			local last_line_idx = vim.api.nvim_buf_line_count(buf) - 1
			local last_line = vim.api.nvim_buf_get_lines(buf, last_line_idx, last_line_idx + 1, false)[1]

			local lines = vim.split(text, "\n")
			vim.api.nvim_buf_set_lines(buf, last_line_idx, -1, false, { last_line .. lines[1] })
			if #lines > 1 then
				vim.api.nvim_buf_set_lines(buf, -1, -1, false, { unpack(lines, 2) })
			end
			-- Auto-scroll
			vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(buf), 0 })
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
				if vim.api.nvim_buf_is_valid(buf) then
					append_text("\n\n✅ Done.")
				end
			end)
		end,
	})
end

-- EDIT MODE (Refactor)
function M.refactor(instruction)
	if not check_binary() then
		return
	end

	local current_buf = vim.api.nvim_get_current_buf()
	local current_file = vim.fn.expand("%:p")
	local file_type = vim.bo.filetype

	if current_file == "" then
		print("❌ Save the file first!")
		return
	end

	-- Prepare the scratch buffer for the result
	local new_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(new_buf, "filetype", file_type)
	vim.api.nvim_buf_set_option(new_buf, "buftype", "nofile")
	vim.api.nvim_buf_set_option(new_buf, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(new_buf, "swapfile", false)

	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, new_buf)

	-- Show loading state
	vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, { "-- 🤖 Generating code..." })

	local strict_prompt = string.format(
		"Refactor file: %s.\nINSTRUCTION: %s\n"
			.. "CRITICAL: Output ONLY valid code. Do not output markdown text unless inside comments.",
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

	-- ACCUMULATOR: Don't stream directly to buffer. Buffer to string first.
	local chunks = {}

	vim.fn.jobstart(cmd, {
		on_stdout = function(_, data)
			if data then
				for _, c in ipairs(data) do
					if c ~= "" then
						table.insert(chunks, c)
					end
				end
			end
		end,
		on_exit = function()
			vim.schedule(function()
				-- 1. Assemble full output
				local full_output = table.concat(chunks, "")

				-- 2. Extract code block (remove markdown fences)
				local clean_code = extract_code(full_output)

				-- 3. Split into lines
				local lines = vim.split(clean_code, "\n")

				-- 4. Replace buffer content
				if vim.api.nvim_buf_is_valid(new_buf) then
					vim.api.nvim_buf_set_lines(new_buf, 0, -1, false, lines)
					setup_diff_view(current_buf, new_buf)
				end
			end)
		end,
	})
end

return M
