-- One-line summaries of tool activity for the preview: how a call reads ("Bash", "(npm test)"),
-- and the text lines of its result.
local config = require("vc.finder.config")

local M = {}

-- Input keys that carry the most telling argument, by priority.
local ARG_KEYS =
	{ "command", "file_path", "notebook_path", "path", "pattern", "url", "query", "description", "skill", "prompt" }
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

return M
