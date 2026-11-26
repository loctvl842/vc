local F = require("test.sessions.fixtures")
local T = require("vc.transcript")

local function text_of(lines)
	return table.concat(lines, "\n")
end

describe("transcript", function()
	it("draws prompts with a chevron and replies with a dot", function()
		local src = table.concat({
			F.user("why is CI red?", "t"),
			F.assistant({ { type = "text", text = "checking\nnow" } }, "t"),
		}, "\n")
		local lines, folds, marks = T.render(src)
		eq({ "> why is CI red?", "", "● checking", "  now" }, lines)
		eq({}, folds)
		local function has(l, hl, whole)
			for _, m in ipairs(marks) do
				if m.l == l and m.hl == hl and (not whole or m.line) then
					return true
				end
			end
			return false
		end
		truthy(has(1, "Prompt"))
		truthy(has(1, "Band", true))
		truthy(has(3, "Dot"))
	end)

	it("shows a call on one line with its result underneath", function()
		local src = table.concat({
			F.user("go", "t"),
			F.assistant({ { type = "tool_use", id = "a", name = "Bash", input = { command = "npm test" } } }, "t"),
			F.tool_result("t", nil, { id = "a", text = "12 passed" }),
			F.assistant({ { type = "text", text = "done" } }, "t"),
		}, "\n")
		local lines, folds = T.render(src)
		eq({ "> go", "", "● Bash(npm test)", "  ⎿  12 passed", "", "● done" }, lines)
		eq({}, folds)
	end)

	it("pairs parallel calls with their own results", function()
		local src = table.concat({
			F.assistant({
				{ type = "tool_use", id = "a", name = "Read", input = { file_path = "/x/a.lua" } },
				{ type = "tool_use", id = "b", name = "Read", input = { file_path = "/x/b.lua" } },
			}, "t", "/x"),
			F.tool_result("t", nil, { id = "b", text = "B" }),
			F.tool_result("t", nil, { id = "a", text = "A" }),
		}, "\n")
		local lines = T.render(src)
		eq({ "● Read(a.lua)", "  ⎿  A", "", "● Read(b.lua)", "  ⎿  B" }, lines)
	end)

	it("folds the rest of a long result and labels what is hidden", function()
		local out = {}
		for i = 1, 9 do
			out[i] = "line " .. i
		end
		local src = table.concat({
			F.assistant({ { type = "tool_use", id = "a", name = "Bash", input = { command = "ls" } } }, "t"),
			F.tool_result("t", nil, { id = "a", text = table.concat(out, "\n") }),
		}, "\n")
		local lines, folds = T.render(src)
		eq(1, #folds)
		eq("     … +6 lines", folds[1].label)
		eq("     line 4", lines[folds[1].start])
		eq("     line 9", lines[folds[1].stop])
		eq(#lines, folds[1].stop)
	end)

	it("does not fold a result that is only one line too long", function()
		local src = table.concat({
			F.assistant({ { type = "tool_use", id = "a", name = "Bash", input = { command = "ls" } } }, "t"),
			F.tool_result("t", nil, { id = "a", text = "1\n2\n3\n4" }),
		}, "\n")
		local lines, folds = T.render(src)
		eq({}, folds)
		eq("     4", lines[#lines])
	end)

	it("marks a failed result as an error", function()
		local src = table.concat({
			F.assistant({ { type = "tool_use", id = "a", name = "Bash", input = { command = "rm x" } } }, "t"),
			F.tool_result("t", nil, { id = "a", text = "no such file", is_error = true }),
		}, "\n")
		local _, _, marks = T.render(src)
		local found
		for _, m in ipairs(marks) do
			found = found or (m.hl == "Error" and m.l == 2)
		end
		truthy(found)
	end)

	it("shows an edit as a colored diff under its call", function()
		local rec = {
			structuredPatch = {
				{ oldStart = 3, oldLines = 2, newStart = 3, newLines = 2, lines = { " keep", "-old", "+new" } },
			},
		}
		local src = table.concat({
			F.assistant(
				{ { type = "tool_use", id = "a", name = "Edit", input = { file_path = "/x/a.lua" } } },
				"t",
				"/x"
			),
			F.tool_result("t", nil, { id = "a", text = "updated", rec = rec }),
		}, "\n")
		local lines, _, marks = T.render(src)
		eq({
			"● Edit(a.lua)",
			"  ⎿  Updated with 1 addition and 1 removal",
			"     3  keep",
			"     4 -old",
			"     4 +new",
		}, lines)
		local hl = {}
		for _, m in ipairs(marks) do
			hl[m.l .. m.hl] = m
		end
		truthy(hl["4DiffDelete"].line)
		truthy(hl["5DiffAdd"].line)
		eq({ 5, 8 }, { hl["5DiffAddSign"].c, hl["5DiffAddSign"].e })
	end)

	it("folds a very long diff after diff_lines", function()
		local ls = {}
		for i = 1, 40 do
			ls[i] = "+l" .. i
		end
		local rec = { structuredPatch = { { oldStart = 1, oldLines = 0, newStart = 1, newLines = 40, lines = ls } } }
		local src = table.concat({
			F.assistant({ { type = "tool_use", id = "a", name = "Edit", input = {} } }, "t"),
			F.tool_result("t", nil, { id = "a", text = "ok", rec = rec }),
		}, "\n")
		local lines, folds = T.render(src)
		eq(1, #folds)
		eq("     … +16 lines", folds[1].label)
		eq(#lines, folds[1].stop)
	end)

	it("falls back to the result text when an error replaces the edit", function()
		local rec =
			{ structuredPatch = { { oldStart = 1, oldLines = 1, newStart = 1, newLines = 1, lines = { "-a", "+b" } } } }
		local src = table.concat({
			F.assistant({ { type = "tool_use", id = "a", name = "Edit", input = {} } }, "t"),
			F.tool_result("t", nil, { id = "a", text = "String to replace not found", is_error = true, rec = rec }),
		}, "\n")
		eq({ "● Edit", "  ⎿  String to replace not found" }, (T.render(src)))
	end)

	it("folds thinking behind a one-line label", function()
		local src = table.concat({
			F.assistant({ { type = "thinking", thinking = "hmm\nok" }, { type = "text", text = "on it" } }, "t"),
		}, "\n")
		local lines, folds = T.render(src)
		eq({ "✻ Thinking…", "  hmm", "  ok", "", "● on it" }, lines)
		eq({ { start = 1, stop = 3, label = "✻ Thinking…" } }, folds)
	end)

	it("keeps a result that has no call and a call that never got a result", function()
		local src = table.concat({
			F.tool_result("t", nil, { id = "zzz", text = "orphan" }),
			F.assistant({ { type = "tool_use", id = "a", name = "Bash", input = { command = "sleep" } } }, "t"),
		}, "\n")
		eq({ "  ⎿  orphan", "", "● Bash(sleep)" }, T.render(src))
	end)

	it("skips sidechain, meta and bookkeeping records", function()
		local src = table.concat({
			F.title("T"),
			F.user("meta", "t", nil, { isMeta = true }),
			F.user("side", "t", nil, { isSidechain = true }),
			F.user("real", "t"),
		}, "\n")
		eq({ "> real" }, (T.render(src)))
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
		eq("● THE END", lines[#lines])
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
		eq("/x - 1500 messages", got[1][1])
		eq("> q1500", got[1][#got[1]])
	end)

	it("does not fold empty thinking blocks", function()
		local src = table.concat({
			F.user("go", "t"),
			F.assistant({ { type = "thinking", thinking = "  " }, { type = "text", text = "ok" } }, "t"),
		}, "\n")
		local _, folds = T.render(src)
		eq({}, folds)
	end)
end)
