local Finder = require("vc.finder")
local highlights = require("vc.finder.highlights")
local theme = require("vc.theme")

local function hl(name)
	return vim.api.nvim_get_hl(0, { name = "VCFinder" .. name, link = false })
end

describe("finder highlights", function()
	before_each(function()
		vim.o.background = "dark"
		highlights.setup()
	end)

	it("leaves the surface to the terminal", function()
		eq(nil, hl("Normal").ctermbg)
		eq(nil, hl("Normal").ctermfg)
		eq(nil, hl("Border").ctermbg)
	end)

	it("takes accent colors from the palette", function()
		eq(3, hl("PreviewTitle").ctermfg)
		eq(1, hl("ListGone").ctermfg)
	end)

	it("never links to a default-scheme group", function()
		for _, name in ipairs(vim.fn.getcompletion("VCFinder", "highlight")) do
			eq(nil, vim.api.nvim_get_hl(0, { name = name }).link, name .. " is a link")
		end
	end)

	it("defines the conversation groups, with a palette fallback for each", function()
		for _, name in ipairs({
			"PreviewMeta",
			"PreviewPrompt",
			"PreviewBand",
			"PreviewDot",
			"PreviewToolName",
			"PreviewToolArgs",
			"PreviewResult",
			"PreviewError",
			"PreviewThinking",
			"PreviewFold",
			"PreviewBold",
			"PreviewItalic",
			"PreviewStrike",
			"PreviewLink",
			"PreviewCode",
			"PreviewQuote",
			"PreviewQuoteBar",
			"PreviewHeading",
			"PreviewHeading1",
			"PreviewCodeLang",
			"PreviewCodeKeyword",
			"PreviewCodeString",
			"PreviewCodeNumber",
			"PreviewCodeComment",
			"PreviewCodeFunction",
			"PreviewCodeType",
			"PreviewDiffAdd",
			"PreviewDiffAddSign",
			"PreviewDiffDelete",
			"PreviewDiffDeleteSign",
		}) do
			truthy(next(hl(name)) ~= nil, name .. " is not defined")
		end
		eq(2, hl("PreviewCodeString").ctermfg)
		eq(5, hl("PreviewCodeKeyword").ctermfg)
		eq(2, hl("PreviewDiffAdd").ctermfg)
		eq(1, hl("PreviewDiffDelete").ctermfg)
		eq(true, hl("PreviewBold").bold)
		eq(true, hl("PreviewLink").underline)
	end)

	it("redefines the conversation groups when the terminal's colors change", function()
		theme.palette = { fg = { 250, 250, 250 }, bg = { 10, 10, 10 } }
		for i = 0, 15 do
			theme.palette[i] = { i * 10, 100, 100 }
		end
		highlights.apply()
		local dark = hl("PreviewDiffAdd").bg
		theme.palette.bg = { 240, 240, 240 }
		highlights.apply()
		truthy(hl("PreviewDiffAdd").bg ~= dark, "the diff band follows the new background")
		theme.palette = nil
		vim.o.termguicolors = false
		highlights.apply()
		eq(2, hl("PreviewDiffAdd").ctermfg)
	end)

	it("tints the selected row for the dark background", function()
		eq(0, hl("ListCursorLine").ctermbg)
	end)

	it("repaints for a light background without touching the open finder", function()
		local session = Finder.open({ cwd = "/work/here", on_confirm = function() end, on_exit = function() end })
		local buf = session.view.input.buf
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { " login" })
		vim.o.background = "light"
		eq(7, hl("ListCursorLine").ctermbg)
		eq(" login", vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1])
		session:close()
	end)

	it("falls back to the dark tint when nothing says otherwise", function()
		vim.o.background = "dark"
		eq(0, hl("ListCursorLine").ctermbg)
	end)

	describe("with the terminal's real colors", function()
		local palette = { fg = { 252, 252, 250 }, bg = { 45, 42, 46 } }
		for i = 0, 15 do
			palette[i] = { i * 10, i * 10, i * 10 }
		end

		before_each(function()
			theme.palette = palette
			highlights.apply()
		end)

		it("blends a tint for the selected row and the dim text", function()
			eq(tonumber(theme.mix(palette.bg, palette.fg, 0.08):sub(2), 16), hl("ListCursorLine").bg)
			eq(tonumber(theme.mix(palette.bg, palette.fg, 0.5):sub(2), 16), hl("ListDim").fg)
		end)

		it("blends the diff bands from the terminal's green and red", function()
			eq(tonumber(theme.mix(palette.bg, palette[2], 0.15):sub(2), 16), hl("PreviewDiffAdd").bg)
			eq(tonumber(theme.mix(palette.bg, palette[1], 0.15):sub(2), 16), hl("PreviewDiffDelete").bg)
			eq(tonumber(theme.mix(palette.bg, palette[2], 0.6):sub(2), 16), hl("PreviewDiffAddSign").fg)
		end)

		it("leaves the background to the terminal", function()
			eq(nil, hl("Normal").bg)
			eq(nil, vim.api.nvim_get_hl(0, { name = "Normal" }).bg)
		end)

		it("gives terminal buffers the terminal's palette", function()
			eq(true, vim.o.termguicolors)
			eq(theme.hex(palette[1]), vim.g.terminal_color_1)
		end)

		it("goes back to palette indexes when the colors are unknown", function()
			theme.palette = nil
			vim.o.termguicolors = false
			highlights.apply()
			eq(0, hl("ListCursorLine").ctermbg)
		end)
	end)
end)
