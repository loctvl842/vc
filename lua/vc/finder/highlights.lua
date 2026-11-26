--- Highlight groups for the finder. They link to the colorscheme's own groups so the
--- finder follows whatever theme is active.
local M = {}

local links = {
	Normal = "NormalFloat",
	Border = "FloatBorder",
	InputTitle = "Title",
	InputPromptPrefix = "Special",
	Spinner = "Special",
	ListCursorLine = "CursorLine",
	ListSelectionPrefix = "Special",
	ListMatch = "Search",
	ListTitle = "Normal",
	ListDim = "Comment",
	ListNew = "String",
	ListGone = "DiagnosticError",
	Hint = "Comment",
	PreviewTitle = "Title",
	PreviewHeading = "Title",
	PreviewYou = "Function",
	PreviewClaude = "String",
	PreviewFold = "Comment",
}

function M.setup()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, "VCFinder" .. name, { link = target, default = true })
	end
	vim.api.nvim_set_hl(0, "VCFinderListCursor", { blend = 100, nocombine = true, default = true })
end

return M
