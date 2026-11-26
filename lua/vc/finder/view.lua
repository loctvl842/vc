-- Window + buffer wrapper shared by the finder panes.
---@class VC.Finder.View
---@field buf integer|false
---@field win integer|false
local Instance = {}
Instance.__index = Instance

---@param buf integer
---@param win integer
function Instance:new(buf, win)
	return setmetatable({ buf = buf or false, win = win or false }, self)
end

---@return boolean
function Instance:is_valid()
	if not self.buf or not self.win then
		return false
	end
	return vim.api.nvim_buf_is_valid(self.buf) and vim.api.nvim_win_is_valid(self.win)
end

function Instance:close()
	if self.win and vim.api.nvim_win_is_valid(self.win) then
		vim.api.nvim_win_close(self.win, true)
	end
	self.buf = false
	self.win = false
end

--- Subclass; `init(obj, ...)` attaches extra state after construction.
---@param init? fun(obj: table, ...: any)
function Instance:extend(init)
	local parent = self
	local cls = setmetatable({}, {
		__index = parent,
		__call = function(t, ...)
			return t:new(...)
		end,
	})
	cls.__index = cls
	function cls:new(buf, win, ...)
		local obj = setmetatable({ buf = buf or false, win = win or false }, cls)
		if init then
			init(obj, ...)
		end
		return obj
	end
	return cls
end

local M = { Instance = Instance }

--- Scratch buffer with a filetype.
---@param filetype string
---@return integer
function M.new_buf(filetype)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = filetype
	return buf
end

--- Set a window-local option.
---@param win integer
---@param k string
---@param v any
function M.wo(win, k, v)
	vim.api.nvim_set_option_value(k, v, { scope = "local", win = win })
end

return M
