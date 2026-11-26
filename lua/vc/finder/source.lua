--- The one source of the finder: Claude Code sessions (see vc.sessions.index).
local wrap = require("vc.finder.wrap")

local M = {}

M.title = "Claude Sessions"
M.footer = "<CR> continue   <C-n>/<C-p> move   <C-l> preview   <Esc> exit"
M.footer_empty = "<Esc> exit"

local FOLD = 3 -- lines of a message shown while its session is not selected
local INDENT = "  "
local LABEL = { recap = "Recap › ", prompt = "You   › " }
local LABEL_COLS = 8
local GUTTER = 2 -- the selection marker the list draws before every row

---@param secs integer
---@param now? integer
---@return string
function M.relative_time(secs, now)
	local d = (now or os.time()) - secs
	if d < 60 then
		return "just now"
	elseif d < 3600 then
		return math.floor(d / 60) .. "m ago"
	elseif d < 86400 then
		return math.floor(d / 3600) .. "h ago"
	elseif d < 2 * 86400 then
		return "yesterday"
	elseif d < 14 * 86400 then
		return math.floor(d / 86400) .. "d ago"
	elseif d < 60 * 86400 then
		return math.floor(d / (7 * 86400)) .. "w ago"
	elseif d < 365 * 86400 then
		return math.floor(d / (30 * 86400)) .. "mo ago"
	end
	return math.floor(d / (365 * 86400)) .. "y ago"
end

