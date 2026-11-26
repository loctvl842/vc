---@class VC.Finder.UI
---@field input VC.Finder.UI.Input
---@field list VC.Finder.UI.List
---@field preview VC.Finder.UI.Preview
local M = {}

setmetatable(M, {
	__index = function(_, k)
		return require("vc.finder.ui." .. k)
	end,
})

return M
