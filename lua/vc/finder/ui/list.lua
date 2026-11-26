--- The session list. Rows are virtual: only the visible slice of items is written to the
--- buffer. An item may span several buffer rows (a session is a title row and a detail row).
local View = require("vc.finder.view")
local config = require("vc.finder.config")

---@alias VC.Finder.Chunk { text: string, hl?: string, right_align?: boolean }
---@alias VC.Finder.Lines VC.Finder.Chunk[][] one array of chunks per buffer row of the item
---@alias VC.Finder.Range { row: integer, s: integer, e: integer } match highlight: 1-based item row, 0-based byte columns [s, e)
---@alias VC.Finder.FormatFn fun(item: VC.Finder.Item, width: integer, opts: VC.Finder.FormatOpts): VC.Finder.Lines, VC.Finder.Range[]?

---@class VC.Finder.ListView: VC.Finder.View
---@field ns integer
---@field prefix_ns integer
---@field items VC.Finder.Item[]
---@field cursor integer 1-based index into items
---@field _format_fn? VC.Finder.FormatFn
---@field _offset integer 0-based index of the first visible item
---@field _win_height integer
---@field _visible_last integer last item index drawn
---@field _row_to_item table<integer, integer> 1-based buffer row -> item index
local ListView = View.Instance:extend(function(obj, ns)
	obj.ns = ns
	obj.prefix_ns = vim.api.nvim_create_namespace("")
	obj.items = {}
	obj.cursor = 1
	obj._offset = 0
	obj._win_height = 0
	obj._visible_last = 0
	obj._row_to_item = {}
end)

-- Above Neovim's default extmark priority (4096), which the selected row's background and every chunk's
-- own colour use: a match must show its colours over both.
local MATCH_PRIORITY = 4200

---@class VC.Finder.UI.List
local M = {}

---@param geo VC.Finder.Layout.Geometry
---@param footer? string
---@return VC.Finder.ListView
function M.create(geo, footer)
	local buf = View.new_buf("vc-finder-list")
	local ns = vim.api.nvim_create_namespace("vc-finder-list")
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = geo.w,
		height = geo.h,
		row = geo.row,
		col = geo.col,
		style = "minimal",
		border = geo.border,
		zindex = 101,
	})
	View.wo(win, "cursorline", false)
	View.wo(win, "scrolloff", 0)
	View.wo(win, "wrap", false)
	View.wo(win, "fillchars", "eob: ")
	View.wo(win, "winhl", "Normal:VCFinderNormal,FloatBorder:VCFinderBorder")
	local view = ListView(buf, win, ns)
	if footer then
		M.set_footer(view, footer)
	end
	return view
end

--- Key hints drawn in the bottom border of the list.
---@param view VC.Finder.ListView
---@param footer string
function M.set_footer(view, footer)
	-- stylua: ignore
	if not view:is_valid() then return end
	pcall(
		vim.api.nvim_win_set_config,
		view.win,
		{ footer = { { " " .. footer .. " ", "VCFinderHint" } }, footer_pos = "left" }
	)
end

--- How item `idx` looks now: the one under the cursor is open, and none is taller than the window.
---@param view VC.Finder.ListView
---@param idx integer
---@param width integer
---@return VC.Finder.Lines
---@return VC.Finder.Range[]?
local function format_item(view, idx, width)
	return view._format_fn(view.items[idx], width, { selected = idx == view.cursor, max_rows = view._win_height })
end

---@param view VC.Finder.ListView
---@param idx integer
---@return integer
local function height_of(view, idx)
	return #(format_item(view, idx, vim.api.nvim_win_get_width(view.win)))
end

--- Last item index that fits when the viewport starts at `offset` (0-based).
---@param view VC.Finder.ListView
---@param offset integer
---@return integer
local function last_visible(view, offset)
	local rows, idx = 0, offset + 1
	while idx <= #view.items do
		local h = height_of(view, idx)
		if rows + h > view._win_height and rows > 0 then
			break
		end
		rows = rows + h
		idx = idx + 1
	end
	return math.max(offset, idx - 1)
end

--- Offset (0-based) that makes `cursor` the last fully visible item.
---@param view VC.Finder.ListView
---@param cursor integer
---@return integer
local function offset_for_cursor(view, cursor)
	local rows, idx = 0, cursor
	while idx >= 1 do
		local h = height_of(view, idx)
		if rows + h > view._win_height then
			break
		end
		rows = rows + h
		idx = idx - 1
	end
	return math.min(idx, cursor - 1)
end

---@param view VC.Finder.ListView
local function clamp_offset(view)
	-- stylua: ignore
	if #view.items == 0 then view._offset = 0 return end
	if view.cursor - 1 < view._offset then
		view._offset = view.cursor - 1
	elseif view.cursor > last_visible(view, view._offset) then
		view._offset = offset_for_cursor(view, view.cursor)
	end
end

