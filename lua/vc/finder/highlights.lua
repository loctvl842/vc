--- Highlight groups for the finder, built from the terminal's colors so the finder follows its theme.
--- With the real colors (`vc.theme`) tints are blended from them; otherwise the groups fall back to the
--- terminal's 16-color palette indexes (`termguicolors` off).
local theme = require("vc.theme")

local M = {}

local NONE = "NONE"

-- ANSI slots by role.
local RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN = 1, 2, 3, 4, 5, 6

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
			blue = { ctermfg = BLUE },
			magenta = { ctermfg = MAGENTA },
			match = { ctermfg = YELLOW, bold = true },
			select = { ctermbg = light and 7 or 0 },
			add = { ctermfg = GREEN },
			add_sign = { ctermfg = GREEN, bold = true },
			delete = { ctermfg = RED },
			delete_sign = { ctermfg = RED, bold = true },
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
		blue = slot(BLUE),
		magenta = slot(MAGENTA),
		match = { fg = theme.hex(p[YELLOW]), bg = theme.mix(p.bg, p.fg, 0.2), bold = true },
		select = { bg = theme.mix(p.bg, p.fg, 0.08) },
		-- Diff tints: a faint band for the line, a stronger number and sign on the same band.
		add = { bg = theme.mix(p.bg, p[GREEN], 0.15) },
		add_sign = { fg = theme.mix(p.bg, p[GREEN], 0.6), bg = theme.mix(p.bg, p[GREEN], 0.15), bold = true },
		delete = { bg = theme.mix(p.bg, p[RED], 0.15) },
		delete_sign = { fg = theme.mix(p.bg, p[RED], 0.6), bg = theme.mix(p.bg, p[RED], 0.15), bold = true },
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
		ListNew = c.green,
		ListGone = c.red,
		Hint = c.dim,
		PreviewTitle = bold(c.accent),
		PreviewMeta = c.dim,
		PreviewPrompt = bold(c.accent),
		PreviewBand = c.select,
		PreviewDot = bold(c.surface),
		PreviewToolName = bold(c.surface),
		PreviewToolArgs = c.dim,
		PreviewResult = c.dim,
		PreviewError = c.red,
		PreviewThinking = vim.tbl_extend("force", c.dim, { italic = true }),
		PreviewFold = c.dim,
		PreviewBold = { bold = true },
		PreviewItalic = { italic = true },
		PreviewStrike = { strikethrough = true },
		PreviewLink = { underline = true },
		PreviewCode = c.blue,
		PreviewQuote = vim.tbl_extend("force", c.dim, { italic = true }),
		PreviewQuoteBar = c.dim,
		PreviewHeading = { bold = true },
		PreviewHeading1 = { bold = true, italic = true, underline = true },
		PreviewDiffAdd = c.add,
		PreviewDiffAddSign = c.add_sign,
		PreviewDiffDelete = c.delete,
		PreviewDiffDeleteSign = c.delete_sign,
		PreviewCodeLang = c.dim,
		PreviewCodeKeyword = c.magenta,
		PreviewCodeString = c.green,
		PreviewCodeNumber = c.accent,
		PreviewCodeComment = vim.tbl_extend("force", c.dim, { italic = true }),
		PreviewCodeFunction = c.blue,
		PreviewCodeType = c.cyan,
		ListCursorLine = c.select,
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
