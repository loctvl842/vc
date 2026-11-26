--- Full-screen geometry for the finder: prompt and list on the left, preview on the right.
local config = require("vc.finder.config")

---@class VC.Finder.Layout.Geometry
---@field row integer
---@field col integer
---@field w integer content width
---@field h integer content height
---@field border? string[]

local M = {}

---@return { input: VC.Finder.Layout.Geometry, list: VC.Finder.Layout.Geometry, preview: VC.Finder.Layout.Geometry }
function M.calc()
	local total_w = vim.o.columns
	local total_h = vim.o.lines - vim.o.cmdheight
	-- Content widths exclude borders: left border + middle separator + right border = 3 columns.
	local content_w = total_w - 3
	local left_w = math.floor(content_w * (1 - config.preview_ratio))
	local preview_w = content_w - left_w
	-- top border + input(1) + separator + list + bottom border
	local list_h = total_h - 4
	return {
		input = {
			row = 0,
			col = 0,
			w = left_w,
			h = 1,
			border = { "╭", "─", "┬", "│", "┤", "─", "├", "│" },
		},
		list = {
			row = 3,
			col = 0,
			w = left_w,
			h = list_h,
			border = { "", "", "", "│", "┘", "─", "╰", "│" },
		},
		preview = { row = 0, col = left_w + 1, w = preview_w, h = total_h - 2 },
	}
end

return M
