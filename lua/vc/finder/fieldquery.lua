--- Splits the typed query into `field:value` terms and the rest, which is searched as ordinary text.
--- A term is a word that starts with a field name and a colon (`cwd:jarvix`); a value that starts with a double
--- quote runs to the closing quote (`title:"fix login"`). Any other word, `ticket:42` and URLs included, stays
--- in the rest. UI-free.
local M = {}

---@type table<string, true>
M.FIELDS = { cwd = true, title = true, branch = true, pr = true, recap = true, msg = true }

---@class VC.Finder.FieldTerm
---@field name string one of `M.FIELDS`
---@field value string never empty
---@field quoted boolean the value was written in double quotes

---@class VC.Finder.FieldQuery
---@field terms VC.Finder.FieldTerm[] terms that have a value, in the order typed
---@field rest string the other words, one space apart
---@field prefixes { s: integer, e: integer }[] bytes of each recognised `name:`, empty values included

---@param text string
---@return VC.Finder.FieldQuery
function M.parse(text)
	local terms, words, prefixes = {}, {}, {}
	local i = 1
	while true do
		local s = text:find("%S", i)
		-- stylua: ignore
		if not s then break end
		local name = text:match("^(%l+):", s)
		if name and M.FIELDS[name] then
			local v = s + #name + 1
			local quoted = text:sub(v, v) == '"'
			local value, e
			if quoted then
				local close = text:find('"', v + 1, true)
				e = close or #text
				value = text:sub(v + 1, (close or #text + 1) - 1)
			else
				e = (text:find("%s", v) or #text + 1) - 1
				value = text:sub(v, e)
			end
			prefixes[#prefixes + 1] = { s = s, e = s + #name }
			if value ~= "" then
				terms[#terms + 1] = { name = name, value = value, quoted = quoted }
			end
			i = e + 1
		else
			local e = (text:find("%s", s) or #text + 1) - 1
			words[#words + 1] = text:sub(s, e)
			i = e + 1
		end
	end
	return { terms = terms, rest = table.concat(words, " "), prefixes = prefixes }
end

return M
