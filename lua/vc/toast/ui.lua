local Record = require("vc.toast.record")
local View = require("vc.finder.view")
local animate = require("vc.animate")
local config = require("vc.toast.config")

---@class VC.Toast.View : VC.Finder.View
---@field ns integer
---@field record VC.Toast.Record
---@field timer? uv.uv_timer_t  auto-dismiss timer (restarted when an identical toast merges in)
---@field closing? boolean     fading out; repeats open a new toast instead of merging
---@overload fun(buf?: integer, win?: integer, ns: integer, record: VC.Toast.Record): VC.Toast.View
local ToastView = View.Instance:extend(
	---@param obj VC.Toast.View
	function(obj, ns, record)
		obj.ns = ns
		obj.record = record
	end
)

-- =============================================================================
-- UTILS
-- =============================================================================

---Trim to a display-width budget, append ellipsis if truncated.
---@param s string
---@param maxw integer
---@return string
local function trim_to_width(s, maxw)
	if vim.fn.strdisplaywidth(s) <= maxw then
		return s
	end
	local take = math.max(0, maxw - 1)
	return vim.fn.strcharpart(s, 0, take) .. "…"
end

-- =============================================================================
-- VIEW
-- =============================================================================

local M = {}

---@param record VC.Toast.Record
---@param bottom_row integer  row of the bottom edge (SE anchor)
---@return VC.Toast.View
function M.create(record, bottom_row)
	local buf = View.new_buf("vc-toast")

	local width, height = record:dimensions()

	local win = vim.api.nvim_open_win(buf, false, {
		relative = "editor",
		anchor = "SE",
		row = bottom_row,
		col = vim.o.columns - config.padding_right,
		width = width,
		height = height,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 200,
		noautocmd = true,
	})
	View.wo(win, "wrap", false)
	View.wo(win, "winhl", "Normal:VCToastNormal")
	View.wo(win, "winblend", 100) -- start transparent; fade_in animates to 0

	local ns = vim.api.nvim_create_namespace("vc_toast_" .. record.id)
	return ToastView(buf, win, ns, record)
end

---@param view VC.Toast.View
function M.render(view)
	-- stylua: ignore
	if not view:is_valid() then return end

	local r = view.record

	local title_str = r.title or ""
	local title_w = (title_str ~= "" and (1 + vim.fn.strdisplaywidth(title_str)) or 0)
	local icon_str = r.icon or ""
	local icon_w = (icon_str ~= "" and (1 + vim.fn.strdisplaywidth(icon_str)) or 0)
	local width, _ = r:dimensions()
	local inner_w = math.max(0, width - (title_w + icon_w))

	-- Trim the message first so the count is never the part that gets cut.
	local count_text = r.count > 1 and (" " .. Record.count_label(r.count)) or ""
	local body_text = trim_to_width(config.normalize_message(r.message), inner_w - #count_text) .. count_text

	-- Float width may need to grow/shrink for in-place updates (a merged repeat grows the line).
	local cur = vim.api.nvim_win_get_config(view.win)
	if cur.width ~= width then
		pcall(vim.api.nvim_win_set_config, view.win, {
			relative = "editor",
			anchor = "SE",
			row = cur.row,
			col = cur.col,
			width = width,
			height = 1,
		})
	end

	local body_w = vim.fn.strdisplaywidth(body_text)
	local pad = math.max(0, inner_w - body_w)
	local line = body_text .. string.rep(" ", pad)
	if title_str ~= "" then
		line = line .. " " .. title_str
	end
	if icon_str ~= "" then
		line = line .. " " .. icon_str
	end
	pcall(vim.api.nvim_buf_set_lines, view.buf, 0, -1, false, { line })

	-- Apply highlights.
	local ns = vim.api.nvim_create_namespace("vc_toast_hl")
	vim.api.nvim_buf_clear_namespace(view.buf, ns, 0, -1)

	local body_bytes = #body_text + pad
	if body_bytes > 0 then
		local body_hl = r.dim and "Comment" or "VCToastBody"
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, 0, { end_row = 0, end_col = body_bytes, hl_group = body_hl })
	end
	if count_text ~= "" then
		local count_start = #body_text - #count_text + 1 -- skip the separating space
		vim.api.nvim_buf_set_extmark(
			view.buf,
			ns,
			0,
			count_start,
			{ end_row = 0, end_col = #body_text, hl_group = "VCToastCount", priority = 200 }
		)
	end

	local hl_title = "VCToastTitle" .. r.level
	local col = #body_text + pad
	if title_str ~= "" then
		local tbytes = #(" " .. title_str)
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, col, { end_row = 0, end_col = col + tbytes, hl_group = hl_title })
		col = col + tbytes
	end

	if icon_str ~= "" then
		local ibytes = #(" " .. icon_str)
		vim.api.nvim_buf_set_extmark(view.buf, ns, 0, col, { end_row = 0, end_col = col + ibytes, hl_group = hl_title })
	end
end

---@param view VC.Toast.View
function M.close(view)
	view:close()
end

---@param view VC.Toast.View
---@param bottom_row integer
function M.move(view, bottom_row)
	-- stylua: ignore
	if not view:is_valid() then return end
	pcall(vim.api.nvim_win_set_config, view.win, {
		relative = "editor",
		anchor = "SE",
		row = bottom_row,
		col = vim.o.columns - config.padding_right,
	})
end

---@param view VC.Toast.View
function M.fade_in(view)
	-- stylua: ignore
	if not view:is_valid() then return end
	local start_blend = vim.wo[view.win].winblend or 100
	animate.run(view.win, { blend = start_blend }, { blend = 0 }, config.anim_ms, nil, { blend_delay = 0 })
end

---@param view VC.Toast.View
---@param on_done? fun()
function M.fade_out(view, on_done)
	if not view:is_valid() then
		if on_done then
			on_done()
		end
		return
	end
	local start_blend = vim.wo[view.win].winblend or 0
	animate.run(view.win, { blend = start_blend }, { blend = 100 }, config.anim_ms, on_done, { blend_delay = 0 })
end

return M
