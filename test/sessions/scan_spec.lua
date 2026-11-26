local F = require("test.sessions.fixtures")
local scan = require("vc.sessions.scan")

local function row(store, name)
	local path = store.proj .. name .. ".jsonl"
	return scan.scan_file(path, vim.uv.fs_stat(path))
end

describe("scan", function()
	local store = F.store()

	it("uses the last ai-title, project from cwd, full-conversation count", function()
		local r = row(store, "titled")
		eq("Fix flaky login test v2", r.title)
		eq("api-server", r.project)
		eq(store.alive, r.cwd)
		eq(4, r.msg_count) -- user, assistant, tool_result, assistant
		eq(scan.parse_ts("2026-11-26T10:05:00.000Z"), r.last_ts)
		eq("titled", r.id)
	end)

	it("falls back to the first prompt, stripped and one line", function()
		local r = row(store, "untitled")
		eq("hello world", r.title)
		eq("proto", r.project)
	end)

	it("lists an empty file as untitled with the dir name as project", function()
		local r = row(store, "empty")
		eq("(untitled)", r.title)
		eq(0, r.msg_count)
		eq("-proj-a", r.project)
		eq(r.mtime, r.last_ts)
	end)

	it("skips corrupt lines", function()
		local r = row(store, "corrupt")
		eq("only prompt", r.title)
	end)

	it("parses timestamps as UTC epoch", function()
		eq(0, scan.parse_ts("1970-01-01T00:00:00Z"))
		eq(1767225600, scan.parse_ts("2026-01-01T00:00:00.000Z"))
		eq(nil, scan.parse_ts("nope"))
	end)
end)
