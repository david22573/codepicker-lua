local M = {}
local config = require("codepicker.config")
local server = require("codepicker.server")
local job = require("codepicker.job")
local ui = require("codepicker.ui")
local log = require("codepicker.log")

-- Track active requests for cleanup
local active_requests = {}

-- Setup function to be called by user
function M.setup(opts)
	config.setup(opts)

	-- Auto-start server on first use
	vim.api.nvim_create_autocmd("VimEnter", {
		once = true,
		callback = function()
			if config.options.auto_start ~= false then
				log.debug("Auto-starting server")
			end
		end,
	})

	-- Cleanup on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			log.debug("Cleaning up on exit")
			job.stop_all()
			server.stop()
		end,
	})

	-- Buffer cleanup
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

-- Ask: Stream AI response to a markdown buffer
function M.ask(query, opts)
	opts = opts or {}

	-- Validate input
	if not query or vim.trim(query) == "" then
		log.error("Query cannot be empty")
		return
	end

	log.info("Ask query: " .. query)

	-- Create UI buffer
	local buf = ui.create_scratch_buf("markdown")
	if not buf then
		log.error("Failed to create buffer")
		return
	end

	local win = ui.open_split(buf)
	if not win then
		log.error("Failed to open split")
		return
	end

	-- Show initial loading message
	local progress_timer = ui.show_progress(buf, "Thinking...")

	-- Start server
	if not server.start() then
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end
		ui.append_text(buf, "\n❌ Failed to start server")
		return
	end

	-- Wait for server to be ready
	server.wait_ready(function(ready)
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end

		if not ready then
			ui.append_text(buf, "\n❌ Server failed to start. Try :CodePickerStatus for details.")
			return
		end

		-- Clear loading message
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })
		end

		-- Prepare request
		local current_file = vim.fn.expand("%:p")
		local payload = vim.fn.json_encode({
			query = query,
			model = config.options.model,
			focus = current_file ~= "" and current_file or nil,
			overwrite = opts.overwrite or false,
		})

		log.debug("Sending request to " .. server.url("/ask"))

		-- Make request
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
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(buf) then
					if code == 0 then
						ui.append_text(buf, "\n✅ Done.")
					else
						ui.append_text(buf, "\n❌ Request failed with code: " .. code)
					end
				end
			end)
		end)

		if request_job then
			active_requests[buf] = request_job
		else
			ui.append_text(buf, "\n❌ Failed to start request")
		end
	end)
end

-- Refactor: Generate code and show diff view
function M.refactor(instruction)
	-- Validate input
	if not instruction or vim.trim(instruction) == "" then
		log.error("Instruction cannot be empty")
		return
	end

	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		log.error("Save the file first before refactoring")
		return
	end

	log.info("Refactor instruction: " .. instruction)

	local src_buf = vim.api.nvim_get_current_buf()
	local filetype = vim.bo[src_buf].filetype

	-- Create destination buffer
	local dst_buf = ui.create_scratch_buf(filetype)
	if not dst_buf then
		log.error("Failed to create buffer")
		return
	end

	local dst_win = ui.open_split(dst_buf)
	if not dst_win then
		log.error("Failed to open split")
		return
	end

	-- Set buffer name
	vim.api.nvim_buf_set_name(dst_buf, "[CodePicker] Refactored")

	-- Add header
	vim.api.nvim_buf_set_lines(dst_buf, 0, 0, false, {
		"-- AI-generated refactored code",
		"-- " .. config.options.mappings.accept .. " to accept changes",
		"-- " .. config.options.mappings.decline .. " to discard",
		"",
	})

	local progress_timer = ui.show_progress(dst_buf, "Generating code...")

	-- Setup keymaps for accept/decline
	local opts = { noremap = true, silent = true, buffer = dst_buf }

	vim.keymap.set("n", config.options.mappings.accept, function()
		local new_lines = vim.api.nvim_buf_get_lines(dst_buf, 4, -1, false) -- Skip header
		vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, new_lines)
		vim.cmd("diffoff!")
		vim.api.nvim_buf_delete(dst_buf, { force = true })
		vim.cmd("update")
		if #vim.lsp.get_active_clients({ bufnr = src_buf }) > 0 then
			vim.lsp.buf.format({ async = false })
		end
		print("✅ Changes applied")
	end, opts)

	vim.keymap.set("n", config.options.mappings.decline, function()
		vim.cmd("diffoff!")
		vim.api.nvim_buf_delete(dst_buf, { force = true })
		print("❌ Changes discarded")
	end, opts)

	-- Start server
	if not server.start() then
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end
		ui.append_text(dst_buf, "\n❌ Failed to start server")
		return
	end

	server.wait_ready(function(ready)
		if progress_timer then
			progress_timer:stop()
			progress_timer:close()
		end

		if not ready then
			ui.append_text(dst_buf, "\n❌ Server failed to start")
			return
		end

		-- Clear header for actual code
		vim.api.nvim_buf_set_lines(dst_buf, 4, -1, false, {})

		-- Enhanced prompt
		local prompt = string.format(
			[[You are an expert coding assistant.
Task: Rewrite the following file to satisfy the instruction.
Instruction: %s

CRITICAL REQUIREMENTS:
1. Output the COMPLETE file content - do not stop early or truncate
2. Do NOT use placeholders like "// ... rest of code ..." or "// ... existing code ..."
3. Preserve the existing code structure and style
4. Output ONLY the code - no markdown, no explanations, no code fences
5. Every line of the original file should be represented in your output]],
			instruction
		)

		local payload = vim.fn.json_encode({
			query = prompt,
			model = config.options.model,
			focus = current_file,
		})

		local chunks = {}
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
			table.insert(chunks, line)
		end, function(code)
			active_requests[dst_buf] = nil
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(dst_buf) then
					return
				end

				if code ~= 0 then
					ui.append_text(dst_buf, "\n❌ Request failed with code: " .. code)
					return
				end

				-- Set buffer content
				vim.api.nvim_buf_set_lines(dst_buf, 4, -1, false, chunks)

				-- Scroll to top
				vim.api.nvim_buf_call(dst_buf, function()
					vim.cmd("normal! gg")
				end)

				-- Enable diff mode
				vim.cmd("windo diffthis")

				print("✨ Code generated. Review and accept/decline changes.")
			end)
		end)

		if request_job then
			active_requests[dst_buf] = request_job
		else
			ui.append_text(dst_buf, "\n❌ Failed to start request")
		end
	end)
end

return M
