-- Message UI: enables Neovim's ui2 (no hit-enter prompt with cmdheight = 0) and turns every message it
-- would print into a notification card.
--
-- ui2 looks its handlers up at call time (`M.msg[event]`), so replacing
-- `ui2.messages.msg_show` intercepts every message without a custom cmdline UI.
-- ui2 is experimental; everything here is gated and falls back to ui2's own
-- behavior on any error.

local config = require("vc.messages.config")
local router = require("vc.messages.router")

local M = {}

---@return boolean
function M.available()
	return vim.fn.has("nvim-0.12") == 1 and pcall(require, "vim._core.ui2")
end

-- Cards scheduled but not shown yet, by route id, so a later message in the same command can supersede
-- them.
---@type table<string, { cancelled?: boolean }>
local pending = {}

---@param kind string
---@param content table[]
---@return boolean handled
local function route(kind, content)
	local resolved = router.resolve(config.routes, kind, router.flatten(content), config.passthrough)
	-- stylua: ignore
	if not resolved then return false end
	for _, id in ipairs(resolved.cancels or {}) do
		if pending[id] then
			pending[id].cancelled = true
		end
	end
	if resolved.text then
		local entry = {}
		local id = resolved.id or ""
		pending[id] = entry
		-- msg_show for internal messages runs in api-fast context.
		vim.schedule(function()
			if pending[id] == entry then
				pending[id] = nil
			end
			if not entry.cancelled then
				require("vc.notify").notify(resolved.text, resolved.level or vim.log.levels.INFO)
			end
		end)
	end
	return true
end

---@param opts? VC.Messages.Config
function M.setup(opts)
	config.setup(opts)
	-- stylua: ignore
	if not M.available() then return end

	require("vim._core.ui2").enable(vim.deepcopy(config.ui2))

	-- The message window ui2 keeps for prompts: the terminal's background, not the grey float one.
	vim.api.nvim_set_hl(0, "MsgArea", { link = "Normal" })
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("VCMessages", { clear = true }),
		pattern = "msg",
		callback = function()
			vim.wo.winhighlight = vim.wo.winhighlight .. ",Normal:Normal"
		end,
	})

	local messages = require("vim._core.ui2.messages")
	local original = messages.msg_show
	messages.msg_show = function(kind, content, ...)
		local ok, handled = pcall(route, kind, content)
		if ok and handled then
			return
		end
		return original(kind, content, ...)
	end
end

return M
