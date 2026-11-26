--- The finder: one picker over Claude Code sessions, filling the whole screen.
local Host = require("vc.finder.host")
local layout = require("vc.finder.layout")
local pipeline = require("vc.finder.pipeline")
local query_mod = require("vc.finder.query")
local source = require("vc.finder.source")
local ui = require("vc.finder.ui")

---@class VC.Finder.Session
---@field closed boolean
---@field query VC.Finder.Query
---@field view { input: VC.Finder.InputView, list: VC.Finder.ListView, preview: VC.Finder.PreviewView }
---@field rows VC.Row[]
---@field cwd string where "New session" starts
---@field host VC.Finder.Host
---@field on_confirm fun(item: VC.Finder.Item)
---@field on_exit fun()
---@field augroup? integer
local Session = {}
Session.__index = Session

local M = {}

---@type VC.Finder.Session?
local instance

---@class VC.Finder.OpenOpts
---@field cwd? string
---@field on_confirm fun(item: VC.Finder.Item) Enter on a row
---@field on_exit fun() the user left the finder (Esc)

---@param opts VC.Finder.OpenOpts
---@return VC.Finder.Session
function M.open(opts)
	M.close()
	require("vc.finder.highlights").setup()
	local geo = layout.calc()
	local session = setmetatable({
		closed = false,
		query = query_mod.new(),
		rows = {},
		cwd = opts.cwd or vim.fn.getcwd(),
		on_confirm = opts.on_confirm,
		on_exit = opts.on_exit,
	}, Session)
	instance = session

	session.host = Host.headless({
		alive = function()
			return not session.closed and session.view.list:is_valid()
		end,
		render = function()
			require("vc.finder.render").render(session)
		end,
		count = function(text)
			ui.input.set_count(session.view.input, text)
		end,
	})
	session.view = {
		input = ui.input.create(function(text)
			session.query.filter:update(text)
			-- A new query starts on the first row.
			session.view.list.cursor, session.view.list._offset = 1, 0
			-- "New session" belongs to the empty query only: rebuild the items when it toggles.
			session:_sync_items()
			pipeline.run(session.query, session.host)
		end, geo.input, source.title),
		list = ui.list.create(geo.list, source.footer),
		preview = ui.preview.create(geo.preview),
	}
	require("vc.finder.keymaps").mount(session)
	require("vc.finder.autocmds").mount(session)
	session:_sync_items()
	pipeline.run(session.query, session.host)
	return session
end

--- The items follow the rows and the query: "New session" only while the query is empty.
function Session:_sync_items()
	local with_new = self.query.filter.pattern == ""
	local first = self.query.items[1]
	local has_new = first ~= nil and first.new == true
	if has_new ~= with_new or #self.query.items ~= #self.rows + (with_new and 1 or 0) then
		self.query.items = source.items(self.rows, with_new)
	end
end

--- New session rows arrived (the cached list first, the full scan after).
---@param rows VC.Row[]
function Session:set_rows(rows)
	-- stylua: ignore
	if self.closed then return end
	self.rows = rows
	self.query.items = source.items(rows, self.query.filter.pattern == "")
	pipeline.load(self.query, self.host, self.query.items)
end

---@param on boolean
function Session:busy(on)
	-- stylua: ignore
	if self.closed then return end
	if on then
		ui.input.start_spinner(self.view.input)
	else
		ui.input.stop_spinner(self.view.input)
	end
end

function Session:close()
	-- stylua: ignore
	if self.closed then return end
	self.closed = true
	pipeline.abort(self.query)
	require("vc.finder.render").cleanup(self)
	ui.input.stop_spinner(self.view.input)
	if self.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, self.augroup)
	end
	self.view.input:close()
	self.view.list:close()
	self.view.preview:close()
	if instance == self then
		instance = nil
	end
end

--- Re-place the panes after the screen changed size.
function Session:relayout()
	-- stylua: ignore
	if self.closed then return end
	local geo = layout.calc()
	for role, g in pairs({ input = geo.input, list = geo.list, preview = geo.preview }) do
		local v = self.view[role]
		if v:is_valid() then
			pcall(
				vim.api.nvim_win_set_config,
				v.win,
				{ relative = "editor", width = g.w, height = g.h, row = g.row, col = g.col }
			)
		end
	end
	require("vc.finder.render").render(self)
end

--- Close the open finder, if any.
function M.close()
	if instance then
		instance:close()
	end
end

---@return VC.Finder.Session?
function M.current()
	return instance
end

return M
