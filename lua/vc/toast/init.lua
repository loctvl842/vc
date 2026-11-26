local Record = require("vc.toast.record")
local State = require("vc.toast.state")
local config = require("vc.toast.config")
local stack = require("vc.toast.stack")

local state = State()

---@class VC.Toast
---@overload fun(message: string|string[], level?: string|integer, opts?: VC.Toast.Options): VC.Toast.Record|{}
local M = setmetatable({}, {
	__call = function(self, m, l, o)
		-- Building a record calls vim.fn, which a fast event (timer, job callback) may not do.
		if vim.in_fast_event() then
			vim.schedule(function()
				self.toast(m, l, o)
			end)
			return
		end
		return self.toast(m, l, o)
	end,
})

function M.setup(opts)
	config.setup(opts)
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("VCToast", { clear = true }),
		callback = function()
			stack.relayout(state)
		end,
	})
end

function M.dismiss()
	stack.dismiss(state)
end

---@param message string|string[]
---@param level? string|integer
---@param opts? VC.Toast.Options
---@return VC.Toast.Record|{}
function M.toast(message, level, opts)
	local level_num = vim.log.levels[config.normalize_level(level or "INFO")]
	if level_num < config.level then
		return {}
	end

	-- Record construction is pure Lua, safe in any context, so return it
	-- immediately so callers can use it as a handle. The actual UI work
	-- (open_win, etc.) is always scheduled by stack.drain to avoid E565
	-- in textlock contexts (fast events, BufRead autocmds, cmdwin, ...).
	local record = Record(state.next_id, message, level, opts)
	state.next_id = state.next_id + 1

	stack.push(state, record)
	return record
end

return M
