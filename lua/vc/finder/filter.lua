local fieldquery = require("vc.finder.fieldquery")

---@class VC.Finder.Filter
---@field text string what the user typed
---@field terms VC.Finder.FieldTerm[] the `field:value` terms in `text`
---@field pattern string fuzzy pattern driving the matcher: `text` without the field terms
local M = {}
M.__index = M

---@return VC.Finder.Filter
function M.new()
	return setmetatable({ text = "", terms = {}, pattern = "" }, M)
end

---@param text string
function M:update(text)
	local query = fieldquery.parse(text)
	self.text = text
	self.terms = query.terms
	self.pattern = query.rest
end

return M
