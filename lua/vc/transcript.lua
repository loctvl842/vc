-- Turns a Claude Code transcript (.jsonl) into a styled document for the preview: display lines, highlight
-- marks and folds. Records become typed blocks first (a tool result is paired with its call by id), and
-- blocks are then rendered the way Claude Code draws a session: "> " prompts, "● " replies, one-line tool
-- calls with their result underneath, thinking folded away.
local config = require("vc.finder.config")
local markdown = require("vc.markdown")
local toolline = require("vc.toolline")

local M = {}

---@class VC.Fold
---@field start integer first line (1-based, inclusive)
---@field stop integer last line (inclusive)
---@field label string text shown while closed

---@class VC.Mark
---@field l integer line (1-based)
---@field c? integer first byte column (0-based); absent for a whole line
---@field e? integer end byte column, exclusive
---@field hl string group, without the "VCFinderPreview" prefix
---@field line? boolean the group paints the whole line

local CHUNK = 400 -- transcript lines handled per event-loop turn when rendering async
local RENDER_CHUNK = 200 -- blocks rendered per event-loop turn
local PARTIAL_LINES = 80 -- lines rendered before the first screen is published
local RESOLVE_WINDOW = 64 -- a call this far back that never got a result is rendered without one

local PROMPT = "> "
local REPLY = "● "
local RESULT_FIRST = "  ⎿  "
local RESULT_REST = "     "

local function decode(line)
	local ok, obj = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
	return ok and type(obj) == "table" and obj or nil
end

---@class VC.Out
---@field lines string[]
---@field marks VC.Mark[]
---@field folds VC.Fold[]
local Out = {}
Out.__index = Out

local function new_out()
	return setmetatable({ lines = {}, marks = {}, folds = {} }, Out)
end

