local M = {}

local log_file = vim.fn.stdpath("cache") .. "/codepicker.log"

-- Lazy load config to avoid circular dependency
local function get_config()
	return require("codepicker.config")
end

local function write_log(level, msg)
	local f = io.open(log_file, "a")
	if f then
		f:write(os.date("%Y-%m-%d %H:%M:%S") .. " [" .. level .. "] " .. msg .. "\n")
		f:close()
	end
end

function M.debug(msg)
	local config = get_config()
	if config.options.debug then
		write_log("DEBUG", msg)
	end
end

function M.info(msg)
	write_log("INFO", msg)
end

function M.warn(msg)
	write_log("WARN", msg)
	vim.notify(msg, vim.log.levels.WARN)
end

function M.error(msg)
	write_log("ERROR", msg)
	vim.notify(msg, vim.log.levels.ERROR)
end

function M.get_log_path()
	return log_file
end

function M.clear()
	local f = io.open(log_file, "w")
	if f then
		f:close()
	end
end

return M
