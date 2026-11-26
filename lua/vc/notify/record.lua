local config = require("vc.notify.config")
local wrap = require("vc.finder.wrap")

---@class VC.Notify.Record
---@field id integer
---@field message string[]
---@field level string        "INFO"|"WARN"|"ERROR"|"DEBUG"|"TRACE"
---@field title string
---@field icon string
---@field time integer        vim.fn.localtime()
---@field timeout number|false
local M = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

M.__index = M

---@class VC.Notify.Options
---@field title? string
---@field icon? string
---@field timeout? number|false

---@param id integer
---@param message string|string[]
---@param level? string|integer
---@param opts? VC.Notify.Options
---@return VC.Notify.Record
function M:new(id, message, level, opts)
	opts = opts or {}
	level = config.normalize_level(level or "INFO")

	return setmetatable({
		id = id,
		message = config.normalize_message(message),
		level = level,
		title = opts.title or "",
		icon = opts.icon or config.icons[level] or "",
		time = vim.fn.localtime(),
		timeout = opts.timeout ~= nil and opts.timeout or config.timeout,
	}, self)
end

---Message lines wrapped to the card width and cut after `max_height` rows.
---@param width integer
---@return string[]
function M:lines(width)
	if self._width ~= width then
		local rows = {}
		for _, line in ipairs(self.message) do
			local spans = wrap.lines(line, width)
			if #spans == 0 then
				rows[#rows + 1] = ""
			end
			for _, span in ipairs(spans) do
				rows[#rows + 1] = line:sub(span.s, span.e)
			end
		end
		self._rows = vim.list_slice(rows, 1, config.max_height)
		self._width = width
	end
	return self._rows
end

---@return integer width, integer height
function M:dimensions()
	local width = config.width()
	return width, #self:lines(width) + 1
end

return M