---@param text string
---@return integer line
function Out:add(text)
	self.lines[#self.lines + 1] = text
	return #self.lines
end

--- One blank line between blocks (never at the very top, never twice).
function Out:gap()
	if #self.lines > 0 and self.lines[#self.lines] ~= "" then
		self:add("")
	end
end

---@param l integer
---@param c integer
---@param e integer
---@param hl string
function Out:mark(l, c, e, hl)
	self.marks[#self.marks + 1] = { l = l, c = c, e = e, hl = hl }
end

---@param l integer
---@param hl string
function Out:whole(l, hl)
	self.marks[#self.marks + 1] = { l = l, hl = hl, line = true }
end

--- Lines of a message: `marker` on the first, an indent of the same width on the rest. `marks` are
--- relative to `lines` (line 1 = the first), as a renderer returns them.
---@param marker string
---@param lines string[]
---@param marks? VC.Mark[]
---@param opts? { line_hl?: string } group for every line (the prompt's band)
---@return integer first line
function Out:message(marker, lines, marks, opts)
	local first = #self.lines + 1
	local indent = string.rep(" ", vim.fn.strdisplaywidth(marker))
	local shift = {}
	for i, text in ipairs(lines) do
		local prefix = i == 1 and marker or indent
		shift[i] = #prefix
		local l = self:add(text == "" and "" or (prefix .. text))
		if opts and opts.line_hl then
			self:whole(l, opts.line_hl)
		end
	end
	for _, m in ipairs(marks or {}) do
		local out = { l = first + m.l - 1, hl = m.hl, line = m.line }
		if m.c then
			out.c, out.e = m.c + shift[m.l], m.e + shift[m.l]
		end
		self.marks[#self.marks + 1] = out
	end
	return first
end

---@class VC.Block
---@field kind "prompt"|"reply"|"thinking"|"call"|"result"
---@field text? string
---@field id? string
---@field name? string
---@field input? table
---@field result? { text: string, is_error: boolean, rec?: table }

---@class VC.Builder
---@field blocks (VC.Block|false)[]
---@field out VC.Out
local Builder = {}
Builder.__index = Builder

---@param header? string[]
function M.builder(header)
	local self = setmetatable({ blocks = {}, calls = {}, rendered = 0, out = new_out(), cwd = nil }, Builder)
	for _, l in ipairs(header or {}) do
		self.out:whole(self.out:add(l), "Meta")
	end
	return self
end

---@param block VC.Block
function Builder:push(block)
	self.blocks[#self.blocks + 1] = block
	return block
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
	self.cwd = self.cwd or o.cwd
	local kind = o.type == "user" and "prompt" or "reply"
	local content = o.message.content
	if type(content) == "string" then
		content = { { type = "text", text = content } }
	end
	if type(content) ~= "table" then
		return
	end
	local results = 0
	for _, b in ipairs(content) do
		results = results + (b.type == "tool_result" and 1 or 0)
	end
	for _, b in ipairs(content) do
		if b.type == "text" and type(b.text) == "string" and b.text ~= "" then
			self:push({ kind = kind, text = b.text })
		elseif b.type == "image" then
			self:push({ kind = kind, text = "[image]" })
		elseif b.type == "thinking" and type(b.thinking) == "string" and b.thinking:find("%S") then
			self:push({ kind = "thinking", text = b.thinking })
		elseif b.type == "tool_use" then
			local call = self:push({ kind = "call", id = b.id, name = tostring(b.name), input = b.input })
			if b.id then
				self.calls[b.id] = call
			end
		elseif b.type == "tool_result" then
			local res = {
				text = toolline.content_text(b.content),
				is_error = b.is_error == true,
				rec = results == 1 and type(o.toolUseResult) == "table" and o.toolUseResult or nil,
			}
			local call = b.tool_use_id and self.calls[b.tool_use_id]
			if call then
				call.result = res
			else
				self:push({ kind = "result", result = res })
			end
		end
	end
end

---@param out VC.Out
---@param res { text: string, is_error: boolean }
local function render_result(out, res)
	local lines = toolline.result_lines(res)
	local hl = res.is_error and "Error" or "Result"
	local shown = #lines
	if #lines - config.preview.result_lines >= 2 then
		shown = config.preview.result_lines
	end
	for i = 1, shown do
		out:whole(out:add((i == 1 and RESULT_FIRST or RESULT_REST) .. lines[i]), hl)
	end
	if shown < #lines then
		local first = #out.lines + 1
		for i = shown + 1, #lines do
			out:whole(out:add(RESULT_REST .. lines[i]), hl)
		end
		out.folds[#out.folds + 1] =
			{ start = first, stop = #out.lines, label = RESULT_REST .. "… +" .. (#lines - shown) .. " lines" }
	end
end

---@param b VC.Block
function Builder:render_block(b)
	local out = self.out
	out:gap()
	if b.kind == "prompt" or b.kind == "reply" then
		if b.kind == "prompt" then
			local first = out:message(PROMPT, toolline.split(b.text), nil, { line_hl = "Band" })
			out:mark(first, 0, #PROMPT - 1, "Prompt")
		else
			local first = out:message(REPLY, markdown.render(b.text))
			out:mark(first, 0, #REPLY - 1, "Dot")
		end
	elseif b.kind == "thinking" then
		local first = out:add("✻ Thinking…")
		out:whole(first, "Thinking")
		for _, text in ipairs(toolline.split(b.text)) do
			out:whole(out:add(text == "" and "" or ("  " .. text)), "Thinking")
		end
		out.folds[#out.folds + 1] = { start = first, stop = #out.lines, label = "✻ Thinking…" }
	elseif b.kind == "call" then
		local name, args = toolline.call(b.name, b.input, self.cwd)
		local l = out:add(REPLY .. name .. args)
		out:mark(l, 0, #REPLY - 1, "Dot")
		out:mark(l, #REPLY, #REPLY + #name, "ToolName")
		if args ~= "" then
			out:mark(l, #REPLY + #name, #REPLY + #name + #args, "ToolArgs")
		end
		if b.result then
			render_result(out, b.result)
		end
	elseif b.kind == "result" then
		render_result(out, b.result)
	end
end

--- Render blocks that are ready, at most `max` of them. A call whose result has not been read yet holds
--- back everything after it, unless it is old enough to be a call that never got one.
---@param final boolean no more records will come: render everything
---@param max? integer
---@return boolean done nothing is left to render
function Builder:render(final, max)
	local blocks = self.blocks
	local limit = #blocks
	if not final then
		for i = math.max(self.rendered + 1, #blocks - RESOLVE_WINDOW), #blocks do
			local b = blocks[i]
			if b and b.kind == "call" and not b.result then
				limit = i - 1
				break
			end
		end
	end
	local n = 0
	while self.rendered < limit and (not max or n < max) do
		self.rendered = self.rendered + 1
		local b = blocks[self.rendered]
		blocks[self.rendered] = false -- rendered blocks (and their big inputs) are not needed again
		if b then
			if b.id then
				self.calls[b.id] = nil
			end
			self:render_block(b)
		end
		n = n + 1
	end
	return self.rendered >= limit and (not final or limit == #blocks)
end

--- Render what is left and return the document.
---@return string[] lines, VC.Fold[] folds, VC.Mark[] marks
function Builder:finish()
	self:render(true)
	return self.out.lines, self.out.folds, self.out.marks
end

---@param row { title: string, cwd?: string, msg_count: integer }
---@return string[]
function M.header(row)
	return { (row.cwd or "(unknown folder)") .. " - " .. row.msg_count .. " messages" }
end

--- Render a whole transcript at once (used by tests and small files).
---@param text string
---@param row? { title: string, cwd?: string, msg_count: integer }
---@return string[] lines, VC.Fold[] folds, VC.Mark[] marks
function M.render(text, row)
	local b = M.builder(row and M.header(row) or nil)
	for line in text:gmatch("[^\n]+") do
		b:feed(line)
	end
	return b:finish()
end

--- Render a transcript file without blocking the UI: reads it, then feeds CHUNK records and renders
--- RENDER_CHUNK blocks per event-loop turn. `on_partial` gets the top of the document once, as soon as
--- there is a screenful, so a long session shows at once. Returns a cancel function.
---@param path string
---@param row { title: string, cwd?: string, msg_count: integer }
---@param on_done fun(lines: string[], folds: VC.Fold[], marks: VC.Mark[])
---@param on_partial? fun(lines: string[], folds: VC.Fold[], marks: VC.Mark[])
---@return fun() cancel
function M.render_file(path, row, on_done, on_partial)
	local cancelled, eof, sent = false, false, false
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
		if not eof then
			for _ = 1, CHUNK do
				local line = iter()
				if not line then
					eof = true
					break
				end
				b:feed(line)
			end
		end
		local done = b:render(eof, RENDER_CHUNK)
		if eof and done then
			on_done(b:finish())
			return
		end
		if on_partial and not sent and #b.out.lines >= PARTIAL_LINES then
			sent = true
			on_partial(b.out.lines, b.out.folds, b.out.marks)
		end
		vim.schedule(step)
	end
	vim.schedule(step)
	return function()
		cancelled = true
	end
end

return M
