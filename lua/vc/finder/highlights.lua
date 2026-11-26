--- Highlight groups for the finder. They use the terminal's own 16-color palette and background
--- (cterm indexes, `termguicolors` off), so the finder follows whatever theme the terminal has.
local M = {}

local NONE = "NONE"

-- Palette slots by role.
local DIM, ERROR, GREEN, YELLOW, CYAN = 8, 1, 2, 3, 6

---@type table<string, vim.api.keyset.highlight>
local static = {
	Normal = { ctermfg = NONE, ctermbg = NONE },
	Border = { ctermfg = DIM, ctermbg = NONE },
	InputTitle = { ctermfg = CYAN, ctermbg = NONE, bold = true },
	Spinner = { ctermfg = CYAN },
	ListSelectionPrefix = { ctermfg = CYAN },
	ListMatch = { ctermfg = YELLOW, bold = true },
	ListTitle = { ctermfg = NONE },
	ListDim = { ctermfg = DIM },
	ListNew = { ctermfg = GREEN },
	ListGone = { ctermfg = ERROR },
	Hint = { ctermfg = DIM },
	PreviewTitle = { ctermfg = CYAN, ctermbg = NONE, bold = true },
	PreviewHeading = { ctermfg = CYAN, bold = true },
	PreviewYou = { ctermfg = CYAN },
	PreviewClaude = { ctermfg = GREEN },
}

--- The selected row is a palette tint: black on a dark terminal, white on a light one.
local function selection()
	return { ctermbg = vim.o.background == "light" and 7 or 0 }
end

function M.setup()
	for name, spec in pairs(static) do
		vim.api.nvim_set_hl(0, "VCFinder" .. name, vim.tbl_extend("force", spec, { default = true }))
	end
	-- Not `default`: it has to be redefined when the background changes.
	vim.api.nvim_set_hl(0, "VCFinderListCursorLine", selection())
	vim.api.nvim_set_hl(0, "VCFinderListCursor", { blend = 100, nocombine = true, default = true })
end

return M
