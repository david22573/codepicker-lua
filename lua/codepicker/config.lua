-- lua/codepicker/config.lua
local M = {}

M.defaults = {
	-- The binary name or full path to your Go tool
	cmd = "codepicker",

	-- The model to use on OpenRouter
	model = "xiaomi/mimo-v2-flash:free",

	-- Edit mode settings
	edit = {
		-- Automatically open diff view after generation?
		diff_view = true,
	},
}

-- Allow user to override config via setup()
M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
