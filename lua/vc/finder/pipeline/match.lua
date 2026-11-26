--- Match pipeline: the items are loaded once, then re-scored locally on each keystroke.
--- UI-free: everything it needs from its owner goes through a `VC.Finder.Host`.
local config = require("vc.finder.config")
local matcher = require("vc.finder.matcher")

local M = {}

---@class VC.Finder.Pipeline.State
---@field match_state? table
---@field matcher_task? { abort: fun() }
---@field aborted boolean
---@field generation integer bumped by every run, reload and abort; an older answer is dropped
---@type table<VC.Finder.Query, VC.Finder.Pipeline.State>
local registry = setmetatable({}, { __mode = "k" })

local function get(query)
	if not registry[query] then
		registry[query] = { aborted = false, generation = 0 }
	end
	return registry[query]
end

--- Re-score all items against the current pattern.
---@param query VC.Finder.Query
---@param host VC.Finder.Host
function M.run(query, host)
	local s = get(query)
	if s.matcher_task then
		s.matcher_task:abort()
	end
	s.generation = s.generation + 1
	local generation = s.generation
	query.matching = true
	s.matcher_task = matcher.run(query.items, query.filter, config.matcher, function(matched, match_state)
		-- stylua: ignore
		if s.aborted or not host.alive() or generation ~= s.generation then return end
		query.matched = matched
		if match_state then
			s.match_state = match_state
			query.total = match_state.total
			query.matching = false
			host.count(M.count_label(query))
		end
		host.render()
	end, s.match_state, query.limit)
end

---@param query VC.Finder.Query
---@return string
function M.count_label(query)
	local shown = 0
	for _, item in ipairs(query.matched) do
		if not item.new then
			shown = shown + 1
		end
	end
	local total = 0
	for _, item in ipairs(query.items) do
		if not item.new then
			total = total + 1
		end
	end
	return ("%d / %d"):format(shown, total)
end

--- Replace the items and score them again (the index delivered a new list).
---@param query VC.Finder.Query
---@param host VC.Finder.Host
---@param items VC.Finder.Item[]
function M.load(query, host, items)
	local s = get(query)
	s.match_state = nil
	query.items = items
	M.run(query, host)
end

--- Abort whatever is running; late answers are dropped.
---@param query VC.Finder.Query
function M.abort(query)
	local s = registry[query]
	-- stylua: ignore
	if not s then return end
	s.aborted = true
	s.generation = s.generation + 1
	if s.matcher_task then
		s.matcher_task:abort()
		s.matcher_task = nil
	end
	registry[query] = nil
end

return M
