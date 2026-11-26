local config = require("vc.toast.config")
local Record = require("vc.toast.record")

describe("toast record", function()
	before_each(function()
		config.setup({})
		vim.o.columns = 100
	end)

	it("flattens a multi-line message to one line", function()
		eq("one two three", Record(1, "one\ntwo\nthree").message)
		eq("a b", Record(1, { "a", "b" }).message)
	end)

	it("normalizes the level and picks its icon", function()
		local r = Record(1, "hi", vim.log.levels.INFO)
		eq("INFO", r.level)
		eq(config.icons.INFO, r.icon)
	end)

	it("is one row tall and as wide as its text and icon", function()
		local r = Record(1, "written to disk")
		local w, h = r:dimensions()
		eq(1, h)
		eq(#"written to disk" + 1 + vim.fn.strdisplaywidth(r.icon), w)
	end)

	it("is never narrower than 10 columns", function()
		eq(10, (Record(1, "a"):dimensions()))
	end)

	it("is at most 60% of the terminal", function()
		local w = Record(1, string.rep("x", 200)):dimensions()
		eq(60, w)
		vim.o.columns = 40
		eq(24, (Record(1, string.rep("x", 200)):dimensions()))
	end)

	it("makes room for the count badge", function()
		local r = Record(1, "written to disk")
		local before = r:dimensions()
		r.count = 12
		eq(before + 1 + #"x12", (r:dimensions()))
	end)

	it("labels the count up to x99, then x99+", function()
		eq("x2", Record.count_label(2))
		eq("x99", Record.count_label(99))
		eq("x99+", Record.count_label(100))
	end)

	it("merges only identical, auto-dismissing toasts", function()
		eq(Record(1, "a").key, Record(2, "a").key)
		truthy(Record(1, "a").key ~= Record(2, "b").key)
		eq(true, Record(1, "a").mergeable)
		eq(false, Record(1, "a", nil, { timeout = false }).mergeable)
		eq(false, Record(1, "a", nil, { merge = false }).mergeable)
	end)
end)
