local toolline = require("vc.toolline")

local function marks_on(d, l)
	local out = {}
	for _, m in ipairs(d.marks) do
		if m.l == l then
			out[#out + 1] = m.hl
		end
	end
	return out
end

describe("toolline", function()
	describe("call", function()
		it("shows the most telling argument", function()
			local name, args = toolline.call("Bash", { command = "npm test" })
			eq("Bash", name)
			eq("(npm test)", args)
			eq("(a.lua)", select(2, toolline.call("Read", { file_path = "/x/a.lua" }, "/x")))
			eq("(/y/a.lua)", select(2, toolline.call("Read", { file_path = "/y/a.lua" }, "/x")))
			eq("(foo)", select(2, toolline.call("Grep", { pattern = "foo", path = "/x" })))
		end)

		it("collapses newlines and truncates long arguments", function()
			local _, args = toolline.call("Bash", { command = "echo 1\necho 2" })
			eq("(echo 1 echo 2)", args)
			local _, long = toolline.call("Bash", { command = string.rep("a", 200) })
			eq(80 + 2, vim.fn.strchars(long))
			truthy(long:find("…)", 1, true))
		end)

		it("reads MCP tools as server - tool (MCP)", function()
			eq("jarvix - mesh_send (MCP)", (toolline.call("mcp__jarvix__mesh_send", {})))
		end)

		it("has no arguments when the input says nothing", function()
			eq("", select(2, toolline.call("TodoWrite", { todos = {} })))
			eq("", select(2, toolline.call("Bash", nil)))
		end)
	end)

	describe("result_lines", function()
		it("splits text, strips escapes and trailing blank lines", function()
			eq({ "a", "b" }, toolline.result_lines({ text = "\27[31ma\27[0m\r\nb\n\n" }))
		end)

		it("says so when there is no output", function()
			eq({ "(No content)" }, toolline.result_lines({ text = "" }))
		end)
	end)

	describe("content_text", function()
		it("flattens strings and block arrays, with images as a placeholder", function()
			eq("plain", toolline.content_text("plain"))
			eq(
				"a\n[image]\nb",
				toolline.content_text({
					{ type = "text", text = "a" },
					{ type = "image" },
					{ type = "text", text = "b" },
				})
			)
			eq("", toolline.content_text(nil))
		end)
	end)

	describe("diff", function()
		local patch = {
			structuredPatch = {
				{
					oldStart = 11,
					oldLines = 3,
					newStart = 11,
					newLines = 4,
					lines = { "   keep", "-  old", "+  new", "+  more", "   tail" },
				},
			},
		}

		it("numbers lines and counts additions and removals", function()
			local d = toolline.diff(patch)
			eq("Updated with 2 additions and 1 removal", d.summary)
			eq({ "11    keep", "12 -  old", "12 +  new", "13 +  more", "14    tail" }, d.lines)
		end)

		it("numbers context after added lines by the new file, so numbers never go backwards", function()
			local d = toolline.diff({
				structuredPatch = {
					{
						oldStart = 10,
						oldLines = 3,
						newStart = 10,
						newLines = 5,
						lines = { " c1", "+n1", "+n2", " c2", " c3" },
					},
				},
			})
			eq({ "10  c1", "11 +n1", "12 +n2", "13  c2", "14  c3" }, d.lines)
		end)

		it("paints removed and added lines and their gutters", function()
			local d = toolline.diff(patch)
			eq({ "DiffDelete", "DiffDeleteSign" }, marks_on(d, 2))
			eq({ "DiffAdd", "DiffAddSign" }, marks_on(d, 3))
			eq({ "ToolArgs" }, marks_on(d, 1))
		end)

		it("separates hunks and keeps one number width", function()
			local d = toolline.diff({
				structuredPatch = {
					{ oldStart = 8, oldLines = 1, newStart = 8, newLines = 1, lines = { " a" } },
					{ oldStart = 98, oldLines = 2, newStart = 98, newLines = 2, lines = { "-b", "+c" } },
				},
			})
			eq({ "  8  a", "    …", " 98 -b", " 98 +c" }, d.lines)
		end)

		it("shows a new file as written lines", function()
			local d = toolline.diff({ type = "create", content = "one\ntwo\n", structuredPatch = {} })
			eq("Wrote 2 lines", d.summary)
			eq({ "1 +one", "2 +two" }, d.lines)
		end)

		it("has nothing to show without a usable patch", function()
			eq(nil, toolline.diff(nil))
			eq(nil, toolline.diff({ stdout = "x" }))
			eq(nil, toolline.diff({ structuredPatch = {} }))
			eq(nil, toolline.diff({ structuredPatch = { { oldStart = "x" } } })) -- malformed: no throw
		end)
	end)
end)
