local M = {}
local config = require("codepicker.config")
local server = require("codepicker.server")
local job = require("codepicker.job")
local ui = require("codepicker.ui")
local log = require("codepicker.log")
local agent = require("codepicker.agent")
local memory = require("codepicker.memory")

-- Helper: Get text from visual selection
local function get_visual_selection()
	local _, csrow, _, _ = unpack(vim.fn.getpos("'<"))
	local _, cerow, _, _ = unpack(vim.fn.getpos("'>"))
	if csrow > cerow then
		csrow, cerow = cerow, csrow
	end
	local lines = vim.api.nvim_buf_get_lines(0, csrow - 1, cerow, false)
	return table.concat(lines, "\n")
end

function M.setup(opts)
	config.setup(opts)

	-- Auto-start Server
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function()
			if config.options.auto_start ~= false then
				log.debug("Auto-starting server")
				-- We ensure the server is ready before we need it
				if not server.is_running() then
					server.start()
				end
			end
		end,
	})

	-- Cleanup on Exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			log.debug("Cleaning up on exit")
			job.stop_all()
			server.stop()
		end,
	})

	-- Register Commands
	M.register_commands()
end

function M.register_commands()
	-- 1. General Task (The main entry point)
	vim.api.nvim_create_user_command("CodePickerTask", function(opts)
		local args = vim.trim(opts.args)
		if args == "" then
			print("❌ Please provide a task")
			return
		end
		agent.run_task(args)
	end, { nargs = "+" })

	-- 2. Context Management (Memory)
	vim.api.nvim_create_user_command("CodePickerAdd", function()
		memory.add_current_file()
	end, {})

	vim.api.nvim_create_user_command("CodePickerDrop", function()
		memory.remove_current_file()
	end, {})

	vim.api.nvim_create_user_command("CodePickerContext", function()
		memory.show_context()
	end, {})

	-- 3. Legacy Wrappers (Redirected to Agent)
	vim.api.nvim_create_user_command("CodePickerAsk", function(opts)
		M.ask(opts.args)
	end, { nargs = "+" })

	vim.api.nvim_create_user_command("CodePickerEdit", function(opts)
		M.refactor(opts.args, { visual = opts.range > 0 })
	end, { nargs = "+", range = true })
end

-- Wrapper: Sends a simple question to the Agent
function M.ask(query)
	-- We just treat a question as a task that doesn't need to write files
	agent.run_task("Question: " .. query)
end

-- Wrapper: Wraps code selection + instruction and sends to Agent
function M.refactor(instruction, opts)
	opts = opts or {}
	local src_buf = vim.api.nvim_get_current_buf()
	local filetype = vim.bo[src_buf].filetype
	local code_context = ""

	-- Get content (Visual or Whole File)
	if opts.visual then
		code_context = get_visual_selection()
	else
		code_context = table.concat(vim.api.nvim_buf_get_lines(src_buf, 0, -1, false), "\n")
	end

	-- Construct a task prompt for the Agent
	local prompt = string.format(
		[[I need you to refactor the following %s code.
Instruction: %s

Code:
```%s
%s

If you change the code, use the 'write_shadow_file' tool to output the new version so I can review it.]],
		filetype,
		instruction,
		filetype,
		code_context
	)
	-- Send to Agent
	agent.run_task(prompt)
end
return M
