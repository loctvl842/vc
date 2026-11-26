local md = require("vc.markdown")

--- Text covered by the marks named `hl`, per line.
local function styled(lines, marks, hl)
	local out = {}
	for _, m in ipairs(marks) do
		if m.hl == hl and m.c then
			out[#out + 1] = lines[m.l]:sub(m.c + 1, m.e)
		end
	end
	return out
end

describe("markdown", function()
	it("drops inline markers and marks the styled text", function()
		local lines, marks = md.render("a **bold** and *it* and `code` and ~~gone~~ end")
		eq({ "a bold and it and code and gone end" }, lines)
		eq({ "bold" }, styled(lines, marks, "Bold"))
		eq({ "it" }, styled(lines, marks, "Italic"))
		eq({ "code" }, styled(lines, marks, "Code"))
		truthy(vim.tbl_contains(styled(lines, marks, "Strike"), "gone"))
	end)

	it("nests emphasis", function()
		local lines, marks = md.render("**bold and *both***")
		eq({ "bold and both" }, lines)
		eq({ "bold and both" }, styled(lines, marks, "Bold"))
		eq({ "both" }, styled(lines, marks, "Italic"))
	end)

	it("shows link text underlined and hides the address", function()
		local lines, marks = md.render("see [the docs](https://x.dev) now, or <https://y.dev>")
		eq({ "see the docs now, or https://y.dev" }, lines)
		eq({ "the docs", "https://y.dev" }, styled(lines, marks, "Link"))
	end)

	it("keeps unresolved references and escapes readable", function()
		eq({ "[ref] and * star" }, (md.render([[[ref] and \* star]])))
	end)

	it("drops heading markers and styles the heading", function()
		local lines, marks = md.render("# Big\n\n## Small\n\ntext")
		eq({ "Big", "", "Small", "", "text" }, lines)
		eq({ "Big" }, styled(lines, marks, "Heading1"))
		eq({ "Small" }, styled(lines, marks, "Heading"))
	end)

	it("renders bullet, numbered and nested lists with hanging text", function()
		local lines = md.render("- one\n  - nested\n- two\n\n1. first\n2. second")
		eq({ "• one", "  • nested", "• two", "", "1. first", "2. second" }, lines)
	end)

	it("renders task lists", function()
		eq({ "• ☐ todo", "• ☒ done" }, (md.render("- [ ] todo\n- [x] done")))
	end)

	it("renders a block quote with a bar on each line", function()
		local lines, marks = md.render("> quoted *text*\n> more")
		eq({ "▎ quoted text", "▎ more" }, lines)
		eq({ "▎", "▎" }, styled(lines, marks, "QuoteBar"))
		truthy(#styled(lines, marks, "Quote") >= 2)
	end)

	it("renders fenced code with a dim language label and no fences", function()
		local lines, marks = md.render("before\n\n```lua\nlocal x = 1\n\nreturn x\n```\n\nafter")
		eq({ "before", "", "  lua", "  local x = 1", "", "  return x", "", "after" }, lines)
		eq({ "lua" }, styled(lines, marks, "CodeLang"))
		eq({ "local x = 1", "return x" }, styled(lines, marks, "CodeBlock"))
	end)

	it("renders code without a language and keeps its indentation", function()
		eq({ "  a", "    b" }, (md.render("```\na\n  b\n```")))
	end)

	it("renders a thematic break as a rule", function()
		local lines = md.render("a\n\n---\n\nb")
		eq("a", lines[1])
		eq(string.rep("─", 24), lines[3])
		eq("b", lines[5])
	end)

	it("keeps soft line breaks as lines", function()
		eq({ "one", "two", "three" }, (md.render("one\ntwo  \nthree")))
	end)

	it("never loses text it cannot style", function()
		local lines = md.render("<div>raw html</div>\n\nplain")
		truthy(table.concat(lines, "\n"):find("raw html", 1, true))
		truthy(table.concat(lines, "\n"):find("plain", 1, true))
	end)

	it("leaves unclosed markers as written", function()
		eq({ "a **b and `c" }, (md.render("a **b and `c")))
	end)

	it("returns empty text as one empty line", function()
		eq({ "" }, (md.render("")))
	end)
end)
