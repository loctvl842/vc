-- Turns a Claude Code transcript (.jsonl) into markdown lines for the preview.
-- The whole conversation is kept: tool calls, tool results and thinking are
-- emitted in full, and each consecutive run of them is reported as a fold so
-- the preview can start them closed.
local M = {}

---@class VC.Fold
---@field start integer first line (1-based, inclusive)
---@field stop integer last line (inclusive)
---@field label string text shown while closed

local CHUNK = 400 -- transcript lines handled per event-loop turn when rendering async

local function decode(line)
	local ok, obj = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
	return ok and type(obj) == "table" and obj or nil
end

---@param out string[]
---@param text string
---@param prefix? string
local function push_text(out, text, prefix)
	prefix = prefix or ""
	for l in (text .. "\n"):gmatch("(.-)\n") do
		out[#out + 1] = prefix .. l
	end
end

--- Flatten a tool_result `content` (string or array of blocks) to text.
local function result_text(content)
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

---@class VC.Builder
---@field lines string[]
---@field folds VC.Fold[]
local Builder = {}
Builder.__index = Builder

---@param header? string[]
function M.builder(header)
	local self = setmetatable({ lines = {}, folds = {}, speaker = nil, run = nil }, Builder)
	for _, l in ipairs(header or {}) do
		self.lines[#self.lines + 1] = l
	end
	return self
end

function Builder:_close_run()
	local run = self.run
	if not run then
		return
	end
	self.run = nil
	local parts = {}
	if run.calls > 0 then
		parts[#parts + 1] = run.calls .. (run.calls == 1 and " tool call" or " tool calls")
	end
	if run.thinking > 0 then
		parts[#parts + 1] = "thinking"
	end
	if run.calls == 0 and run.thinking == 0 then
		parts[#parts + 1] = "tool results"
	end
	self.folds[#self.folds + 1] = { start = run.start, stop = #self.lines, label = "▸ " .. table.concat(parts, ", ") }
end

function Builder:_open_run()
	if not self.run then
		self.run = { start = #self.lines + 1, calls = 0, thinking = 0 }
	end
	return self.run
end

---@param role "user"|"assistant"
---@param text string
function Builder:_say(role, text)
	self:_close_run()
	if self.speaker ~= role then
		if #self.lines > 0 then
			self.lines[#self.lines + 1] = ""
		end
		self.lines[#self.lines + 1] = role == "user" and "## You" or "## Claude"
		self.speaker = role
	end
	self.lines[#self.lines + 1] = ""
	push_text(self.lines, text)
end

--- Feed one transcript line (a JSON record).
---@param line string
function Builder:feed(line)
	if not (line:find('"type":"user"', 1, true) or line:find('"type":"assistant"', 1, true)) then
		return
	end
	if line:find('"isSidechain":true', 1, true) or line:find('"isMeta":true', 1, true) then
		return
	end
	local o = decode(line)
	if not o or (o.type ~= "user" and o.type ~= "assistant") or not o.message then
		return
	end
	local role = o.type
	local content = o.message.content
	if type(content) == "string" then
		content = { { type = "text", text = content } }
	end
	if type(content) ~= "table" then
		return
	end
	for _, b in ipairs(content) do
		if b.type == "text" and type(b.text) == "string" and b.text ~= "" then
			self:_say(role, b.text)
		elseif b.type == "image" then
			self:_say(role, "[image]")
		elseif b.type == "thinking" and type(b.thinking) == "string" and b.thinking:find("%S") then
			local run = self:_open_run()
			run.thinking = run.thinking + 1
			self.lines[#self.lines + 1] = "thinking:"
			push_text(self.lines, b.thinking, "  ")
		elseif b.type == "tool_use" then
			local run = self:_open_run()
			run.calls = run.calls + 1
			self.lines[#self.lines + 1] = "tool: " .. tostring(b.name)
			push_text(self.lines, vim.json.encode(b.input or {}), "  ")
		elseif b.type == "tool_result" then
			self:_open_run()
			self.lines[#self.lines + 1] = "result:"
			push_text(self.lines, result_text(b.content), "  ")
		end
	end
end

--- Close any open run and return the result.
---@return string[] lines, VC.Fold[] folds
function Builder:finish()
	self:_close_run()
	return self.lines, self.folds
end

---@param row { title: string, cwd?: string, msg_count: integer }
---@return string[]
function M.header(row)
	return {
		"# " .. row.title,
		(row.cwd or "(unknown folder)") .. " - " .. row.msg_count .. " messages",
	}
end

--- Render a whole transcript at once (used by tests and small files).
---@param text string
---@param row? { title: string, cwd?: string, msg_count: integer }
---@return string[] lines, VC.Fold[] folds
function M.render(text, row)
	local b = M.builder(row and M.header(row) or nil)
	for line in text:gmatch("[^\n]+") do
		b:feed(line)
	end
	return b:finish()
end

--- Render a transcript file without blocking the UI: reads it, then feeds
--- CHUNK lines per event-loop turn. Returns a cancel function.
---@param path string
---@param row { title: string, cwd?: string, msg_count: integer }
---@param on_done fun(lines: string[], folds: VC.Fold[])
---@return fun() cancel
function M.render_file(path, row, on_done)
	local cancelled = false
	local f = io.open(path, "rb")
	local text = f and f:read("*a") or ""
	if f then
		f:close()
	end
	local b = M.builder(M.header(row))
	local iter = text:gmatch("[^\n]+")
	local function step()
		if cancelled then
			return
		end
		for _ = 1, CHUNK do
			local line = iter()
			if not line then
				on_done(b:finish())
				return
			end
			b:feed(line)
		end
		vim.schedule(step)
	end
	vim.schedule(step)
	return function()
		cancelled = true
	end
end

return M
