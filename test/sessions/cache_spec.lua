local cache = require("vc.sessions.cache")

describe("cache", function()
	it("round-trips rows", function()
		local p = tmpdir() .. "/c/index.json"
		local rows = { ["/a.jsonl"] = { id = "a", size = 1, mtime = 2 } }
		truthy(cache.write(p, rows))
		eq(rows, cache.read(p))
	end)

	it("returns empty for missing, corrupt and other-version files", function()
		local d = tmpdir()
		eq({}, cache.read(d .. "/none.json"))
		write_file(d .. "/bad.json", "{oops")
		eq({}, cache.read(d .. "/bad.json"))
		write_file(d .. "/old.json", '{"version":0,"rows":{"x":{}}}')
		eq({}, cache.read(d .. "/old.json"))
	end)
end)
