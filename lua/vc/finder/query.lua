---@class VC.Finder.Field
---@field name string the field a `field:value` term names: title, cwd, recap or msg
---@field from integer first byte in `text`
---@field to integer last byte in `text`
---@field plain? boolean matches as a plain substring only (long prose), not fuzzily

---@class VC.Finder.Item
---@field idx integer
---@field score number
---@field text string what the query matches against
---@field fields? VC.Finder.Field[] spans of `text` the query is matched against one at a time
---@field positions? integer[] matched byte positions in `text`
---@field row? VC.Row the session this item stands for
---@field new? boolean the "New session" item
---@field _lower? string cached lowercased text for the matcher

---@class VC.Finder.Query
---@field items VC.Finder.Item[]
---@field matched VC.Finder.Item[]
---@field filter VC.Finder.Filter
---@field limit integer how many matches `matched` keeps (best first)
---@field matching boolean the scorer is still running
---@field total integer how many items match the pattern
local M = {}
M.__index = M

M.DEFAULT_LIMIT = 100000

---@return VC.Finder.Query
function M.new()
	return setmetatable({
		items = {},
		matched = {},
		filter = require("vc.finder.filter").new(),
		limit = M.DEFAULT_LIMIT,
		matching = false,
		total = 0,
	}, M)
end

return M
