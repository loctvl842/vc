local highlights = require("vc.finder.highlights")

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
		eq(6, hl("PreviewTitle").ctermfg)
		eq(1, hl("ListGone").ctermfg)
	end)

	it("never links to a default-scheme group", function()
		for _, name in ipairs(vim.fn.getcompletion("VCFinder", "highlight")) do
			eq(nil, vim.api.nvim_get_hl(0, { name = name }).link, name .. " is a link")
		end
	end)

	it("tints the selected row for the dark background", function()
		eq(0, hl("ListCursorLine").ctermbg)
	end)
end)
