local View = require("vc.finder.view")
local config = require("vc.finder.config")
local debounce = require("vc.debounce")

local SPINNER = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local SPINNER_INTERVAL_MS = 80

---@class VC.Finder.InputView: VC.Finder.View
---@field ns integer
---@field _debounced? table
---@field _on_change fun()
---@field _spinner_timer? uv.uv_timer_t
---@field _spinner_frame integer
---@field _spinner_extmark? integer
---@field _count_extmark? integer
local InputView = View.Instance:extend(function(obj, ns)
	obj.ns = ns
	obj._spinner_frame = 0
end)

---@class VC.Finder.UI.Input
local M = {}

---@param on_change fun(text: string)
---@param geo VC.Finder.Layout.Geometry
---@param title string
function M.create(on_change, geo, title)
	local buf = View.new_buf("vc-finder-input")
	vim.bo[buf].buftype = "prompt"
	local ns = vim.api.nvim_create_namespace("vc-finder-input")

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		width = geo.w,
		height = geo.h,
		row = geo.row,
		col = geo.col,
		style = "minimal",
		border = geo.border,
		title = " " .. title .. " ",
		title_pos = "center",
		zindex = 103,
	})
	View.wo(win, "cursorline", false)
	View.wo(win, "winhl", "Normal:VCFinderNormal,FloatBorder:VCFinderBorder,FloatTitle:VCFinderInputTitle")

	local view = InputView(buf, win, ns)
	local prefix = config.prompt_prefix
	vim.fn.prompt_setprompt(buf, prefix)

	view._on_change = function()
		-- stylua: ignore
		if not view:is_valid() then return end
		on_change(M.get_text(view))
	end
	view._debounced = debounce(config.debounce.normal_ms, view._on_change)
	vim.api.nvim_create_autocmd({ "TextChangedI", "TextChanged" }, {
		buffer = buf,
		callback = function()
			view._debounced()
		end,
	})
	vim.api.nvim_create_autocmd("BufWipeout", {
		buffer = buf,
		once = true,
		callback = function()
			if view._debounced then
				view._debounced:close()
				view._debounced = nil
			end
			M.stop_spinner(view)
		end,
	})
	vim.cmd("startinsert!")
	return view
end

---@param view VC.Finder.InputView
---@return string
function M.get_text(view)
	-- stylua: ignore
	if not view:is_valid() then return "" end
	local text = vim.api.nvim_buf_get_lines(view.buf, 0, 1, false)[1] or ""
	local prefix = config.prompt_prefix
	if text:sub(1, #prefix) == prefix then
		text = text:sub(#prefix + 1)
	end
	return text
end

--- Show (or with nil, clear) a right-aligned dim label in the prompt row, e.g. the result count.
---@param view VC.Finder.InputView
---@param text? string
function M.set_count(view, text)
	-- stylua: ignore
	if not view:is_valid() then return end
	if view._count_extmark then
		pcall(vim.api.nvim_buf_del_extmark, view.buf, view.ns, view._count_extmark)
		view._count_extmark = nil
	end
	if text and text ~= "" then
		view._count_extmark = vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, {
			virt_text = { { text, "VCFinderListDim" } },
			virt_text_pos = "right_align",
		})
	end
end

--- Show a spinning indicator right-aligned in the prompt (the index is still scanning).
---@param view VC.Finder.InputView
function M.start_spinner(view)
	-- stylua: ignore
	if view._spinner_timer and not view._spinner_timer:is_closing() then return end
	view._spinner_timer = assert(vim.uv.new_timer(), "failed to create spinner timer")
	local function tick()
		-- stylua: ignore
		if not view:is_valid() then return end
		view._spinner_frame = (view._spinner_frame % #SPINNER) + 1
		if view._spinner_extmark then
			pcall(vim.api.nvim_buf_del_extmark, view.buf, view.ns, view._spinner_extmark)
		end
		view._spinner_extmark = vim.api.nvim_buf_set_extmark(view.buf, view.ns, 0, 0, {
			virt_text = { { SPINNER[view._spinner_frame] .. " ", "VCFinderSpinner" } },
			virt_text_pos = "right_align",
		})
	end
	tick()
	view._spinner_timer:start(SPINNER_INTERVAL_MS, SPINNER_INTERVAL_MS, vim.schedule_wrap(tick))
end

---@param view VC.Finder.InputView
function M.stop_spinner(view)
	if view._spinner_timer and not view._spinner_timer:is_closing() then
		view._spinner_timer:stop()
		view._spinner_timer:close()
	end
	view._spinner_timer = nil
	if view._spinner_extmark and view:is_valid() then
		pcall(vim.api.nvim_buf_del_extmark, view.buf, view.ns, view._spinner_extmark)
		view._spinner_extmark = nil
	end
end

return M
