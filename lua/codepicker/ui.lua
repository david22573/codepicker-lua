local M = {}
local config = require("codepicker.config")

-- Create a scratch buffer with specific options
function M.create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	if not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	vim.bo[buf].filetype = filetype or "markdown"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buftype = "nofile"

	return buf
end

-- Open a vertical split and focus it
function M.open_split(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	vim.cmd("vsplit")
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, buf)

	if config.options.ui.wrap then
		vim.wo[win].wrap = true
	end

	return win
end

-- Create a floating window at cursor position
function M.create_float_at_cursor(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	local width = math.min(vim.o.columns - 4, 80)
	local height = math.min(vim.o.lines - 4, 20)

	-- Calculate position relative to cursor
	-- We'll try to position it below the cursor, but flip up if near bottom
	local opts = {
		relative = "cursor",
		row = 1,
		col = 0,
		width = width,
		height = height,
		style = "minimal",
		border = "rounded",
		title = " ≡ƒñû CodePicker Ghost ",
		title_pos = "center",
	}

	local win = vim.api.nvim_open_win(buf, true, opts)

	-- Set some window options for code readability
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].conceallevel = 2 -- Hide markdown syntax if possible
	vim.wo[win].foldenable = false

	return win
end

-- Show progress indicator
function M.show_progress(buf, message)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return nil
	end

	local frames = config.options.ui.progress_frames
	local idx = 1
	local timer = vim.loop.new_timer()

	timer:start(
		0,
		100,
		vim.schedule_wrap(function()
			if not vim.api.nvim_buf_is_valid(buf) then
				timer:stop()
				timer:close()
				return
			end

			local line = frames[idx] .. " " .. message
			pcall(vim.api.nvim_buf_set_lines, buf, 0, 1, false, { line })
			idx = (idx % #frames) + 1
		end)
	)

	return timer
end

-- Append text to buffer (handles multiline)
function M.append_text(buf, text)
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		return false
	end

	vim.schedule(function()
		if not vim.api.nvim_buf_is_valid(buf) then
			return
		end

		local last_line_idx = vim.api.nvim_buf_line_count(buf) - 1
		local last_line = vim.api.nvim_buf_get_lines(buf, last_line_idx, last_line_idx + 1, false)[1]
		local lines = vim.split(text, "\n")

		-- Append to last line
		vim.api.nvim_buf_set_lines(buf, last_line_idx, -1, false, { last_line .. lines[1] })

		-- Add remaining lines
		if #lines > 1 then
			vim.api.nvim_buf_set_lines(buf, -1, -1, false, { unpack(lines, 2) })
		end

		-- Auto-scroll to bottom
		local wins = vim.fn.win_findbuf(buf)
		if #wins > 0 then
			local win = wins[1]
			pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(buf), 0 })
		end
	end)

	return true
end

-- Setup the Diff View (Reference vs Generated)
function M.setup_diff_view(original_buf, generated_buf)
	if not vim.api.nvim_buf_is_valid(original_buf) or not vim.api.nvim_buf_is_valid(generated_buf) then
		return false
	end

	local gen_win = vim.fn.bufwinid(generated_buf)
	local orig_win = vim.fn.bufwinid(original_buf)

	if gen_win ~= -1 then
		vim.api.nvim_win_call(gen_win, function()
			vim.cmd("diffthis")
		end)
	end

	if orig_win ~= -1 then
		vim.api.nvim_win_call(orig_win, function()
			vim.cmd("diffthis")
		end)
		M.set_review_keymaps(original_buf, generated_buf)
	end

	return true
end

-- Keymaps for Accepting/Declining Code
function M.set_review_keymaps(original_buf, scratch_buf)
	if not vim.api.nvim_buf_is_valid(original_buf) or not vim.api.nvim_buf_is_valid(scratch_buf) then
		return
	end

	local opts = { noremap = true, silent = true, buffer = original_buf }
	local keys = config.options.mappings

	-- Accept (Normal Mode) - use diffget
	vim.keymap.set("n", keys.accept, function()
		vim.cmd("normal! do") -- Diff Obtain
		vim.cmd("update")
		-- Format if LSP is available
		if #vim.lsp.get_active_clients({ bufnr = 0 }) > 0 then
			vim.lsp.buf.format({ async = false })
		end
		print("✅ Code Accepted.")
	end, opts)

	-- Accept (Visual Mode)
	vim.keymap.set("v", keys.accept, function()
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
		vim.schedule(function()
			vim.cmd("'<,'>diffget")
			vim.cmd("update")
			if #vim.lsp.get_active_clients({ bufnr = 0 }) > 0 then
				vim.lsp.buf.format({ async = false })
			end
			print("✅ Selection Accepted.")
		end)
	end, opts)

	-- Decline
	vim.keymap.set({ "n", "v" }, keys.decline, function()
		vim.cmd("diffoff!")
		if vim.api.nvim_buf_is_valid(scratch_buf) then
			vim.api.nvim_buf_delete(scratch_buf, { force = true })
		end
		print("❌ Review Cancelled.")
	end, opts)

	-- Print helper message
	vim.schedule(function()
		print(string.format("Review Mode: %s to Accept | %s to Decline", keys.accept or "N/A", keys.decline or "N/A"))
	end)
end

return M
