local config = require("vc.notify.config")
local ui = require("vc.notify.ui")

local M = {}

-- =============================================================================
-- UTILS
-- =============================================================================

---First usable row, accounting for tabline.
---@return integer
local function top_row()
	local top = 0
	if vim.o.showtabline == 2 or (vim.o.showtabline == 1 and vim.fn.tabpagenr("$") > 1) then
		top = 1
	end
	return top
end

---Compute top-border row for each view, stacking top-down.
---views[1] = topmost (oldest), views[#] = bottommost (newest). A view that is sliding out keeps the row
---it has and takes no room, so the cards that stay close the gap at once.
---@param views VC.Notify.View[]
---@return integer[] slots, integer bottom first free row below the stack
local function calc_slots(views)
	local slots = {}
	local cursor = top_row()
	for i = 1, #views do
		slots[i] = cursor
		if not views[i].leaving then
			local _, h = views[i].record:dimensions()
			cursor = cursor + h + config.gap + 2
		end
	end
	return slots, cursor
end

---Rows a notification takes on screen: its lines, the title row and the border.
---@param record VC.Notify.Record
---@return integer
local function outer_height(record)
	local _, h = record:dimensions()
	return h + 2
end

-- =============================================================================
-- MAIN
-- =============================================================================

---Recalculate and move all open views to their correct rows.
---@param state VC.Notify.State
function M.reflow(state)
	local slots = calc_slots(state.views)
	for i, view in ipairs(state.views) do
		if not view.leaving then
			ui.move(view, slots[i])
		end
	end
end

---The terminal changed size: refit every open card and restack.
---@param state VC.Notify.State
function M.relayout(state)
	for _, view in ipairs(state.views) do
		if not view.leaving then
			ui.resize(view)
		end
	end
	M.reflow(state)
end

---@param state VC.Notify.State
---@param record VC.Notify.Record
local function show(state, record)
	-- Make room: when the stack would run past the bottom of the screen the oldest cards slide out early.
	local limit = vim.o.lines - vim.o.cmdheight
	for _, old in ipairs(state.views) do
		local _, bottom = calc_slots(state.views)
		if bottom + outer_height(record) <= limit then
			break
		end
		if not old.leaving then
			M.remove(state, old.record.id)
		end
	end
	local _, slot_row = calc_slots(state.views)
	local view = ui.create(record, slot_row)
	table.insert(state.views, view)
	ui.render(view)
	ui.fade_in(view)

	if record.timeout ~= false then
		local index = #state.views
		local bonus = math.floor(math.sqrt(index * index * index) * config.stagger)
		local timeout = record.timeout + bonus
		vim.defer_fn(function()
			local _, view = state:find(record.id)
			-- If window is focus
			if view and view:is_valid() and vim.api.nvim_get_current_win() == view.win then
				vim.api.nvim_create_autocmd("WinLeave", {
					once = true,
					callback = function()
						vim.defer_fn(function()
							M.remove(state, record.id)
						end, 2000)
					end,
				})
				return
			end
			M.remove(state, record.id)
		end, timeout)
	end
end

---@param state VC.Notify.State
function M.drain(state)
	if state.draining then
		return
	end

	local record = table.remove(state.queue, 1)
	if not record then
		return
	end

	state.draining = true
	show(state, record)

	vim.defer_fn(function()
		state.draining = false
		M.drain(state)
	end, config.stagger)
end

---Queue a notification to be shown with staggered delay.
---@param state VC.Notify.State
---@param record VC.Notify.Record
function M.push(state, record)
	table.insert(state.queue, record)
	M.drain(state)
end

---Slide out one notification, close it when done.
---@param state VC.Notify.State
---@param id integer
function M.remove(state, id)
	local idx, view = state:find(id)
	-- stylua: ignore
	if not idx or view.leaving then return end

	view.leaving = true
	M.reflow(state)
	ui.slide_out(view, function()
		local cur_idx = state:find(id)
		if cur_idx then
			table.remove(state.views, cur_idx)
		end
		ui.close(view)
		M.reflow(state)
	end)
end

---Close all open notifications.
---@param state VC.Notify.State
function M.dismiss(state)
	local ids = {}
	for _, v in ipairs(state.views) do
		ids[#ids + 1] = v.record.id
	end
	for _, id in ipairs(ids) do
		M.remove(state, id)
	end
end

return M
