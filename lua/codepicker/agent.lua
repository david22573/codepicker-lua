local M = {}
local config = require("codepicker.config")
local server = require("codepicker.server")
local ui = require("codepicker.ui")
local log = require("codepicker.log")
local job = require("codepicker.job")

-- Handle approval requests from the Sentinel
local function request_approval(req_id, command, reason, on_decision)
	vim.schedule(function()
		local msg = string.format("⚠️  Sentinel Alert\nCommand: %s\nReason: %s\nAllow execution?", command, reason)
		vim.ui.select({ "Yes", "No" }, {
			prompt = msg,
			format_item = function(item)
				return item
			end,
		}, function(choice)
			local approved = (choice == "Yes")
			-- Send decision back to server
			local payload = vim.fn.json_encode({ id = req_id, approved = approved })
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

			if approved then
				print("✅ Command Approved")
			else
				print("🛑 Command Blocked")
			end
		end)
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
		-- Parse SSE "data: {...}" lines
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
				-- Stream thoughts/content to buffer
				ui.append_text(buf, event.content)
			elseif event.type == "approval_req" then
				-- Trigger Blocking UI for Sentinel
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
