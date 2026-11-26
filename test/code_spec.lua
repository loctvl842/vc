local code = require("vc.code")

local function styled(src, marks, hl)
	local lines, out = vim.split(src, "\n", { plain = true }), {}
	for _, m in ipairs(marks) do
		if m.hl == hl then
			out[#out + 1] = lines[m.l]:sub(m.c + 1, m.e)
		end
	end
	return out
end

describe("code", function()
	local src = 'local function wait(n) -- poll\n  return "ok", 42\nend'

	it("colors keywords, strings, numbers, comments and functions of a Lua block", function()
		local marks = code.marks(src, "lua")
		truthy(vim.tbl_contains(styled(src, marks, "CodeKeyword"), "local"))
		truthy(vim.tbl_contains(styled(src, marks, "CodeKeyword"), "return"))
		truthy(vim.tbl_contains(styled(src, marks, "CodeString"), '"ok"'))
		eq({ "42" }, styled(src, marks, "CodeNumber"))
		eq({ "-- poll" }, styled(src, marks, "CodeComment"))
		truthy(vim.tbl_contains(styled(src, marks, "CodeFunction"), "wait"))
	end)

	it("resolves language aliases and is case blind", function()
		truthy(#code.marks("local x = 1", "Lua") > 0)
		truthy(#code.marks("echo 'hi'", "sh") > 0 or not pcall(vim.treesitter.language.add, "bash"))
	end)

	it("gives no marks for an unknown language or none", function()
		eq({}, code.marks("whatever", "no-such-language"))
		eq({}, code.marks("local x = 1", nil))
		eq({}, code.marks("local x = 1", ""))
	end)

	it("cuts a multi-line node (block comment) into one mark per line", function()
		local text = "--[[ a\nb ]]\nlocal x"
		local comments = styled(text, code.marks(text, "lua"), "CodeComment")
		eq({ "--[[ a", "b ]]" }, comments)
	end)

	it("leaves a huge block plain", function()
		eq({}, code.marks(string.rep("local x = 1\n", 5000), "lua"))
	end)
end)
