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

--- Items for a list of session rows (newest first), "New session" in front when `with_new`.
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
		items[#items + 1] = { idx = #items + 1, score = 1, text = row.title .. "  " .. row.project, row = row }
	end
	return items
end

--- How an item looks: a title row and a detail row (the "New session" item is one row).
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
	local title = row.title
	local kept = #title
	if vim.fn.strdisplaywidth(title) > avail then
		local cut = vim.fn.strcharpart(title, 0, avail - 1)
		kept = #cut
		title = cut .. "…"
	end
	local project = row.project
	local detail = { { text = "  " .. project, hl = "VCFinderListDim" } }
	if row.cwd_exists == false then
		detail[#detail + 1] = { text = " (folder gone)", hl = "VCFinderListGone" }
	end
	detail[#detail + 1] = {
		text = M.relative_time(row.last_ts) .. "   " .. row.msg_count .. " msg",
		hl = "VCFinderListDim",
		right_align = true,
	}

	local ranges = {}
	local title_len = #row.title
	for _, p in ipairs(item.positions or {}) do
		if p <= title_len then
			if p <= kept then
				ranges[#ranges + 1] = { row = 1, s = p - 1, e = p }
			end
		elseif p >= title_len + 3 then
			local col = 2 + (p - (title_len + 2)) - 1
			ranges[#ranges + 1] = { row = 2, s = col, e = col + 1 }
		end
	end
	return { { { text = title, hl = "VCFinderListTitle" } }, detail }, ranges
end

return M
