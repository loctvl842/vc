-- nvim --headless -u NONE -l scripts/bench-preview.lua [messages=5000]
-- Renders a synthetic session (markdown replies, code, tables, tool calls, diffs) the way the preview does,
-- and times the whole render and how soon the first screen is ready.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local transcript = require("vc.transcript")

local N = tonumber(_G.arg[1]) or 5000
local REPLY = table.concat({
	"## Findings",
	"",
	"The **timing issue** is in `form.lua`; see [the docs](https://x.dev).",
	"",
	"- wait for the form",
	"- re-run on CI",
	"",
	"```lua",
	"local function wait(form)",
	"  return form:ready() -- poll",
	"end",
	"```",
	"",
	"| name | value |",
	"|------|-------|",
	"| a    | 1     |",
}, "\n")

local function rec(kind, content)
	return vim.json.encode({
		type = kind,
		isSidechain = false,
		cwd = "/x",
		message = { role = kind, content = content },
	})
end

local lines = {}
for i = 1, N do
	lines[#lines + 1] = rec("user", "question " .. i)
	lines[#lines + 1] = rec("assistant", { { type = "text", text = REPLY } })
	local id = "t" .. i
	lines[#lines + 1] =
		rec("assistant", { { type = "tool_use", id = id, name = "Edit", input = { file_path = "/x/a.lua" } } })
	lines[#lines + 1] = vim.json.encode({
		type = "user",
		isSidechain = false,
		toolUseResult = {
			structuredPatch = {
				{ oldStart = 1, oldLines = 2, newStart = 1, newLines = 2, lines = { " a", "-b", "+c" } },
			},
		},
		message = { role = "user", content = { { type = "tool_result", tool_use_id = id, content = "ok" } } },
	})
end
local path = vim.fn.tempname() .. ".jsonl"
vim.fn.writefile(lines, path)
print(("session: %d messages, %d records, %.1f MB"):format(N * 2, #lines, vim.uv.fs_stat(path).size / 1e6))

local t0 = vim.uv.hrtime()
local out, folds, marks = transcript.render(table.concat(lines, "\n"))
print(
	("sync render:   %6.0f ms  (%d lines, %d marks, %d folds)"):format(
		(vim.uv.hrtime() - t0) / 1e6,
		#out,
		#marks,
		#folds
	)
)

-- The async render hands the event loop back between steps; the longest step is the longest stall.
local schedule, slowest = vim.schedule, 0
vim.schedule = function(fn)
	schedule(function()
		local t = vim.uv.hrtime()
		fn()
		slowest = math.max(slowest, (vim.uv.hrtime() - t) / 1e6)
	end)
end
local done, first = false, nil
local t1 = vim.uv.hrtime()
transcript.render_file(path, { title = "bench", cwd = "/x", msg_count = N * 2 }, function()
	done = true
end, function()
	first = (vim.uv.hrtime() - t1) / 1e6
end)
vim.wait(120000, function()
	return done
end, 1)
print(
	("async render:  %6.0f ms  first screen after %.0f ms, longest step %.0f ms"):format(
		(vim.uv.hrtime() - t1) / 1e6,
		first or -1,
		slowest
	)
)
os.remove(path)
