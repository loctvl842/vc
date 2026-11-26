--- The one source of the finder: Claude Code sessions (see vc.sessions.index).
local M = {}

M.title = "Claude Sessions"
M.footer = "<CR> continue   <C-n>/<C-p> move   <C-l> preview   <Esc> exit"
M.footer_empty = "<Esc> exit"

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
--- The search text is the title, the location and the recap (when there is one), in that order;
--- the recap matches only as a substring (see `fuzzy_len`).
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
		local fuzzy_len = row.recap and #text
		if row.recap then
			text = text .. "  " .. row.recap
		end
		items[#items + 1] = { idx = #items + 1, score = 1, text = text, fuzzy_len = fuzzy_len, row = row }
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

--- How an item looks: a title row, a detail row (location and age), and a recap row when the session has one.
--- The "New session" item is one row.
---@param item VC.Finder.Item
---@param width integer
---@return VC.Finder.Lines lines
---@return VC.Finder.Range[]? ranges
function M.format(item, width)
	if item.new then
		return { { { text = "+ New session", hl = "VCFinderListNew" } } }
	end
	local row = item.row
	local avail = math.max(8, width - 4)
	local title, title_kept = fit(row.title, avail, "head")

	local location = M.location(row)
	local gone = row.cwd_exists == false and " (folder gone)" or ""
	local stats = M.relative_time(row.last_ts) .. "   " .. row.msg_count .. " msg"
	local loc_avail = math.max(8, width - 4 - #gone - 2 - vim.fn.strdisplaywidth(stats))
	local shown_loc, loc_kept = fit(location, loc_avail, "tail")
	local detail = { { text = "  " .. shown_loc, hl = "VCFinderListDim" } }
	if gone ~= "" then
		detail[#detail + 1] = { text = gone, hl = "VCFinderListGone" }
	end
	detail[#detail + 1] = { text = stats, hl = "VCFinderListDim", right_align = true }
	local lines = { { { text = title, hl = "VCFinderListTitle" } }, detail }

	local recap_start, recap_kept
	if row.recap then
		local shown
		shown, recap_kept = fit(row.recap, avail, "head")
		lines[3] = { { text = "  " .. shown, hl = "VCFinderListRecap" } }
		recap_start = #row.title + 2 + #location + 2
	end

	-- `item.positions` index `item.text` (title, location, recap); map each onto the row that shows it.
	local ranges = {}
	local title_len, loc_start = #row.title, #row.title + 2
	local cut = #location - loc_kept -- bytes of the location hidden behind the leading "…"
	for _, p in ipairs(item.positions or {}) do
		if p <= title_len then
			if p <= title_kept then
				ranges[#ranges + 1] = { row = 1, s = p - 1, e = p }
			end
		elseif p > loc_start and p <= loc_start + #location then
			local k = p - loc_start -- 1-based byte in the location
			if cut == 0 then
				ranges[#ranges + 1] = { row = 2, s = 2 + k - 1, e = 2 + k }
			elseif k > cut then
				local col = 2 + #"…" + (k - cut) - 1
				ranges[#ranges + 1] = { row = 2, s = col, e = col + 1 }
			end
		elseif recap_start and p > recap_start and p <= recap_start + recap_kept then
			local col = 2 + (p - recap_start) - 1
			ranges[#ranges + 1] = { row = 3, s = col, e = col + 1 }
		end
	end
	return lines, ranges
end

return M
