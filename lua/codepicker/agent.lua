local M = {}
local config = require("codepicker.config")
local server = require("codepicker.server")
local ui = require("codepicker.ui")
local log = require("codepicker.log")
local job = require("codepicker.job")

-- Queue for non-blocking Sentinel approvals
local pending_approvals = {}

-- Non-blocking request
local function request_approval(req_id, command, reason)
	table.insert(pending_approvals, { id = req_id, command = command, reason = reason })

	vim.schedule(function()
		local msg = string.format(
			"Agent wants to run: `%s`\nReason: %s\n\nRun :CodePickerApprove (or <leader>cy) to allow.",
			command,
			reason
		)
		vim.notify(msg, vim.log.levels.WARN, { title = "⚠️ Sentinel Alert" })
	end)
end

-- Process the oldest pending request
function M.handle_approval(approved)
	if #pending_approvals == 0 then
		vim.notify("No pending Sentinel requests.", vim.log.levels.INFO, { title = "CodePicker" })
		return
	end

	local req = table.remove(pending_approvals, 1)
	local payload = vim.fn.json_encode({ id = req.id, approved = approved })

	job.run({
		"curl",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		payload,
		server.url("/agent/approve"),
	}, function() end)

	vim.schedule(function()
		if approved then
			vim.notify("✅ Approved: " .. req.command, vim.log.levels.INFO, { title = "CodePicker Sentinel" })
		else
			vim.notify("🛑 Blocked: " .. req.command, vim.log.levels.WARN, { title = "CodePicker Sentinel" })
		end
	end)
end

function M.run_task(query)
	if not server.is_running() then
		log.error("Server not running. Run :CodePickerServe first.")
		return
	end

	local buf = ui.create_scratch_buf("markdown")
	local win = ui.open_split(buf)
	local progress = ui.show_progress(buf, "Agent is thinking...")

	ui.append_text(buf, "# 🤖 Agent Task: " .. query .. "\n\n")

	local url = server.url("/agent/task?q=" .. vim.fn.fnameescape(query))

	-- SSE Stream Handler
	job.run({
		"curl",
		"-N",
		"-s",
		url,
	}, function(line)
		local data_str = line:match("^data: (.+)$")
		if not data_str then
			return
		end

		local ok, event = pcall(vim.fn.json_decode, data_str)
		if not ok or not event then
			return
		end

		vim.schedule(function()
			if event.type == "thought" then
				ui.append_text(buf, event.content)
			elseif event.type == "approval_req" then
				-- Push to non-blocking queue instead of UI prompt
				request_approval(event.id, event.command, event.reason)
			elseif event.type == "error" then
				ui.append_text(buf, "\n❌ Error: " .. event.msg)
			elseif event.type == "done" then
				if progress then
					progress:stop()
				end
				ui.append_text(buf, "\n✨ Task Completed.")
			end
		end)
	end)
end

return M
