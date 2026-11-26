--- Highlight groups for the notification cards (`VCNotify*`) and the toasts (`VCToast*`), built from the
--- terminal's colors like the finder's: tints blended from the real palette when `vc.theme` knows it, the
--- 16-color palette indexes otherwise.
local theme = require("vc.theme")

local M = {}

-- ANSI slots by role.
local RED, YELLOW, BLUE, CYAN = 1, 3, 4, 6
local NONE = "NONE"

--- Highlight attributes per group, in RGB when the terminal's colors are known, else palette indexes.
local function groups()
	local p = theme.palette
	if not p then
		local light = vim.o.background == "light"
		local card = { ctermbg = light and 7 or 0 }
		return {
			ToastNormal = { ctermfg = NONE, ctermbg = NONE },
			ToastBody = { ctermfg = 8 },
			ToastTitleERROR = { ctermfg = RED },
			ToastTitleWARN = { ctermfg = YELLOW },
			ToastTitleINFO = { ctermfg = BLUE },
			ToastTitleDEBUG = { ctermfg = CYAN },
			ToastTitleTRACE = { ctermfg = 8 },
			ToastCount = { ctermfg = YELLOW, bold = true },
			Normal = card,
			-- The border glyphs are half blocks drawn in the page color over the card color.
			Border = { ctermfg = light and 15 or 0, ctermbg = card.ctermbg },
			ERROR = { ctermfg = RED, ctermbg = card.ctermbg, bold = true },
			WARN = { ctermfg = YELLOW, ctermbg = card.ctermbg, bold = true },
			INFO = { ctermfg = BLUE, ctermbg = card.ctermbg, bold = true },
			DEBUG = { ctermfg = CYAN, ctermbg = card.ctermbg, bold = true },
			TRACE = { ctermfg = 8, ctermbg = card.ctermbg },
		}
	end
	local card = theme.mix(p.bg, p.fg, 0.08)
	local function level(slot)
		return { fg = theme.hex(p[slot]), bg = card, bold = true }
	end
	local function color(slot)
		return { fg = theme.hex(p[slot]) }
	end
	return {
		ToastNormal = { fg = NONE, bg = NONE },
		ToastBody = { fg = theme.mix(p.bg, p.fg, 0.5) },
		ToastTitleERROR = color(RED),
		ToastTitleWARN = color(YELLOW),
		ToastTitleINFO = color(BLUE),
		ToastTitleDEBUG = color(CYAN),
		ToastTitleTRACE = { fg = theme.mix(p.bg, p.fg, 0.5) },
		ToastCount = { fg = theme.hex(p[YELLOW]), bold = true },
		Normal = { fg = theme.mix(p.bg, p.fg, 0.75), bg = card },
		Border = { fg = theme.hex(p.bg), bg = card },
		ERROR = level(RED),
		WARN = level(YELLOW),
		INFO = level(BLUE),
		DEBUG = level(CYAN),
		TRACE = { fg = theme.mix(p.bg, p.fg, 0.5), bg = card },
	}
end

--- Define every group. Not `default`: this runs again when the terminal's theme changes.
function M.apply()
	theme.activate()
	for name, spec in pairs(groups()) do
		-- `Toast*` keys are toast groups; the rest belong to the cards.
		vim.api.nvim_set_hl(0, (name:find("^Toast") and "VC" or "VCNotify") .. name, spec)
	end
end

function M.setup()
	M.apply()
	-- Same triggers as the finder: 'background' follows the terminal's light/dark, focus covers terminals
	-- that cannot say so. Only highlights change, open cards stay as they are.
	local group = vim.api.nvim_create_augroup("VCNotifyHighlights", { clear = true })
	local function refresh()
		theme.refresh(M.apply)
	end
	vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = refresh })
	vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = refresh })
end

return M
