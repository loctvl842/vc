local Record = require("vc.notify.record")
local State = require("vc.notify.state")
local config = require("vc.notify.config")
local stack = require("vc.notify.stack")

local state = State()

local M = setmetatable({}, {
	__call = function(self, m, l, o)
		if vim.in_fast_event() or vim.fn.has("vim_starting") == 1 then
			vim.schedule(function()
				self.notify(m, l, o)
			end)
			return
		end

		return self.notify(m, l, o)
	end,
})

function M.setup(opts)
	require("vc.notify.highlights").setup()
	config.setup(opts)
	-- Through the callable, so a call from a fast event is scheduled instead of opening windows there.
	vim.notify = function(...)
		return M(...)
	end
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("VCNotify", { clear = true }),
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
---@param opts? VC.Notify.Options
function M.notify(message, level, opts)
	local level_num = vim.log.levels[config.normalize_level(level or "INFO")]
	if level_num < config.level then
		return {}
	end

	local record = Record(state.next_id, message, level, opts)
	state.next_id = state.next_id + 1

	stack.push(state, record)
	return record
end

return M
