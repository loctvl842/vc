-- Syntax colors for a code block: the language's tree-sitter highlight query, mapped onto a few roles that
-- `finder.highlights` defines from the terminal palette (never the active colorscheme). A language without
-- an installed parser gets no marks, so the block just stays plain text.
local M = {}

local ts = vim.treesitter

local MAX_BYTES = 30000 -- bigger blocks stay plain; the preview must not stall on a pasted file

-- Names Claude writes after the fence that are not parser or filetype names.
local ALIAS = { shell = "bash", sh = "bash", zsh = "bash", console = "bash", js = "javascript", ts = "typescript" }

-- Capture name (or its prefix, so `keyword.function` falls back to `keyword`) -> mark group.
local ROLE = {
	keyword = "CodeKeyword",
	conditional = "CodeKeyword",
	["repeat"] = "CodeKeyword",
	include = "CodeKeyword",
	string = "CodeString",
	character = "CodeString",
	number = "CodeNumber",
	boolean = "CodeNumber",
	constant = "CodeNumber",
	comment = "CodeComment",
	["function"] = "CodeFunction",
	method = "CodeFunction",
	type = "CodeType",
	constructor = "CodeType",
	module = "CodeType",
	tag = "CodeKeyword",
}

local missing = {} ---@type table<string, true> languages known to have no parser or query

---@param capture string
---@return string?
local function role(capture)
	local name = capture
	while name do
		if ROLE[name] then
			return ROLE[name]
		end
		name = name:match("^(.+)%.[^.]+$")
	end
end

---@param lang string
---@return string? parser language, when one is installed
local function resolve(lang)
	lang = ALIAS[lang:lower()] or lang:lower()
	lang = ts.language.get_lang(lang) or lang
	if missing[lang] then
		return
	end
	if not (pcall(ts.language.add, lang) and ts.query.get(lang, "highlights")) then
		missing[lang] = true
		return
	end
	return lang
end

--- Marks for `code`, relative to its lines (line 1 = the first), columns in bytes.
---@param code string
---@param lang? string
---@return VC.Mark[]
function M.marks(code, lang)
	local marks = {}
	local parser_lang = lang and lang ~= "" and #code <= MAX_BYTES and resolve(lang)
	if not parser_lang then
		return marks
	end
	local ok = pcall(function()
		local lines = vim.split(code, "\n", { plain = true })
		local query = ts.query.get(parser_lang, "highlights")
		local root = ts.get_string_parser(code, parser_lang):parse()[1]:root()
		for id, node in query:iter_captures(root, code) do
			local hl = role(query.captures[id])
			if hl then
				local sr, sc, er, ec = node:range()
				for row = sr, er do
					local line = lines[row + 1] or ""
					local from, to = row == sr and sc or 0, row == er and ec or #line
					if from < to then
						marks[#marks + 1] = { l = row + 1, c = from, e = math.min(to, #line), hl = hl }
					end
				end
			end
		end
	end)
	return ok and marks or {}
end

return M
