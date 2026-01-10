local M = {}

M.defaults = {
	cmd = "codepicker",
	model = "xiaomi/mimo-v2-flash:free",
	ui = {
		diff_view = true,
		wrap = true,
	},
	keymaps = {
		accept = "<C-CR>",
		decline = "<C-BS>",
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
