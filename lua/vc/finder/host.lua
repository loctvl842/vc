--- What a pipeline may tell whoever owns it, so it never touches windows.

---@class VC.Finder.Host
---@field alive fun(): boolean false once the owner is closed; the pipeline drops late work
---@field render fun() `query.matched` changed
---@field count fun(text?: string) text for the prompt's count label

local M = {}

---@param overrides? table
---@return VC.Finder.Host
function M.headless(overrides)
	return vim.tbl_extend("force", {
		alive = function()
			return true
		end,
		render = function() end,
		count = function() end,
	}, overrides or {})
end

return M
