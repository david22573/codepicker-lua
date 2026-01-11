local M = {}

M.defaults = {
	cmd = "codepicker",
	model = nil,
	port = 22573,
	timeout = {
		server_start = 5000, -- ms to wait for server
		request = 30000, -- ms to wait for response
	},
	mappings = {
		accept = "<C-CR>",
		decline = "<C-BS>",
	},
	debug = false,
	ui = {
		wrap = true,
		progress_frames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" },
	},
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
	opts = opts or {}

	-- Validate port
	if opts.port and (opts.port < 1024 or opts.port > 65535) then
		vim.notify("Invalid port number, using default: " .. M.defaults.port, vim.log.levels.WARN)
		opts.port = nil
	end

	-- Validate mappings
	if opts.mappings then
		for k, v in pairs(opts.mappings) do
			if type(v) ~= "string" then
				vim.notify("Invalid mapping for " .. k .. ", using default", vim.log.levels.WARN)
				opts.mappings[k] = nil
			end
		end
	end

	-- Validate timeout values
	if opts.timeout then
		if opts.timeout.server_start and opts.timeout.server_start < 100 then
			vim.notify("server_start timeout too low, using default", vim.log.levels.WARN)
			opts.timeout.server_start = nil
		end
		if opts.timeout.request and opts.timeout.request < 1000 then
			vim.notify("request timeout too low, using default", vim.log.levels.WARN)
			opts.timeout.request = nil
		end
	end

	M.options = vim.tbl_deep_extend("force", M.defaults, opts)
end

return M
