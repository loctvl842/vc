---@class VC.Toast.State
---@field views VC.Toast.View[]   index 1 = topmost (oldest), #views = bottommost (newest)
---@field queue VC.Toast.Record[]
---@field next_id integer
---@field draining boolean
---@field inflight? VC.Toast.Record  taken off the queue, not yet shown
local State = setmetatable({}, {
	__call = function(t, ...)
		return t:new(...)
	end,
})

State.__index = State

---@return VC.Toast.State
function State:new()
	return setmetatable({
		views = {},
		queue = {},
		next_id = 1,
		draining = false,
	}, self)
end

---@param id integer
---@return integer|nil idx
---@return VC.Toast.View|nil view
function State:find(id)
	for i, v in ipairs(self.views) do
		if v.record.id == id then
			return i, v
		end
	end
end

return State
