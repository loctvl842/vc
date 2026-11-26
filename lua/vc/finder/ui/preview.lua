--- The conversation preview. It shows a whole transcript (see vc.transcript); tool calls, tool
--- results and thinking are folded away at first and open with the usual fold keys.
local View = require("vc.finder.view")
local transcript = require("vc.transcript")

---@class VC.Finder.PreviewView: VC.Finder.View
---@field ns integer
---@field shown? string id of the session now shown (or being rendered)
---@field _cancel? fun() cancels the render in flight
local PreviewView = View.Instance:extend(function(obj, ns)
	obj.ns = ns
end)

---@class VC.Finder.UI.Preview
local M = {}

local CACHE_SIZE = 4

---@type table<integer, { level: table<integer, string>, label: table<integer, string> }> fold data per buffer
local fold_data = {}
---@type { id: string, lines: string[], folds: VC.Fold[] }[] most recently shown first; `id` includes size and mtime so a resumed session is read again
local cache = {}

--- 'foldexpr' of the preview: folds come from the transcript's fold map.
---@return string
function M.foldexpr()
	local d = fold_data[vim.api.nvim_get_current_buf()]
	return d and d.level[vim.v.lnum] or "0"
end

--- 'foldtext' of the preview: the fold's label, with how many lines are tucked away.
---@return string
function M.foldtext()
	local d = fold_data[vim.api.nvim_get_current_buf()]
	local label = d and d.label[vim.v.foldstart] or "▸ details"
	return label .. " (" .. (vim.v.foldend - vim.v.foldstart + 1) .. " lines)"
end

---@param geo VC.Finder.Layout.Geometry
---@return VC.Finder.PreviewView
function M.create(geo)
	local buf = View.new_buf("vc-finder-preview")
	local ns = vim.api.nvim_create_namespace("vc-finder-preview")
	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		width = geo.w,
		height = geo.h,
		row = geo.row,
		col = geo.col,
		style = "minimal",
		border = { "┬", "─", "╮", "│", "╯", "─", "┴", "│" },
		zindex = 102,
	})
	View.wo(
		win,
		"winhl",
		"Normal:VCFinderNormal,FloatBorder:VCFinderBorder,FloatTitle:VCFinderPreviewTitle,Folded:VCFinderPreviewFold"
	)
	View.wo(win, "wrap", true)
	View.wo(win, "linebreak", true)
	View.wo(win, "number", false)
	View.wo(win, "foldmethod", "expr")
	View.wo(win, "foldexpr", "v:lua.require'vc.finder.ui.preview'.foldexpr()")
	View.wo(win, "foldtext", "v:lua.require'vc.finder.ui.preview'.foldtext()")
	View.wo(win, "foldlevel", 0)
	View.wo(win, "foldenable", true)
	View.wo(win, "foldcolumn", "0")
	View.wo(win, "fillchars", "fold: ,eob: ")
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			fold_data[buf] = nil
		end,
	})
	return PreviewView(buf, win, ns)
end

---@param view VC.Finder.PreviewView
---@param title string
local function set_title(view, title)
	pcall(
		vim.api.nvim_win_set_config,
		view.win,
		{ title = title ~= "" and (" " .. title .. " ") or "", title_pos = "center" }
	)
end

---@param view VC.Finder.PreviewView
---@param lines string[]
---@param folds VC.Fold[]
local function set_content(view, lines, folds)
	-- stylua: ignore
	if not view:is_valid() then return end
	local level, label = {}, {}
	for _, f in ipairs(folds) do
		level[f.start] = ">1"
		label[f.start] = f.label
		for l = f.start + 1, f.stop do
			level[l] = "1"
		end
	end
	fold_data[view.buf] = { level = level, label = label }
	vim.bo[view.buf].modifiable = true
	vim.api.nvim_buf_set_lines(view.buf, 0, -1, false, lines)
	vim.bo[view.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(view.buf, view.ns, 0, -1)
	-- Tool calls, results and thinking keep their background when a fold is opened.
	for _, f in ipairs(folds) do
		for l = f.start, f.stop do
			vim.api.nvim_buf_set_extmark(view.buf, view.ns, l - 1, 0, { line_hl_group = "VCFinderPreviewTool" })
		end
	end
	local speaker
	for i, l in ipairs(lines) do
		local hl
		if l == "## You" then
			hl, speaker = "VCFinderPreviewYou", "You"
		elseif l == "## Claude" then
			hl, speaker = "VCFinderPreviewClaude", "Claude"
		elseif i == 1 and l:sub(1, 2) == "# " then
			hl = "VCFinderPreviewHeading"
		elseif i == 2 then
			hl = "VCFinderListDim"
		end
		if hl then
			vim.api.nvim_buf_set_extmark(view.buf, view.ns, i - 1, 0, { line_hl_group = hl })
		end
	end
	vim.api.nvim_win_call(view.win, function()
		vim.cmd("normal! zx") -- recompute folds, all closed
		vim.cmd("normal! gg")
	end)
	pcall(vim.api.nvim_win_set_cursor, view.win, { 1, 0 })
end

---@param id string
---@return { lines: string[], folds: VC.Fold[] }?
local function cache_get(id)
	for i, e in ipairs(cache) do
		if e.id == id then
			table.remove(cache, i)
			table.insert(cache, 1, e)
			return e
		end
	end
end

---@param view VC.Finder.PreviewView
local function cancel(view)
	if view._cancel then
		view._cancel()
		view._cancel = nil
	end
end

--- Show a text note (e.g. for the "New session" row).
---@param view VC.Finder.PreviewView
---@param title string
---@param lines string[]
function M.note(view, title, lines)
	-- stylua: ignore
	if not view:is_valid() then return end
	cancel(view)
	view.shown = nil
	set_title(view, title)
	set_content(view, lines, {})
end

--- Show the whole conversation of a session.
---@param view VC.Finder.PreviewView
---@param row VC.Row
function M.show(view, row)
	local key = row.id .. ":" .. row.size .. ":" .. row.mtime
	-- stylua: ignore
	if not view:is_valid() or view.shown == key then return end
	cancel(view)
	view.shown = key
	set_title(view, row.title)
	local hit = cache_get(key)
	if hit then
		set_content(view, hit.lines, hit.folds)
		return
	end
	set_content(view, { "Loading..." }, {})
	view._cancel = transcript.render_file(row.path, row, function(lines, folds)
		view._cancel = nil
		table.insert(cache, 1, { id = key, lines = lines, folds = folds })
		cache[CACHE_SIZE + 1] = nil
		if view.shown == key then
			set_content(view, lines, folds)
		end
	end)
end

---@param view VC.Finder.PreviewView
function M.clear(view)
	-- stylua: ignore
	if not view:is_valid() then return end
	cancel(view)
	view.shown = nil
	set_title(view, "")
	set_content(view, {}, {})
end

return M
