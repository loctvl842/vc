-- nvim --headless -u NONE -l scripts/bench-index.lua [sessions=5000]
-- Builds a synthetic ~/.claude/projects store, then times the index cold, warm, and after one new session.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
local index = require("vc.sessions.index")

local N = tonumber(_G.arg[1]) or 5000
local store = vim.fn.tempname()
local cache_path = store .. "-cache/index.json"
local cwd = vim.fn.tempname()
vim.fn.mkdir(cwd, "p")

local function rec(kind, text, i)
	local ts = ("2026-11-%02dT10:%02d:00.000Z"):format(1 + i % 28, i % 60)
	local msg = kind == "user" and { role = "user", content = text }
		or { role = "assistant", content = { { type = "text", text = text } } }
	return vim.json.encode({ type = kind, isSidechain = false, timestamp = ts, cwd = cwd, message = msg })
end

local function make(i, turns)
	local lines = {
		rec("user", "session " .. i .. " task", i),
		vim.json.encode({ type = "ai-title", aiTitle = "Synthetic session " .. i }),
	}
	local filler = string.rep("lorem ipsum dolor sit amet ", 40)
	for t = 1, turns do
		lines[#lines + 1] = rec("assistant", filler, i)
		lines[#lines + 1] = vim.json.encode({ type = "api-request", params = { blob = filler } })
		lines[#lines + 1] = rec("user", filler, i)
	end
	local dir = ("%s/-proj-%d"):format(store, i % 40)
	vim.fn.mkdir(dir, "p")
	local f = assert(io.open(("%s/%08d.jsonl"):format(dir, i), "w"))
	f:write(table.concat(lines, "\n") .. "\n")
	f:close()
end

local t0 = vim.uv.hrtime()
for i = 1, N do
	make(i, 10) -- ~30 KB
end
for i = N + 1, N + 5 do
	make(i, 12000) -- tens of MB
end
local function ms(t)
	return ("%.0f ms"):format((vim.uv.hrtime() - t) / 1e6)
end
print(("built %d sessions in %s"):format(N + 5, ms(t0)))

local function load()
	local t, done_rows = vim.uv.hrtime(), nil
	local first
	index.load({ root = store, cache_path = cache_path }, function(rows, done)
		first = first or ms(t)
		if done then
			done_rows = rows
		end
	end)
	vim.wait(600000, function()
		return done_rows ~= nil
	end, 5)
	return first, ms(t), #done_rows
end

local first, total, n = load()
print(("cold:        first paint %s, complete %s (%d rows)"):format(first, total, n))
first, total, n = load()
print(("warm:        first paint %s, complete %s (%d rows)"):format(first, total, n))
local f = assert(io.open(store .. "/-proj-1/zz-new.jsonl", "w"))
f:write(rec("user", "brand new", 1) .. "\n")
f:close()
first, total, n = load()
print(("one new:     first paint %s, complete %s (%d rows)"):format(first, total, n))
vim.fn.delete(store, "rf")
vim.fn.delete(vim.fs.dirname(cache_path), "rf")
vim.fn.delete(cwd, "rf")
vim.cmd("qa!")
