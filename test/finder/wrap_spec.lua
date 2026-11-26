local wrap = require("vc.finder.wrap")

--- The text of each wrapped line.
local function rows(text, width)
	local out = {}
	for _, sp in ipairs(wrap.lines(text, width)) do
		out[#out + 1] = text:sub(sp.s, sp.e)
	end
	return out
end

describe("wrap", function()
	it("breaks at spaces and keeps every word whole", function()
		eq({ "one two", "three", "four" }, rows("one two three four", 8))
	end)

	it("fills a line exactly", function()
		eq({ "abc def", "ghi" }, rows("abc def ghi", 7))
	end)

	it("returns nothing for empty or blank text", function()
		eq({}, rows("", 10))
		eq({}, rows("   ", 10))
	end)

	it("cuts a word wider than the line, then lets the next word join the rest", function()
		eq({ "abcde", "fg hi" }, rows("abcdefg hi", 5))
		eq({ "abcd", "efgh", "ij" }, rows("abcdefghij", 4))
	end)

	it("starts an over-wide word on a fresh line", function()
		eq({ "ab", "cdef", "gh" }, rows("ab cdefgh", 4))
	end)

	it("never splits a multi-byte character", function()
		eq({ "ééé", "éé" }, rows("ééééé", 3))
	end)

	it("counts wide characters as two columns", function()
		eq({ "日本", "語" }, rows("日本語", 4))
		eq({ "日", "本", "語" }, rows("日本語", 1))
	end)

	it("returns spans that index the original text", function()
		local text = "alpha beta gamma"
		local spans = wrap.lines(text, 10)
		eq({ { s = 1, e = 10 }, { s = 12, e = 16 } }, spans)
	end)
end)
