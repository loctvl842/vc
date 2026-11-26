local config = require("vc.notify.config")
local Record = require("vc.notify.record")

describe("notify record", function()
	before_each(function()
		config.setup({})
		vim.o.columns = 100
	end)

	it("splits a string message on newlines and normalizes the level", function()
		local r = Record(1, "a\nb", vim.log.levels.WARN)
		eq({ "a", "b" }, r.message)
		eq("WARN", r.level)
	end)

	it("keeps short lines as they are", function()
		local r = Record(1, { "one", "two" })
		eq({ "one", "two" }, r:lines(40))
		local w, h = r:dimensions()
		eq(80, w)
		eq(3, h) -- title row + 2 lines
	end)

	it("keeps an empty line as an empty row", function()
		eq({ "a", "", "b" }, Record(1, "a\n\nb"):lines(40))
	end)

	it("wraps a long line to the card width", function()
		local r = Record(1, "aaaa bbbb cccc")
		eq({ "aaaa", "bbbb", "cccc" }, r:lines(4))
	end)

	it("cuts the message after max_height rows", function()
		local lines = {}
		for i = 1, 25 do
			lines[i] = "line " .. i
		end
		local r = Record(1, lines)
		eq(10, #r:lines(40))
		eq("line 10", r:lines(40)[10])
		local _, h = r:dimensions()
		eq(11, h)
	end)

	it("re-wraps when the width changes", function()
		local r = Record(1, "aaaa bbbb")
		eq(2, #r:lines(4))
		eq(1, #r:lines(20))
	end)
end)

describe("notify config width", function()
	before_each(function()
		config.setup({})
	end)

	it("is the configured width on a wide terminal", function()
		vim.o.columns = 200
		eq(80, config.width())
	end)

	it("leaves room for the border on a narrow terminal", function()
		vim.o.columns = 40
		eq(38, config.width())
	end)
end)
