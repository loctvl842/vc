---@class VC.Messages.Route
---@field kind string[]                 Message kinds this route applies to (see :help ui-messages)
---@field match? string                 Lua pattern tested against the message text; captures go to `format`
---@field level? integer                vim.log.levels value for the card
---@field id? string                    Name other routes use in `cancels`
---@field format? fun(...: string): string  Builds the card text from the pattern captures (default: the message text)
---@field cancels? string[]             Ids of not-yet-shown cards this message supersedes (a failed search also emits "search hit BOTTOM")
---@field drop? boolean                 Swallow the message without any output

---@class VC.Messages.Config
local defaults = {
	-- Options passed to vim._core.ui2.enable().
	ui2 = {
		msg = {
			-- Ephemeral message window (made for cmdheight = 0) instead of the cmdline.
			target = "msg",
			targets = { list_cmd = "pager" },
			msg = { timeout = 4000 },
		},
	},

	-- Message kinds the user has to answer; ui2 shows these as it always does.
	passthrough = { "confirm", "confirm_sub", "return_prompt", "number_prompt" },

	-- Ordered; the first matching route wins. Anything not matched becomes an INFO card.
	---@type VC.Messages.Route[]
	routes = {
		{
			kind = { "emsg" },
			match = "^E486: Pattern not found: (.*)",
			level = vim.log.levels.WARN,
			cancels = { "search-wrapped" },
			format = function(pat)
				return "Pattern not found: " .. pat
			end,
		},
		{
			kind = { "wmsg" },
			match = "^search hit (%u+)",
			level = vim.log.levels.WARN,
			id = "search-wrapped",
			format = function(edge)
				return edge == "BOTTOM" and "Hit BOTTOM, continuing at TOP" or "Hit TOP, continuing at BOTTOM"
			end,
		},
		-- The finder shows its own counts.
		{ kind = { "search_count" }, drop = true },
		{ kind = { "emsg", "echoerr", "lua_error", "rpc_error" }, level = vim.log.levels.ERROR },
		{ kind = { "wmsg" }, level = vim.log.levels.WARN },
	},
}

---@type VC.Messages.Config
local cfg = vim.deepcopy(defaults)

local methods = {}

---@param opts? VC.Messages.Config
function methods.setup(opts)
	cfg = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

local M = setmetatable({}, {
	__index = function(_, key)
		if methods[key] ~= nil then
			return methods[key]
		end
		return cfg[key]
	end,

	__newindex = function(_, key, _)
		error(
			string.format(
				"vc.messages.config is read-only; cannot assign '%s' directly. Use setup() instead.",
				tostring(key)
			),
			2
		)
	end,
})

return M
