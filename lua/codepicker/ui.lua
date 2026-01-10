local M = {}
local config = require("codepicker.config")

-- Helper: Create a scratch buffer with specific options
function M.create_scratch_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].filetype = filetype or "markdown"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	return buf
end

-- Helper: Open a vertical split and focus it
function M.open_split(buf)
	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, buf)
	if config.options.ui.wrap then
		vim.wo[0].wrap = true
	end
end

-- Setup the Diff View (Reference vs Generated)
function M.setup_diff_view(original_buf, generated_buf)
	-- Find windows for both buffers
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
		M.set_review_keymaps(original_buf, orig_win, generated_buf)
	end
end

-- Keymaps for Accepting/Declining Code
function M.set_review_keymaps(buf, win, scratch_buf)
	local opts = { noremap = true, silent = true, buffer = buf }
	local keys = config.options.keymaps

	-- Accept (Normal Mode)
	vim.keymap.set("n", keys.accept, function()
		vim.cmd("normal! do") -- Diff Obtain
		vim.cmd("update")
		vim.lsp.buf.format()
		print("✅ Code Accepted.")
	end, opts)

	-- Accept (Visual Mode)
	vim.keymap.set("v", keys.accept, function()
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
		vim.schedule(function()
			vim.cmd("'<,'>diffget")
			vim.cmd("update")
			vim.lsp.buf.format()
			print("✅ Selection Accepted.")
		end)
	end, opts)

	-- Decline
	vim.keymap.set({ "n", "v" }, keys.decline, function()
		vim.cmd("diffoff")
		if vim.api.nvim_buf_is_valid(scratch_buf) then
			vim.api.nvim_buf_delete(scratch_buf, { force = true })
		end
		print("❌ Review Cancelled.")
	end, opts)
end

return M
