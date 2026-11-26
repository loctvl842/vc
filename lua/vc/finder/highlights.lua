--- Highlight groups for the finder, built from the terminal's colors so the finder follows its theme.
--- With the real colors (`vc.theme`) tints are blended from them; otherwise the groups fall back to the
--- terminal's 16-color palette indexes (`termguicolors` off).
local theme = require("vc.theme")

local M = {}

local NONE = "NONE"

-- ANSI slots by role.
local RED, GREEN, YELLOW, BLUE, CYAN = 1, 2, 3, 4, 6

--- Highlight attributes per role, in RGB when the terminal's colors are known, else palette indexes.
local function colors()
	local p = theme.palette
	if not p then
		local light = vim.o.background == "light"
		return {
			surface = { ctermfg = NONE, ctermbg = NONE },
			dim = { ctermfg = 8 },
			border = { ctermfg = 8, ctermbg = NONE },
			accent = { ctermfg = YELLOW },
			cyan = { ctermfg = CYAN },
			green = { ctermfg = GREEN },
			red = { ctermfg = RED },
			you = { ctermfg = CYAN },
			match = { ctermfg = YELLOW, bold = true },
			select = { ctermbg = light and 7 or 0 },
			fold = { ctermfg = 8, ctermbg = light and 7 or 0 },
		}
	end
	local function slot(i)
		return { fg = theme.hex(p[i]) }
	end
	return {
		surface = { fg = NONE, bg = NONE },
		dim = { fg = theme.mix(p.bg, p.fg, 0.5) },
		border = { fg = theme.mix(p.bg, p.fg, 0.3), bg = NONE },
		accent = slot(YELLOW),
		cyan = slot(CYAN),
		green = slot(GREEN),
		red = slot(RED),
		you = slot(BLUE),
		match = { fg = theme.hex(p[YELLOW]), bg = theme.mix(p.bg, p.fg, 0.2), bold = true },
		select = { bg = theme.mix(p.bg, p.fg, 0.08) },
		fold = { fg = theme.mix(p.bg, p.fg, 0.5), bg = theme.mix(p.bg, p.fg, 0.06) },
	}
end

--- Define every group. Not `default`: this runs again when the terminal's theme changes.
function M.apply()
	theme.activate()
	local c = colors()
	local function bold(spec)
		return vim.tbl_extend("force", spec, { bold = true })
	end
	local groups = {
		Normal = c.surface,
		Border = c.border,
		InputTitle = bold(c.accent),
		Spinner = c.cyan,
		ListSelectionPrefix = c.accent,
		ListMatch = c.match,
		ListTitle = {},
		ListDim = c.dim,
		ListLabel = c.dim,
		ListRecap = c.dim,
		ListPrompt = {},
		ListNew = c.green,
		ListGone = c.red,
		Hint = c.dim,
		PreviewTitle = bold(c.accent),
		PreviewHeading = bold(c.accent),
		PreviewYou = c.you,
		PreviewClaude = c.green,
		ListCursorLine = c.select,
		PreviewTool = { bg = c.fold.bg, ctermbg = c.fold.ctermbg },
		PreviewFold = c.fold,
		ListCursor = { blend = 100, nocombine = true },
	}
	for name, spec in pairs(groups) do
		vim.api.nvim_set_hl(0, "VCFinder" .. name, spec)
	end
	-- Neovim's default scheme paints its own grey behind everything; the terminal's background wins.
	vim.api.nvim_set_hl(0, "Normal", c.surface)
end

function M.setup()
	M.apply()
	-- Neovim updates 'background' when the terminal flips light/dark; focus covers terminals that cannot
	-- say so. Only highlights change, so the query, selection and scroll of an open finder stay as they are.
	local group = vim.api.nvim_create_augroup("VCFinderHighlights", { clear = true })
	local function refresh()
		theme.refresh(M.apply)
	end
	vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = refresh })
	vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = refresh })
end

return M
