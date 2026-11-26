-- Pure message routing: decides whether a message becomes a notification card,
-- is dropped, or is left to ui2. No Neovim state, so it is unit-testable.

local M = {}

---@class VC.Messages.Resolved
---@field drop? boolean
---@field text? string
---@field level? integer
---@field id? string
---@field cancels? string[]

---Flatten ui-messages `content` chunks (`{ attr_id, text, hl_id }`) into text.
---@param content table[]
---@return string
function M.flatten(content)
	local parts = {}
	for _, chunk in ipairs(content) do
		parts[#parts + 1] = chunk[2]
	end
	return (table.concat(parts):gsub("^%s+", ""):gsub("%s+$", ""))
end

---Decide what a message becomes. Prompts the user must answer stay with ui2 (nil), empty messages are
---dropped, the first matching route wins, and anything else is an INFO card.
---@param routes VC.Messages.Route[]
---@param kind string
---@param text string
---@param passthrough? string[] kinds ui2 keeps
---@return VC.Messages.Resolved?
function M.resolve(routes, kind, text, passthrough)
	if vim.tbl_contains(passthrough or {}, kind) then
		return nil
	end
	if text == "" then
		return { drop = true }
	end
	for _, route in ipairs(routes) do
		if vim.tbl_contains(route.kind, kind) then
			local caps = route.match and { text:match(route.match) } or {}
			if not route.match or #caps > 0 then
				if route.drop then
					return { drop = true }
				end
				local out = route.format and route.format(unpack(caps)) or text
				return { text = out, level = route.level, id = route.id, cancels = route.cancels }
			end
		end
	end
	return { text = text, level = vim.log.levels.INFO }
end

return M
