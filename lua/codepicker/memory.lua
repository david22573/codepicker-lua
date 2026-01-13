local M = {}
local server = require("codepicker.server")
local log = require("codepicker.log")
local job = require("codepicker.job")

-- Helper to get relative path of current buffer
local function get_current_rel_path()
	local abs = vim.fn.expand("%:p")
	local cwd = vim.fn.getcwd()
	return abs:sub(#cwd + 2) -- +2 to remove leading slash
end

function M.add_current_file()
	local path = get_current_rel_path()
	M.modify_context("POST", path)
end

function M.remove_current_file()
	local path = get_current_rel_path()
	M.modify_context("DELETE", path)
end

function M.modify_context(method, path)
	if not server.is_running() then
		log.error("Server not running.")
		return
	end

	local payload = vim.fn.json_encode({ path = path })

	job.run({
		"curl",
		"-s",
		"-X",
		method,
		"-H",
		"Content-Type: application/json",
		"-d",
		payload,
		server.url("/agent/context"),
	}, function(output)
		vim.schedule(function()
			if method == "POST" then
				print("🧠 Added to Agent Memory: " .. path)
			else
				print("🗑️  Removed from Agent Memory: " .. path)
			end
		end)
	end)
end

function M.show_context()
	if not server.is_running() then
		return
	end

	job.run({ "curl", "-s", server.url("/agent/context") }, function(output)
		local ok, res = pcall(vim.fn.json_decode, output)
		if ok and res.files then
			local msg = "📂 Active Context:\n"
			if #res.files == 0 then
				msg = msg .. "  (Empty)"
			else
				for _, f in ipairs(res.files) do
					msg = msg .. "  - " .. f .. "\n"
				end
			end
			vim.schedule(function()
				print(msg)
			end)
		end
	end)
end

return M