---@param chunks VC.Finder.Chunk[]
---@return string
local function line_text(chunks)
	local parts = {}
	for _, c in ipairs(chunks) do
		if not c.right_align then
			parts[#parts + 1] = c.text
		end
	end
	return table.concat(parts)
end

--- Write the visible slice of items to the buffer, with highlights and the selection marker.
---@param view VC.Finder.ListView
local function render_visible(view)
	-- stylua: ignore
	if not view:is_valid() or not view._format_fn then return end
	local width = vim.api.nvim_win_get_width(view.win)
	local sel_prefix = config.selection_prefix .. " "
	local pad = string.rep(" ", vim.fn.strdisplaywidth(sel_prefix))

	local lines, chunk_rows, first_rows, ranges_by_row = {}, {}, {}, {}
	local row_to_item = {}
	local rows, idx = 0, view._offset + 1
	while idx <= #view.items do
		local item_lines, ranges = format_item(view, idx, width)
		if rows + #item_lines > view._win_height and rows > 0 then
			break
		end
		first_rows[idx] = rows + 1
		for r, chunks in ipairs(item_lines) do
			rows = rows + 1
			lines[rows] = line_text(chunks)
			chunk_rows[rows] = chunks
			row_to_item[rows] = idx
			for _, rg in ipairs(ranges or {}) do
				if rg.row == r then
					ranges_by_row[rows] = ranges_by_row[rows] or {}
					table.insert(ranges_by_row[rows], rg)
				end
			end
		end
		idx = idx + 1
	end
	view._row_to_item = row_to_item
	view._visible_last = idx - 1

	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)

	local cursor_first = first_rows[view.cursor]
	for r = 1, rows do
		local selected = row_to_item[r] == view.cursor
		vim.api.nvim_buf_set_extmark(view.buf, view.prefix_ns, r - 1, 0, {
			virt_text = { { (selected and r == cursor_first) and sel_prefix or pad, "VCFinderListSelectionPrefix" } },
			virt_text_pos = "inline",
			hl_mode = "combine",
		})
		if selected then
			vim.api.nvim_buf_set_extmark(view.buf, view.ns, r - 1, 0, { line_hl_group = "VCFinderListCursorLine" })
		end
		local col = 0
		for _, c in ipairs(chunk_rows[r]) do
			if c.right_align then
				vim.api.nvim_buf_set_extmark(view.buf, view.ns, r - 1, 0, {
					virt_text = { { c.text, c.hl or "VCFinderNormal" } },
					virt_text_pos = "right_align",
					hl_mode = "combine",
				})
			else
				if c.hl then
					vim.api.nvim_buf_set_extmark(
						view.buf,
						view.ns,
						r - 1,
						col,
						{ end_col = col + #c.text, hl_group = c.hl }
					)
				end
				col = col + #c.text
			end
		end
		for _, rg in ipairs(ranges_by_row[r] or {}) do
			vim.api.nvim_buf_set_extmark(
				view.buf,
				view.ns,
				r - 1,
				rg.s,
				{ end_col = rg.e, hl_group = "VCFinderListMatch", priority = MATCH_PRIORITY }
			)
		end
	end
	pcall(vim.api.nvim_win_set_cursor, view.win, { cursor_first or 1, 0 })
end

---@param view VC.Finder.ListView
---@param text string
local function render_empty(view, text)
	view._row_to_item = {}
	view._visible_last = 0
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, { " " .. text })
	vim.bo[view.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	vim.api.nvim_buf_clear_namespace(view.buf, view.prefix_ns, 0, -1)
	vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, { end_col = #text + 1, hl_group = "VCFinderListDim" })
end

---@param view VC.Finder.ListView
---@param items VC.Finder.Item[]
---@param format_fn VC.Finder.FormatFn
---@param empty_text? string shown instead of rows when `items` is empty
function M.render(view, items, format_fn, empty_text)
	-- stylua: ignore
	if not view:is_valid() then return end
	view.items = items
	if #items == 0 and empty_text then
		view.cursor = 1
		view._offset = 0
		render_empty(view, empty_text)
		return
	end
	view._format_fn = format_fn
	view._win_height = vim.api.nvim_win_get_height(view.win)
	view.cursor = math.min(view.cursor, math.max(1, #items))
	clamp_offset(view)
	render_visible(view)
end

---@param view VC.Finder.ListView
---@param idx integer 1-based
function M.set_cursor(view, idx)
	-- stylua: ignore
	if not view:is_valid() or #view.items == 0 then return end
	view.cursor = math.max(1, math.min(idx, #view.items))
	clamp_offset(view)
	render_visible(view)
end

---@param view VC.Finder.ListView
---@param delta integer positive = down, negative = up
function M.move(view, delta)
	-- stylua: ignore
	if #view.items == 0 then return end
	local new_idx = view.cursor + delta
	if new_idx > #view.items then
		new_idx = 1
	elseif new_idx < 1 then
		new_idx = #view.items
	end
	M.set_cursor(view, new_idx)
end

---@param view VC.Finder.ListView
---@return VC.Finder.Item?
function M.selected(view)
	return view.items[view.cursor]
end

--- Item index shown on a 1-based buffer row.
---@param view VC.Finder.ListView
---@param buf_row integer
---@return integer?
function M.item_at_row(view, buf_row)
	return view._row_to_item[buf_row]
end

return M
