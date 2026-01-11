local M = {}
local config = require("codepicker.config")
local server = require("codepicker.server")
local job = require("codepicker.job")
local ui = require("codepicker.ui")
local log = require("codepicker.log")

-- Track active requests for cleanup
local active_requests = {}

-- Helper: Get text from visual selection
local function get_visual_selection()
	local _, csrow, _, _ = unpack(vim.fn.getpos("'<"))
	local _, cerow, _, _ = unpack(vim.fn.getpos("'>"))

	if csrow > cerow then
		csrow, cerow = cerow, csrow
	end

	local lines = vim.api.nvim_buf_get_lines(0, csrow - 1, cerow, false)
	return table.concat(lines, "\n"), csrow - 1, cerow
end

function M.setup(opts)
	config.setup(opts)

	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function()
			if config.options.auto_start ~= false then
				log.debug("Auto-starting server")
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			log.debug("Cleaning up on exit")
			job.stop_all()
			server.stop()
		end,
	})

	vim.api.nvim_create_autocmd("BufDelete", {
		callback = function(args)
			local buf = args.buf
			if active_requests[buf] then
				job.stop(active_requests[buf])
				active_requests[buf] = nil
			end
		end,
	})
end

function M.ask(query, opts)
	opts = opts or {}

	if not query or vim.trim(query) == "" then
		log.error("Query cannot be empty")
		return
	end

	local buf = ui.create_scratch_buf("markdown")
	local win = ui.open_split(buf)
	if not buf or not win then
		log.error("Failed to create UI")
		return
	end

	local progress_timer = ui.show_progress(buf, "Thinking...")

	if not server.start() then
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end
		ui.append_text(buf, "\n❌ Failed to start server")
		return
	end

	server.wait_ready(function(ready)
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end
		if not ready then
			ui.append_text(buf, "\n❌ Server failed to start")
			return
		end

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

		local payload = vim.fn.json_encode({
			query = query,
			model = config.options.model,
			focus = vim.fn.expand("%:p"),
			overwrite = opts.overwrite or false,
		})

		local request_job = job.run({
			"curl",
			"-s",
			"-N",
			"--no-buffer",
			"-H",
			"Content-Type: application/json",
			"-X",
			"POST",
			server.url("/ask"),
			"-d",
			payload,
		}, function(line)
			ui.append_text(buf, line .. "\n")
		end, function(code)
			active_requests[buf] = nil
			if code == 0 then
				ui.append_text(buf, "\n✅ Done.")
			else
				ui.append_text(buf, "\n❌ Request failed: " .. code)
			end
		end)

		if request_job then
			active_requests[buf] = request_job
		end
	end)
end

function M.refactor(instruction, opts)
	opts = opts or {}

	if not instruction or vim.trim(instruction) == "" then
		log.error("Instruction cannot be empty")
		return
	end

	local src_buf = vim.api.nvim_get_current_buf()
	local filetype = vim.bo[src_buf].filetype
	vim.cmd("update")

	local is_visual = opts.visual
	if is_visual == nil then
		local mode = vim.fn.mode()
		is_visual = mode == "v" or mode == "V" or mode == "\22"
	end

	local code_context, start_line, end_line

	if is_visual then
		code_context, start_line, end_line = get_visual_selection()
	else
		start_line = 0
		end_line = vim.api.nvim_buf_line_count(src_buf)
		code_context = table.concat(vim.api.nvim_buf_get_lines(src_buf, 0, -1, false), "\n")
	end

	local system_prompt
	if is_visual then
		system_prompt = string.format(
			[[You are a coding assistant.
Task: Refactor a selection.
Instruction: %s

```%s
%s
```]],
			instruction,
			filetype,
			code_context
		)
	else
		system_prompt = string.format(
			[[You are a coding assistant.
Task: Rewrite entire file.
Instruction: %s

```%s
%s
```]],
			instruction,
			filetype,
			code_context
		)
	end

	local dst_buf = ui.create_scratch_buf(filetype)
	local dst_win = ui.open_split(dst_buf)
	if not dst_buf or not dst_win then
		log.error("Failed to create refactor UI")
		return
	end

	vim.api.nvim_buf_set_name(dst_buf, "[CodePicker] Refactor")

	local progress_timer = ui.show_progress(dst_buf, "Generating code...")

	server.wait_ready(function(ready)
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end
		if not ready then
			return
		end

		local payload = vim.fn.json_encode({ query = system_prompt })

		job.run({
			"curl",
			"-s",
			"-N",
			"--no-buffer",
			"-H",
			"Content-Type: application/json",
			"-X",
			"POST",
			server.url("/ask"),
			"-d",
			payload,
		}, function(line)
			if not line:match("^```") then
				vim.api.nvim_buf_set_lines(dst_buf, -1, -1, false, { line })
			end
		end)
	end)
end

return M
