--- Word wrap by display width. The result is byte spans of the text, not new strings, so a position in
--- the text (a search match) maps onto the row and column that show it.
local M = {}

---@alias VC.Finder.Span { s: integer, e: integer } 1-based inclusive byte range of the text

---@param byte integer first byte of a UTF-8 character
---@return integer bytes in the character
local function char_len(byte)
	if byte < 0xC0 then
		return 1
	elseif byte < 0xE0 then
		return 2
	elseif byte < 0xF0 then
		return 3
	end
	return 4
end

--- Cut the word `text[s..e]` into pieces of at most `width` columns, at character boundaries.
---@return { s: integer, e: integer, w: integer }[]
local function split_word(text, s, e, width)
	local pieces = {}
	local pos = s
	while pos <= e do
		local w, i, last = 0, pos, pos - 1
		while i <= e do
			local n = char_len(text:byte(i))
			local cw = vim.fn.strdisplaywidth(text:sub(i, i + n - 1))
			-- A piece always takes one character, even one wider than `width`.
			if w + cw > width and last >= pos then
				break
			end
			w, last, i = w + cw, i + n - 1, i + n
		end
		pieces[#pieces + 1] = { s = pos, e = last, w = w }
		pos = last + 1
	end
	return pieces
end

--- Break `text` into lines of at most `width` display columns. Lines break at spaces (the space belongs to
--- no span); a word wider than `width` is cut at a character boundary.
---@param text string
---@param width integer
---@return VC.Finder.Span[]
function M.lines(text, width)
	width = math.max(1, width)
	local out = {}
	local cur ---@type { s: integer, e: integer, w: integer }?
	local function flush()
		if cur then
			out[#out + 1] = { s = cur.s, e = cur.e }
			cur = nil
		end
	end
	local pos = 1
	while true do
		local ws, we = text:find("%S+", pos)
		-- stylua: ignore
		if not ws then break end
		pos = we + 1
		local w = vim.fn.strdisplaywidth(text:sub(ws, we))
		if w > width then
			flush()
			local pieces = split_word(text, ws, we, width)
			for i = 1, #pieces - 1 do
				out[#out + 1] = { s = pieces[i].s, e = pieces[i].e }
			end
			cur = pieces[#pieces]
		elseif cur and cur.w + 1 + w <= width then
			cur.e, cur.w = we, cur.w + 1 + w
		else
			flush()
			cur = { s = ws, e = we, w = w }
		end
	end
	flush()
	return out
end

return M
