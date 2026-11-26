-- Claude's markdown as display lines plus highlight marks. Markers (`**`, backticks, `#`, link brackets) are
-- dropped and the style they stand for becomes a mark, so the preview shows bold text instead of "**bold**".
-- Both the block structure and the inline spans come from tree-sitter (the bundled `markdown` and
-- `markdown_inline` parsers). Without a parser, or on any error, the text is returned as it is.
local code = require("vc.code")
local toolline = require("vc.toolline")

local M = {}

---@class VC.Doc
---@field lines string[]
---@field marks VC.Mark[] positions are relative to `lines`

local ts = vim.treesitter

local BULLET = "• "
local RULE = string.rep("─", 24)
local CODE_INDENT = "  "

local available ---@type boolean?

---@return boolean
local function parsers_ready()
	if available == nil then
		available = pcall(ts.language.add, "markdown") and pcall(ts.language.add, "markdown_inline")
	end
	return available
end

---@param lines string[]
---@param marks? VC.Mark[]
---@return VC.Doc
local function doc(lines, marks)
	return { lines = lines, marks = marks or {} }
end

--- `b` below `a`, with `gap` blank lines between when both have content.
---@param a VC.Doc
---@param b VC.Doc
---@param gap? boolean
local function append(a, b, gap)
	if #b.lines == 0 then
		return
	end
	if gap and #a.lines > 0 then
		a.lines[#a.lines + 1] = ""
	end
	local at = #a.lines
	for _, l in ipairs(b.lines) do
		a.lines[#a.lines + 1] = l
	end
	for _, m in ipairs(b.marks) do
		local c = { l = m.l + at, c = m.c, e = m.e, hl = m.hl, line = m.line }
		a.marks[#a.marks + 1] = c
	end
end

--- Put `first` before the first line and `rest` before the others (an empty line stays empty, unless
--- `keep_empty`). `bar` marks the prefix; `text_hl` marks the text after it.
---@param d VC.Doc
---@param first string
---@param rest string
---@param opts? { keep_empty?: boolean, bar?: string, text_hl?: string }
---@return VC.Doc
local function prefixed(d, first, rest, opts)
	opts = opts or {}
	local shift, lines, marks = {}, {}, {}
	for i, text in ipairs(d.lines) do
		local p = i == 1 and first or rest
		if text == "" and not opts.keep_empty and i > 1 then
			p = ""
		end
		shift[i] = #p
		lines[i] = p .. text
		if opts.bar and p ~= "" then
			marks[#marks + 1] = { l = i, c = 0, e = #vim.trim(p) > 0 and #p - 1 or #p, hl = opts.bar }
		end
		if opts.text_hl and text ~= "" then
			marks[#marks + 1] = { l = i, c = #p, e = #p + #text, hl = opts.text_hl }
		end
	end
	for _, m in ipairs(d.marks) do
		local c = { l = m.l, hl = m.hl, line = m.line }
		if m.c then
			c.c, c.e = m.c + shift[m.l], m.e + shift[m.l]
		end
		marks[#marks + 1] = c
	end
	return doc(lines, marks)
end

--- Split `text` into lines; `spans` are {start, stop, hl} byte ranges (0-based, stop exclusive) of the
--- whole text, cut at line ends.
---@param text string
---@param spans { [1]: integer, [2]: integer, [3]: string }[]
---@return VC.Doc
local function split_spans(text, spans)
	local lines, starts = {}, {}
	local pos = 1
	while true do
		local nl = text:find("\n", pos, true)
		starts[#starts + 1] = pos - 1
		lines[#lines + 1] = text:sub(pos, (nl or #text + 1) - 1)
		if not nl then
			break
		end
		pos = nl + 1
	end
	local marks = {}
	for _, s in ipairs(spans) do
		for i, l in ipairs(lines) do
			local from, to = math.max(s[1], starts[i]), math.min(s[2], starts[i] + #l)
			if from < to then
				marks[#marks + 1] = { l = i, c = from - starts[i], e = to - starts[i], hl = s[3] }
			end
		end
	end
	return doc(lines, marks)
end

---@param node TSNode
---@return integer start, integer stop byte range (0-based, stop exclusive)
local function bytes(node)
	local _, _, sb, _, _, eb = node:range(true)
	return sb, eb
end

local INLINE_STYLE = { emphasis = "Italic", strong_emphasis = "Bold", strikethrough = "Strike" }

--- Inline markdown to text and spans.
---@param text string
---@return string out, { [1]: integer, [2]: integer, [3]: string }[] spans
local function inline(text)
	local root = ts.get_string_parser(text, "markdown_inline"):parse()[1]:root()
	local buf, n, spans = {}, 0, {}
	local function put(s)
		buf[#buf + 1] = s
		n = n + #s
	end
	local walk

	--- All of `node`'s text, each child handled by `walk`.
	local function children(node)
		local pos, stop = bytes(node)
		for child in node:iter_children() do
			local cs, ce = bytes(child)
			if cs > pos then
				put(text:sub(pos + 1, cs))
			end
			walk(child)
			pos = ce
		end
		if pos < stop then
			put(text:sub(pos + 1, stop))
		end
	end

	---@param node TSNode
	---@param hl? string
	local function styled(node, hl)
		local from = n
		children(node)
		if hl and n > from then
			spans[#spans + 1] = { from, n, hl }
		end
	end

	function walk(node)
		local kind = node:type()
		local s, e = bytes(node)
		if kind:find("_delimiter$") then
			return
		elseif INLINE_STYLE[kind] then
			styled(node, INLINE_STYLE[kind])
		elseif kind == "code_span" then
			styled(node, "Code")
		elseif kind == "inline_link" then
			for child in node:iter_children() do
				if child:type() == "link_text" then
					styled(child, "Link")
				end
			end
		elseif kind == "image" then
			local alt
			for child in node:iter_children() do
				if child:type() == "image_description" then
					local cs, ce = bytes(child)
					alt = text:sub(cs + 1, ce)
				end
			end
			put("[image" .. (alt and alt ~= "" and (": " .. alt) or "") .. "]")
		elseif kind == "backslash_escape" then
			put(text:sub(s + 2, e))
		elseif kind == "hard_line_break" then
			put("\n")
		elseif kind == "uri_autolink" or kind == "email_autolink" then
			local from = n
			put(text:sub(s + 2, e - 1))
			spans[#spans + 1] = { from, n, "Link" }
		elseif kind == "shortcut_link" or kind == "full_reference_link" or kind == "collapsed_reference_link" then
			put(text:sub(s + 1, e)) -- no definition to resolve: keep the source as written
		else
			children(node)
		end
	end

	children(root)
	return table.concat(buf), spans
end

---@param text string
---@return VC.Doc
local function inline_doc(text)
	text = text:gsub("[ \t]+\n", "\n"):gsub("\n[ \t]+", "\n"):gsub("^%s+", ""):gsub("%s+$", "")
	local out, spans = inline(text)
	return split_spans(out, spans)
end

---@param node TSNode
---@param src string
---@return string
local function text_of(node, src)
	local s, e = bytes(node)
	return src:sub(s + 1, e)
end

--- Text of an `inline` node without the "> " (or indent) a container repeats at the start of each line.
---@param node TSNode
---@param src string
---@return string
local function inline_text(node, src)
	local pos, stop = bytes(node)
	local parts = {}
	for child in node:iter_children() do
		if child:type() == "block_continuation" then
			local cs, ce = bytes(child)
			parts[#parts + 1] = src:sub(pos + 1, cs)
			pos = ce
		end
	end
	parts[#parts + 1] = src:sub(pos + 1, stop)
	return table.concat(parts)
end

local render ---@type fun(node: TSNode, src: string): VC.Doc

---@param text string
---@param lang? string
---@return VC.Doc
local function code_block(text, lang)
	local d = doc({})
	local label = lang and lang ~= ""
	if label then
		d.lines[1] = CODE_INDENT .. lang
		d.marks[1] = { l = 1, c = #CODE_INDENT, e = #CODE_INDENT + #lang, hl = "CodeLang" }
	end
	local lines = toolline.split(text)
	for _, l in ipairs(lines) do
		d.lines[#d.lines + 1] = l == "" and "" or (CODE_INDENT .. l)
	end
	for _, m in ipairs(code.marks(table.concat(lines, "\n"), lang)) do
		d.marks[#d.marks + 1] =
			{ l = m.l + (label and 1 or 0), c = m.c + #CODE_INDENT, e = m.e + #CODE_INDENT, hl = m.hl }
	end
	return d
end

--- Child blocks of `node`, in order, one blank line between them.
---@param node TSNode
---@param src string
---@return VC.Doc
local function blocks(node, src)
	local d = doc({})
	for child in node:iter_children() do
		local kind = child:type()
		if child:named() and kind ~= "block_quote_marker" and kind ~= "block_continuation" then
			append(d, render(child, src), true)
		end
	end
	return d
end

---@param item TSNode
---@param src string
---@return VC.Doc
local function list_item(item, src)
	local marker = BULLET
	local body = doc({})
	for child in item:iter_children() do
		local kind = child:type()
		if kind:find("^list_marker") then
			local m = vim.trim(text_of(child, src))
			marker = m:match("^%d") and (m .. " ") or BULLET
		elseif kind == "task_list_marker_checked" then
			marker = marker .. "☒ "
		elseif kind == "task_list_marker_unchecked" then
			marker = marker .. "☐ "
		elseif child:named() and kind ~= "block_continuation" then
			append(body, render(child, src), not (kind == "list"))
		end
	end
	if #body.lines == 0 then
		body.lines[1] = ""
	end
	return prefixed(body, marker, string.rep(" ", vim.fn.strdisplaywidth(marker)))
end

---@param node TSNode
---@param src string
---@return VC.Doc
function render(node, src)
	local kind = node:type()
	if kind == "document" or kind == "section" then
		return blocks(node, src)
	elseif kind == "paragraph" then
		for child in node:iter_children() do
			if child:type() == "inline" then
				return inline_doc(inline_text(child, src))
			end
		end
	elseif kind == "atx_heading" or kind == "setext_heading" then
		local level = 2
		local body
		for child in node:iter_children() do
			local ck = child:type()
			if ck == "atx_h1_marker" or ck == "setext_h1_underline" then
				level = 1
			elseif ck == "inline" or ck == "paragraph" then
				body = inline_text(child, src)
			end
		end
		local d = inline_doc(body or "")
		local hl = level == 1 and "Heading1" or "Heading"
		for i, l in ipairs(d.lines) do
			if l ~= "" then
				d.marks[#d.marks + 1] = { l = i, c = 0, e = #l, hl = hl }
			end
		end
		return d
	elseif kind == "list" then
		local d = doc({})
		for item in node:iter_children() do
			if item:type() == "list_item" then
				append(d, list_item(item, src))
			end
		end
		return d
	elseif kind == "block_quote" then
		return prefixed(blocks(node, src), "▎ ", "▎ ", { keep_empty = true, bar = "QuoteBar", text_hl = "Quote" })
	elseif kind == "fenced_code_block" then
		local lang, text
		for child in node:iter_children() do
			if child:type() == "info_string" then
				lang = vim.split(vim.trim(text_of(child, src)), "%s+")[1]
			elseif child:type() == "code_fence_content" then
				text = text_of(child, src)
			end
		end
		return code_block(text or "", lang)
	elseif kind == "indented_code_block" then
		return code_block((text_of(node, src):gsub("^    ", ""):gsub("\n    ", "\n")), nil)
	elseif kind == "thematic_break" then
		return doc({ RULE }, { { l = 1, c = 0, e = #RULE, hl = "QuoteBar" } })
	end
	return doc(toolline.split(text_of(node, src)))
end

---@param text string
---@return VC.Doc
local function plain(text)
	return doc(toolline.split(text))
end

--- Render markdown text to display lines and marks. Never fails: on any error the plain text comes back.
---@param text string
---@return string[] lines, VC.Mark[] marks
function M.render(text)
	if not parsers_ready() then
		local d = plain(text)
		return d.lines, d.marks
	end
	local ok, d = pcall(function()
		local src = toolline.clean(text):gsub("%s+$", "") .. "\n"
		local root = ts.get_string_parser(src, "markdown"):parse()[1]:root()
		return render(root, src)
	end)
	if not ok or #d.lines == 0 then
		d = plain(text)
	end
	return d.lines, d.marks
end

return M