--- Where a session ran: the full folder path with the home directory as `~`.
---@param row VC.Row
---@return string
function M.location(row)
	local cwd = row.cwd
	if not cwd or cwd == "" then
		return row.project
	end
	local home = vim.env.HOME
	if home and home ~= "" and (cwd == home or vim.startswith(cwd, home .. "/")) then
		return "~" .. cwd:sub(#home + 1)
	end
	return cwd
end

--- Items for a list of session rows (newest first), "New session" in front when `with_new`.
--- The search text is the title, the location, the recap and the last message (the last two when the session
--- has them), in that order. The title and location match fuzzily; the recap and last message only as a
--- substring (see `fuzzy_len`), since scattered letters match nearly any query in a paragraph.
--- `recap_at` and `prompt_at` are where those two start.
---@param rows VC.Row[]
---@param with_new boolean
---@return VC.Finder.Item[]
function M.items(rows, with_new)
	local items = {}
	if with_new then
		-- Empty text: it matches no query, so any typed text removes it from the list.
		items[1] = { idx = 1, score = 1, text = "", new = true }
	end
	for _, row in ipairs(rows) do
		local text = row.title .. "  " .. M.location(row)
		local item = { idx = #items + 1, score = 1, row = row }
		if row.recap or row.last_prompt then
			item.fuzzy_len = #text
		end
		if row.recap then
			item.recap_at = #text + 3
			text = text .. "  " .. row.recap
		end
		if row.last_prompt then
			item.prompt_at = #text + 3
			text = text .. "  " .. row.last_prompt
		end
		item.text = text
		items[#items + 1] = item
	end
	return items
end

--- `text` cut to `avail` display columns, with "…" in place of what was cut.
---@param text string
---@param avail integer
---@param keep "head"|"tail" which end survives; a path keeps its tail
---@return string shown
---@return integer kept bytes of `text` that survive
local function fit(text, avail, keep)
	if vim.fn.strdisplaywidth(text) <= avail then
		return text, #text
	end
	if keep == "head" then
		local cut = vim.fn.strcharpart(text, 0, avail - 1)
		return cut .. "…", #cut
	end
	local tail = vim.fn.strcharpart(text, vim.fn.strchars(text) - (avail - 1))
	return "…" .. tail, #tail
end

--- End `chunks` (one buffer row) with "…", dropping characters from its last text until it fits `width`.
---@param chunks VC.Finder.Chunk[]
---@param width integer
local function ellipsize(chunks, width)
	local last, used = nil, 0
	for i, c in ipairs(chunks) do
		if not c.right_align then
			last = i
			used = used + vim.fn.strdisplaywidth(c.text)
		end
	end
	-- stylua: ignore
	if not last or used == 0 then return end
	local text = chunks[last].text
	while used + 1 > width and text ~= "" do
		local drop = vim.fn.strcharpart(text, vim.fn.strchars(text) - 1)
		text = vim.fn.strcharpart(text, 0, vim.fn.strchars(text) - 1)
		used = used - vim.fn.strdisplaywidth(drop)
	end
	chunks[last].text = text .. "…"
end

---@class VC.Finder.Message a wrapped message shown in the list
---@field at integer where the message starts in `item.text`
---@field len integer bytes of the message
---@field spans VC.Finder.Span[] every wrapped line of the message
---@field rows VC.Finder.Chunk[][] the rows shown (the first `#rows` spans)
---@field kept integer[] bytes of each shown span that are drawn as they are
---@field first integer buffer row of the first shown line

--- The rows of one message: its label, then its text wrapped to `text_w` columns, `limit` lines at most -
--- except that the lines run on far enough to show the first match (`hit`, a byte of the text) of a query.
---@param kind "recap"|"prompt"
---@param text string
---@param text_w integer
---@param limit? integer
---@param hit? integer
---@return VC.Finder.Chunk[][] rows
---@return VC.Finder.Span[] spans
---@return integer[] kept
local function message_rows(kind, text, text_w, limit, hit)
	local spans = wrap.lines(text, text_w)
	local shown = limit and math.min(#spans, limit) or #spans
	if hit then
		for i, sp in ipairs(spans) do
			if hit >= sp.s and hit <= sp.e then
				shown = math.max(shown, i)
				break
			end
		end
	end
	local rows, kept = {}, {}
	local hl = kind == "recap" and "VCFinderListRecap" or "VCFinderListPrompt"
	for i = 1, shown do
		local piece = text:sub(spans[i].s, spans[i].e)
		kept[i] = #piece
		if i == shown and shown < #spans then
			local room = text_w - 1
			while vim.fn.strdisplaywidth(piece) > room and piece ~= "" do
				piece = vim.fn.strcharpart(piece, 0, vim.fn.strchars(piece) - 1)
			end
			kept[i] = #piece
			piece = piece .. "…"
		end
		local head = i == 1 and { text = INDENT .. LABEL[kind], hl = "VCFinderListLabel" }
			or { text = INDENT .. string.rep(" ", LABEL_COLS) }
		rows[i] = { head, { text = piece, hl = hl } }
	end
	return rows, spans, kept
end

--- Match highlights that fall inside a message, one range per matched byte.
--- The first match of a query inside a message: its byte in the message, or nil.
---@param positions integer[]
---@param at integer where the message starts in `item.text`
---@param len integer
---@return integer?
local function first_hit(positions, at, len)
	local first
	for _, p in ipairs(positions) do
		if p >= at and p < at + len and (not first or p < first) then
			first = p
		end
	end
	return first and first - at + 1
end

---@param ranges VC.Finder.Range[]
---@param positions integer[]
---@param m VC.Finder.Message
local function message_ranges(ranges, positions, m)
	for _, p in ipairs(positions) do
		local k = p - m.at + 1
		if k >= 1 and k <= m.len then
			for i = 1, #m.rows do
				local sp = m.spans[i]
				if k >= sp.s and k <= sp.e then
					if k - sp.s < m.kept[i] then
						local col = #m.rows[i][1].text + (k - sp.s)
						ranges[#ranges + 1] = { row = m.first + i - 1, s = col, e = col + 1 }
					end
					break
				end
			end
		end
	end
end

--- Sorted, with touching and overlapping ranges joined.
---@param ranges VC.Finder.Range[]
---@return VC.Finder.Range[]
local function merge(ranges)
	table.sort(ranges, function(a, b)
		if a.row ~= b.row then
			return a.row < b.row
		end
		return a.s < b.s
	end)
	local out = {}
	for _, r in ipairs(ranges) do
		local last = out[#out]
		if last and last.row == r.row and r.s <= last.e then
			last.e = math.max(last.e, r.e)
		else
			out[#out + 1] = { row = r.row, s = r.s, e = r.e }
		end
	end
	return out
end

---@class VC.Finder.FormatOpts
---@field selected? boolean the item under the cursor shows its messages in full
---@field max_rows? integer the item is cut with "…" after this many rows

--- How an item looks: a title row, a folder row (folder, branch, PR, age), the recap and the last message
--- when the session has them - each wrapped to the list width, `FOLD` lines while unselected - and a blank
--- row that separates it from the next item. The "New session" item is one row and the blank row.
---@param item VC.Finder.Item
---@param width integer
---@param opts? VC.Finder.FormatOpts
---@return VC.Finder.Lines lines
---@return VC.Finder.Range[]? ranges
function M.format(item, width, opts)
	opts = opts or {}
	if item.new then
		return { { { text = "+ New session", hl = "VCFinderListNew" } }, { { text = "" } } }
	end
	local row = item.row
	local avail = math.max(8, width - 4)
	local title, title_kept = fit(row.title, avail, "head")

	local location = M.location(row)
	local gone = row.cwd_exists == false and " (folder gone)" or ""
	local stats = M.relative_time(row.last_ts) .. "   " .. row.msg_count .. " msg"
	-- The age and count keep their place at the right; the folder and the chips share what is left. The folder
	-- keeps at least 8 columns, so a long branch gives way first.
	local left_w = width - GUTTER - #INDENT - 2 - vim.fn.strdisplaywidth(stats) - #gone
	local pr_chip = row.pr and " · #" .. row.pr or ""
	local branch = row.branch
	if branch then
		local room = left_w - 8 - vim.fn.strdisplaywidth(pr_chip) - vim.fn.strdisplaywidth(" · ")
		branch = room >= 4 and fit(branch, room, "head") or nil
	end
	local chips = (branch and " · " .. branch or "") .. pr_chip
	local shown_loc, loc_kept = fit(location, math.max(8, left_w - vim.fn.strdisplaywidth(chips)), "tail")
	local detail = { { text = INDENT .. shown_loc, hl = "VCFinderListDim" } }
	if chips ~= "" then
		detail[#detail + 1] = { text = chips, hl = "VCFinderListDim" }
	end
	if gone ~= "" then
		detail[#detail + 1] = { text = gone, hl = "VCFinderListGone" }
	end
	detail[#detail + 1] = { text = stats, hl = "VCFinderListDim", right_align = true }
	local lines = { { { text = title, hl = "VCFinderListTitle" } }, detail }

	local text_w = math.max(10, width - GUTTER - #INDENT - LABEL_COLS)
	local limit = not opts.selected and FOLD or nil
	local messages = {} ---@type VC.Finder.Message[]
	local positions = item.positions or {}
	for _, f in ipairs({ { "recap", row.recap, item.recap_at }, { "prompt", row.last_prompt, item.prompt_at } }) do
		local kind, text, at = f[1], f[2], f[3]
		if text then
			local hit = limit and at and first_hit(positions, at, #text)
			local rows, spans, kept = message_rows(kind, text, text_w, limit, hit)
			messages[#messages + 1] =
				{ at = at, len = #text, spans = spans, rows = rows, kept = kept, first = #lines + 1 }
			vim.list_extend(lines, rows)
		end
	end
	lines[#lines + 1] = { { text = "" } }

	-- `item.positions` index `item.text` (title, location, messages); map each onto the row that shows it.
	local ranges = {}
	local title_len, loc_start = #row.title, #row.title + 2
	local cut = #location - loc_kept -- bytes of the location hidden behind the leading "…"
	for _, p in ipairs(positions) do
		if p <= title_len then
			if p <= title_kept then
				ranges[#ranges + 1] = { row = 1, s = p - 1, e = p }
			end
		elseif p > loc_start and p <= loc_start + #location then
			local k = p - loc_start -- 1-based byte in the location
			if cut == 0 then
				ranges[#ranges + 1] = { row = 2, s = #INDENT + k - 1, e = #INDENT + k }
			elseif k > cut then
				local col = #INDENT + #"…" + (k - cut) - 1
				ranges[#ranges + 1] = { row = 2, s = col, e = col + 1 }
			end
		end
	end
	for _, m in ipairs(messages) do
		if m.at then
			message_ranges(ranges, positions, m)
		end
	end

	if opts.max_rows and #lines > opts.max_rows then
		for i = #lines, opts.max_rows + 1, -1 do
			lines[i] = nil
		end
		ellipsize(lines[opts.max_rows], width - GUTTER)
		ranges = vim.tbl_filter(function(r)
			return r.row <= opts.max_rows
		end, ranges)
	end
	return lines, merge(ranges)
end

return M
