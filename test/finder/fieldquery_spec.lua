local fieldquery = require("vc.finder.fieldquery")

describe("fieldquery", function()
	it("reads one term and leaves no rest", function()
		local q = fieldquery.parse("cwd:jarvix")
		assert(#q.terms == 1 and q.terms[1].name == "cwd" and q.terms[1].value == "jarvix")
		assert(not q.terms[1].quoted and q.rest == "")
	end)

	it("splits terms from the normal query, wherever the terms sit", function()
		local q = fieldquery.parse("startup cwd:jarvix  title:nvim now")
		assert(#q.terms == 2 and q.terms[1].name == "cwd" and q.terms[2].name == "title", vim.inspect(q))
		assert(q.rest == "startup now", q.rest)
	end)

	it("keeps a term with no value out of the terms, and still reports its prefix", function()
		local q = fieldquery.parse("cwd:")
		assert(#q.terms == 0 and q.rest == "")
		assert(#q.prefixes == 1 and q.prefixes[1].s == 1 and q.prefixes[1].e == 4)
	end)

	it("treats an unknown name, a capital and a URL as normal words", function()
		for _, text in ipairs({ "ticket:42", "Cwd:x", "https://example.com", "a:b" }) do
			local q = fieldquery.parse(text)
			assert(#q.terms == 0 and #q.prefixes == 0 and q.rest == text, text)
		end
	end)

	it("recognises a name only at the start of a word", function()
		local q = fieldquery.parse("xcwd:a mycwd:b")
		assert(#q.terms == 0 and q.rest == "xcwd:a mycwd:b")
	end)

	it("reads a quoted value with spaces", function()
		local q = fieldquery.parse('title:"fix login" x')
		assert(q.terms[1].value == "fix login" and q.terms[1].quoted and q.rest == "x", vim.inspect(q))
	end)

	it("reads an unterminated quote to the end of the text", function()
		local q = fieldquery.parse('title:"fix log')
		assert(q.terms[1].value == "fix log" and q.terms[1].quoted and q.rest == "")
	end)

	it("drops a quoted empty value", function()
		local q = fieldquery.parse('title:"" x')
		assert(#q.terms == 0 and q.rest == "x" and #q.prefixes == 1)
	end)

	it("keeps two terms for the same field", function()
		local q = fieldquery.parse("cwd:work cwd:jarvix")
		assert(#q.terms == 2 and q.terms[1].value == "work" and q.terms[2].value == "jarvix")
	end)

	it("points each prefix at the name and its colon", function()
		local q = fieldquery.parse("a cwd:jarvix msg:x")
		assert(q.prefixes[1].s == 3 and q.prefixes[1].e == 6, vim.inspect(q.prefixes))
		assert(q.prefixes[2].s == 14 and q.prefixes[2].e == 17, vim.inspect(q.prefixes))
	end)

	it("keeps a colon inside a value", function()
		local q = fieldquery.parse("cwd:a:b")
		assert(q.terms[1].value == "a:b")
	end)
end)
