-- One-line summaries of tool activity for the preview: how a call reads ("Bash", "(npm test)"),
-- and the text lines of its result.
local config = require("vc.finder.config")

local M = {}

-- Input keys that carry the most telling argument, by priority.
local ARG_KEYS = {
	"command",
	"file_path",
	"notebook_path",
	"pattern",
	"path",
	"url",
	"query",
	"description",
	"skill",
	"prompt",
}
local PATH_KEYS = { file_path = true, notebook_path = true, path = true }

--- Drop ANSI escapes and carriage returns; neither belongs in a buffer line.
---@param s string
---@return string
function M.clean(s)
	s = s:gsub("\27%[[%d;?]*[%a]", ""):gsub("\27", ""):gsub("\r", "")
	return s
end

---@param s string
---@param width integer
---@return string
local function truncate(s, width)
	if vim.fn.strchars(s) <= width then
		return s
	end
	return vim.fn.strcharpart(s, 0, width - 1) .. "…"
end

--- "Name" and "(args)" for a tool call. MCP tools read "server - tool (MCP)", as in Claude Code.
---@param name string
---@param input table?
---@param cwd string? folder paths are shown relative to
---@return string name, string args
function M.call(name, input, cwd)
	input = type(input) == "table" and input or {}
	local server, tool = tostring(name):match("^mcp__(.-)__(.+)$")
	if server then
		name = server .. " - " .. tool .. " (MCP)"
	end
	local arg
	for _, key in ipairs(ARG_KEYS) do
		local v = input[key]
		if type(v) == "string" and v ~= "" then
			arg = v
			if PATH_KEYS[key] and cwd and cwd ~= "" and vim.startswith(v, cwd .. "/") then
				arg = v:sub(#cwd + 2)
			end
			break
		end
	end
	if not arg then
		return name, ""
	end
	arg = M.clean(arg):gsub("%s*\n%s*", " ")
	return name, "(" .. truncate(arg, config.preview.args_width) .. ")"
end

-- Tools Claude Code folds into a "Ran 2 shell commands" summary when they come one after another.
local CATEGORY = { Bash = "shell", Read = "read", Grep = "search", Glob = "search" }
local SUMMARY = { -- in the order Claude Code lists them
	{ "search", "searched for %d pattern", "searched for %d patterns" },
	{ "read", "read %d file", "read %d files" },
	{ "shell", "ran %d shell command", "ran %d shell commands" },
}

--- What a tool call counts as in a folded run, or nil when it always shows on its own line.
---@param name string
---@return string?
function M.category(name)
	return CATEGORY[name]
end

--- "Searched for 1 pattern, read 2 files, ran 3 shell commands" for the counts of a run.
---@param counts table<string, integer>
---@return string
function M.summary(counts)
	local parts = {}
	for _, s in ipairs(SUMMARY) do
		local n = counts[s[1]]
		if n then
			parts[#parts + 1] = s[n == 1 and 2 or 3]:format(n)
		end
	end
	local text = table.concat(parts, ", ")
	return text:sub(1, 1):upper() .. text:sub(2)
end

--- Flatten a tool_result `content` (string or array of blocks) to text.
---@param content any
---@return string
function M.content_text(content)
	if type(content) == "string" then
		return content
	end
	if type(content) ~= "table" then
		return ""
	end
	local parts = {}
	for _, b in ipairs(content) do
		if b.type == "text" and type(b.text) == "string" then
			parts[#parts + 1] = b.text
		elseif b.type == "image" then
			parts[#parts + 1] = "[image]"
		end
	end
	return table.concat(parts, "\n")
end

--- Split text into buffer lines (no newlines inside, no trailing blank lines).
---@param text string
---@return string[]
function M.split(text)
	text = M.clean(text):gsub("%s+$", "")
	local out = {}
	for l in (text .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = l
	end
	return out
end

--- The text lines of a result; a result without output reads "(No content)".
---@param res { text: string }
---@return string[]
function M.result_lines(res)
	local lines = M.split(res.text or "")
	if #lines == 1 and lines[1] == "" then
		return { "(No content)" }
	end
	return lines
end

--- A file edit as a diff, from the patch Claude Code stored with the result (Edit, MultiEdit, Write).
--- Lines read `<line number> <+|-| ><text>`; marks are relative to `lines`.
---@param rec table? the record's `toolUseResult`
---@return { summary: string, lines: string[], marks: VC.Mark[] }?
function M.diff(rec)
	local ok, d = pcall(M._diff, rec) -- a malformed patch must not stop the whole preview
	return ok and d or nil
end

---@param rec table?
---@return { summary: string, lines: string[], marks: VC.Mark[] }?
function M._diff(rec)
	if type(rec) ~= "table" then
		return
	end
	local hunks = rec.structuredPatch
	if rec.type == "create" and type(rec.content) == "string" and (not hunks or #hunks == 0) then
		local added = M.split(rec.content)
		for i, l in ipairs(added) do
			added[i] = "+" .. l
		end
		hunks = { { oldStart = 0, newStart = 1, oldLines = 0, newLines = #added, lines = added } }
	end
	if type(hunks) ~= "table" or #hunks == 0 then
		return
	end
	local width = 1
	for _, h in ipairs(hunks) do
		width = math.max(width, #tostring(math.max(h.oldStart + h.oldLines, h.newStart + h.newLines)))
	end
	local lines, marks, added, removed = {}, {}, 0, 0
	for i, h in ipairs(hunks) do
		if i > 1 then
			lines[#lines + 1] = string.rep(" ", width) .. " …"
			marks[#marks + 1] = { l = #lines, hl = "ToolArgs", line = true }
		end
		local old_no, new_no = h.oldStart, h.newStart
		for _, raw in ipairs(h.lines) do
			local sign, no = raw:sub(1, 1), nil
			if sign == "+" then
				no, new_no, added = new_no, new_no + 1, added + 1
			elseif sign == "-" then
				no, old_no, removed = old_no, old_no + 1, removed + 1
			else
				no, old_no, new_no = new_no, old_no + 1, new_no + 1
			end
			lines[#lines + 1] = string.format("%" .. width .. "d %s", no, M.clean(raw))
			local l, gutter = #lines, width + 2
			if sign == "+" then
				marks[#marks + 1] = { l = l, hl = "DiffAdd", line = true }
				marks[#marks + 1] = { l = l, c = 0, e = gutter, hl = "DiffAddSign" }
			elseif sign == "-" then
				marks[#marks + 1] = { l = l, hl = "DiffDelete", line = true }
				marks[#marks + 1] = { l = l, c = 0, e = gutter, hl = "DiffDeleteSign" }
			else
				marks[#marks + 1] = { l = l, c = 0, e = gutter, hl = "ToolArgs" }
			end
		end
	end
	local function count(n, word)
		return n .. " " .. word .. (n == 1 and "" or "s")
	end
	local parts = {}
	if added > 0 then
		parts[#parts + 1] = count(added, "addition")
	end
	if removed > 0 then
		parts[#parts + 1] = count(removed, "removal")
	end
	local summary = rec.type == "create" and ("Wrote " .. count(added, "line"))
		or ("Updated with " .. (#parts > 0 and table.concat(parts, " and ") or "no changes"))
	return { summary = summary, lines = lines, marks = marks }
end

return M
