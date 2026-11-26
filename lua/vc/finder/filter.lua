---@class VC.Finder.Filter
---@field pattern string fuzzy pattern driving the matcher
local M = {}
M.__index = M

---@return VC.Finder.Filter
function M.new()
	return setmetatable({ pattern = "" }, M)
end

---@param pattern string
function M:update(pattern)
	self.pattern = pattern
end

return M
