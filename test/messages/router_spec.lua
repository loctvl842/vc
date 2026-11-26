local config = require("vc.messages.config")
local router = require("vc.messages.router")

local function resolve(kind, text)
	return router.resolve(config.routes, kind, text, config.passthrough)
end

describe("messages flatten", function()
	it("joins chunks and trims", function()
		eq(
			"E492: Not an editor command: foo",
			router.flatten({ { 0, " E492: " }, { 0, "Not an editor command: foo " } })
		)
	end)
end)

describe("messages resolve", function()
	it("turns E486 into a search warning", function()
		local r = resolve("emsg", "E486: Pattern not found: zzz")
		eq("Pattern not found: zzz", r.text)
		eq(vim.log.levels.WARN, r.level)
		eq({ "search-wrapped" }, r.cancels)
	end)

	it("rewrites forward search wrap", function()
		local r = resolve("wmsg", "search hit BOTTOM, continuing at TOP")
		eq("Hit BOTTOM, continuing at TOP", r.text)
		eq("search-wrapped", r.id)
	end)

	it("rewrites backward search wrap", function()
		eq("Hit TOP, continuing at BOTTOM", resolve("wmsg", "search hit TOP, continuing at BOTTOM").text)
	end)

	it("drops search_count", function()
		eq(true, resolve("search_count", "[2/3]").drop)
	end)

	it("makes the E21 message an error card with its full text", function()
		local r = resolve("emsg", "E21: Cannot make changes, 'modifiable' is off")
		eq("E21: Cannot make changes, 'modifiable' is off", r.text)
		eq(vim.log.levels.ERROR, r.level)
	end)

	it("makes Lua errors and echoerr errors", function()
		eq(vim.log.levels.ERROR, resolve("lua_error", "Error executing Lua callback").level)
		eq(vim.log.levels.ERROR, resolve("echoerr", "boom").level)
	end)

	it("makes other warnings warn cards", function()
		eq(vim.log.levels.WARN, resolve("wmsg", "W10: Changing a readonly file").level)
	end)

	it("keeps every line of a multi-line message", function()
		eq("E5108: Error\nstack line 1", resolve("emsg", "E5108: Error\nstack line 1").text)
	end)

	it("makes any other message an info card", function()
		for _, kind in ipairs({ "echo", "echomsg", "list_cmd", "bufwrite", "undo", "" }) do
			local r = resolve(kind, "hello")
			eq("hello", r.text)
			eq(vim.log.levels.INFO, r.level)
		end
	end)

	it("drops an empty message", function()
		eq(true, resolve("echo", "").drop)
		eq(true, resolve("emsg", "").drop)
	end)

	it("leaves prompts to ui2", function()
		for _, kind in ipairs({ "confirm", "confirm_sub", "return_prompt", "number_prompt" }) do
			eq(nil, resolve(kind, "Replace with x (y/n/a/q/l/^E/^Y)?"))
		end
	end)
end)
