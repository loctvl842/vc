local F = require("test.sessions.fixtures")
local T = require("vc.transcript")

local function text_of(lines)
	return table.concat(lines, "\n")
end

describe("transcript", function()
	it("renders dialogue with You / Claude headings", function()
		local src = table.concat({
			F.user("why is CI red?", "t"),
			F.assistant({ { type = "text", text = "checking\nnow" } }, "t"),
		}, "\n")
		local lines, folds = T.render(src)
		eq({ "## You", "", "why is CI red?", "", "## Claude", "", "checking", "now" }, lines)
		eq({}, folds)
	end)

	it("keeps tool calls, results and thinking in full and folds each run", function()
		local src = table.concat({
			F.user("go", "t"),
			F.assistant({ { type = "thinking", thinking = "hmm" }, { type = "text", text = "on it" } }, "t"),
			F.assistant({ { type = "tool_use", id = "1", name = "Read", input = { file = "a.lua" } } }, "t"),
			F.tool_result("t"),
			F.assistant({ { type = "tool_use", id = "2", name = "Edit", input = {} } }, "t"),
			F.tool_result("t"),
			F.assistant({ { type = "text", text = "done" } }, "t"),
		}, "\n")
		local lines, folds = T.render(src)
		local text = text_of(lines)
		truthy(text:find("tool: Read", 1, true))
		truthy(text:find('{"file":"a.lua"}', 1, true))
		truthy(text:find("result:", 1, true))
		truthy(text:find("hmm", 1, true))
		eq(2, #folds)
		eq("▸ thinking", folds[1].label)
		eq("▸ 2 tool calls", folds[2].label)
		eq("thinking:", lines[folds[1].start])
		eq("  hmm", lines[folds[1].stop])
		eq("tool: Read", lines[folds[2].start])
		truthy(folds[2].stop < #lines) -- "done" comes after the fold
	end)

	it("skips sidechain, meta and bookkeeping records", function()
		local src = table.concat({
			F.title("T"),
			F.user("meta", "t", nil, { isMeta = true }),
			F.user("side", "t", nil, { isSidechain = true }),
			F.user("real", "t"),
		}, "\n")
		local lines = T.render(src)
		eq({ "## You", "", "real" }, lines)
	end)

	it("handles array text content and images", function()
		local src = F.user({ { type = "text", text = "look" }, { type = "image", source = {} } }, "t")
		local lines = T.render(src)
		truthy(text_of(lines):find("look", 1, true))
		truthy(text_of(lines):find("[image]", 1, true))
	end)

	it("never truncates a very large conversation", function()
		local parts = {}
		for i = 1, 2000 do
			parts[#parts + 1] = F.user("question " .. i, "t")
			parts[#parts + 1] = F.assistant({ { type = "text", text = "answer " .. i } }, "t")
		end
		parts[#parts + 1] = F.assistant({ { type = "text", text = "THE END" } }, "t")
		local lines = T.render(table.concat(parts, "\n"))
		eq("THE END", lines[#lines])
	end)

	it("render_file yields the same result asynchronously", function()
		local d = tmpdir()
		local parts = {}
		for i = 1, 1500 do
			parts[#parts + 1] = F.user("q" .. i, "t")
		end
		write_file(d .. "/s.jsonl", parts)
		local row = { title = "Big", cwd = "/x", msg_count = 1500 }
		local got
		T.render_file(d .. "/s.jsonl", row, function(lines, folds)
			got = { lines, folds }
		end)
		wait(function()
			return got ~= nil
		end)
		eq("# Big", got[1][1])
		eq("/x - 1500 messages", got[1][2])
		eq("q1500", got[1][#got[1]])
	end)
end)
