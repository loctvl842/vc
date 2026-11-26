-- Builds a fake ~/.claude/projects store in a temp dir.
local M = {}

local function j(t)
	return vim.json.encode(t)
end

function M.user(text, ts, cwd, extra)
	return j(vim.tbl_extend("force", {
		type = "user",
		isSidechain = false,
		timestamp = ts,
		cwd = cwd,
		sessionId = "s",
		message = { role = "user", content = text },
	}, extra or {}))
end

function M.assistant(blocks, ts, cwd)
	return j({
		type = "assistant",
		isSidechain = false,
		timestamp = ts,
		cwd = cwd,
		sessionId = "s",
		message = { role = "assistant", content = blocks },
	})
end

function M.tool_result(ts, cwd)
	return j({
		type = "user",
		isSidechain = false,
		timestamp = ts,
		cwd = cwd,
		sessionId = "s",
		message = { role = "user", content = { { type = "tool_result", tool_use_id = "t1", content = "ok" } } },
	})
end

function M.title(t)
	return j({ type = "ai-title", aiTitle = t, sessionId = "s" })
end

--- Make a store with the standard sessions; returns root plus useful paths.
function M.store()
	local root = tmpdir()
	local alive = tmpdir() .. "/api-server"
	vim.fn.mkdir(alive, "p")
	local gone = "/no/such/dir/proto"
	local P = root .. "/-proj-a/"
	write_file(P .. "titled.jsonl", {
		M.user("fix the login test", "2026-11-26T10:00:00.000Z", alive),
		M.assistant(
			{ { type = "text", text = "looking" }, { type = "tool_use", id = "t1", name = "Read", input = {} } },
			"2026-11-26T10:00:05.000Z",
			alive
		),
		M.tool_result("2026-11-26T10:00:06.000Z", alive),
		M.assistant({ { type = "text", text = "done" } }, "2026-11-26T10:05:00.000Z", alive),
		M.title("Fix flaky login test"),
		M.title("Fix flaky login test v2"),
	})
	write_file(P .. "untitled.jsonl", {
		M.user("<command-name>/foo</command-name> hello   world", "2026-11-25T09:00:00.000Z", gone),
		M.assistant({ { type = "text", text = "hi" } }, "2026-11-25T09:00:01.000Z", gone),
	})
	write_file(P .. "empty.jsonl", "")
	write_file(P .. "corrupt.jsonl", {
		"{not json",
		M.user("only prompt", "2026-11-20T00:00:00.000Z", alive),
		'{"type":"user" truncated',
	})
	write_file(P .. "titled/subagents/agent-1.jsonl", { M.user("sub", "2026-11-26T11:00:00.000Z", alive) })
	return { root = root, alive = alive, gone = gone, proj = P }
end

return M
