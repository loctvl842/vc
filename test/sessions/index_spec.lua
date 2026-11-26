local F = require("test.sessions.fixtures")
local index = require("vc.sessions.index")

local function load(store, cache_path)
	local out, done = nil, false
	index.load({ root = store.root, cache_path = cache_path }, function(rows, d)
		out, done = rows, d
	end)
	wait(function()
		return done
	end)
	return out
end

local function snapshot(root)
	local t = {}
	for _, f in ipairs(vim.fn.glob(root .. "/**/*", false, true)) do
		local s = vim.uv.fs_stat(f)
		t[f] = s.type == "file" and (s.size .. ":" .. s.mtime.sec) or "dir"
	end
	return t
end

describe("index", function()
	it("lists top-level sessions newest first, ignores subagent files", function()
		local store = F.store()
		local rows = load(store, tmpdir() .. "/idx.json")
		local ids = vim.tbl_map(function(r)
			return r.id
		end, rows)
		eq(4, #ids)
		-- the empty file has no timestamps, so it takes its mtime (now) and sorts first
		eq({ "empty", "titled", "untitled", "corrupt" }, ids)
	end)

	it("marks whether the project folder still exists", function()
		local store = F.store()
		local by = {}
		for _, r in ipairs(load(store, tmpdir() .. "/idx.json")) do
			by[r.id] = r
		end
		eq(true, by.titled.cwd_exists)
		eq(false, by.untitled.cwd_exists)
	end)

	it("uses the cache when files are unchanged and rescans changed ones", function()
		local store = F.store()
		local cp = tmpdir() .. "/idx.json"
		load(store, cp)
		local calls = 0
		index.load({ root = store.root, cache_path = cp }, function(_, done)
			calls = calls + 1
			eq(true, done) -- nothing to rescan: single call
		end)
		eq(1, calls)
		write_file(store.proj .. "new.jsonl", { F.user("brand new", "2026-11-27T00:00:00.000Z", store.alive) })
		local rows = load(store, cp)
		eq("new", rows[1].id)
	end)

	it("drops sessions whose file vanished", function()
		local store = F.store()
		local cp = tmpdir() .. "/idx.json"
		load(store, cp)
		os.remove(store.proj .. "corrupt.jsonl")
		local ids = vim.tbl_map(function(r)
			return r.id
		end, load(store, cp))
		eq(false, vim.tbl_contains(ids, "corrupt"))
	end)

	it("never writes under the store", function()
		local store = F.store()
		local before = snapshot(store.root)
		load(store, tmpdir() .. "/idx.json")
		eq(before, snapshot(store.root))
	end)

	it("rescans many new files in batches and delivers every row", function()
		local store = F.store()
		for i = 1, 400 do
			write_file(
				store.proj .. ("bulk%d.jsonl"):format(i),
				{ F.user("bulk " .. i, "2026-10-01T00:00:00.000Z", store.alive) }
			)
		end
		local done = false
		index.load({ root = store.root, cache_path = tmpdir() .. "/idx.json" }, function(rows, d)
			if d then
				done = true
				eq(404, #rows)
			end
		end)
		wait(function()
			return done
		end, 10000)
	end)

	it("a cancelled load delivers and caches nothing", function()
		local store = F.store()
		for i = 1, 100 do
			write_file(store.proj .. ("c%d.jsonl"):format(i), { F.user("x", "2026-10-01T00:00:00.000Z", store.alive) })
		end
		local cp = tmpdir() .. "/idx.json"
		local delivered = false
		local cancel = index.load({ root = store.root, cache_path = cp }, function(_, done)
			delivered = delivered or done
		end)
		cancel()
		vim.wait(300)
		eq(false, delivered)
		eq(0, vim.fn.filereadable(cp))
	end)
end)
