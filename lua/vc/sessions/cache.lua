-- Persistent index of session rows so reopening does not rescan the store.
local M = {}

local VERSION = 3

---@return string
function M.default_path()
	return vim.fs.joinpath(vim.fn.stdpath("cache"), "vc", "index.json")
end

--- Rows keyed by transcript path; empty when missing, corrupt or from another version.
---@param path string
---@return table<string, VC.Row>
function M.read(path)
	local f = io.open(path, "rb")
	if not f then
		return {}
	end
	local text = f:read("*a")
	f:close()
	local ok, obj = pcall(vim.json.decode, text)
	if not ok or type(obj) ~= "table" or obj.version ~= VERSION or type(obj.rows) ~= "table" then
		return {}
	end
	return obj.rows
end

--- Atomic write (tmp file then rename).
---@param path string
---@param rows table<string, VC.Row>
function M.write(path, rows)
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	local tmp = path .. ".tmp"
	local f = io.open(tmp, "wb")
	if not f then
		return false
	end
	f:write(vim.json.encode({ version = VERSION, rows = rows }))
	f:close()
	return vim.uv.fs_rename(tmp, path) == true
end

return M
