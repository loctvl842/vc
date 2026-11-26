--- Finder keys. An action table says what a key does, a binding table says which keys exist in
--- which pane (input, list, preview).
local render = require("vc.finder.render")
local ui = require("vc.finder.ui")

local M = {}

---@param session VC.Finder.Session
---@param delta integer positive = down, negative = up
local function move_cursor(session, delta)
	ui.list.move(session.view.list, delta)
	vim.cmd("redraw")
	render.schedule_preview(session)
end

---@param session VC.Finder.Session
local function focus_input(session)
	vim.api.nvim_set_current_win(session.view.input.win)
	vim.cmd("startinsert!")
end

---@type table<string, fun(session: VC.Finder.Session)>
local actions = {
	down = function(s)
		move_cursor(s, 1)
	end,
	up = function(s)
		move_cursor(s, -1)
	end,
	wheel_down = function(s)
		move_cursor(s, 3)
	end,
	wheel_up = function(s)
		move_cursor(s, -3)
	end,
	-- Enter on no rows does nothing.
	confirm = function(s)
		-- Enter acts on the list for the text in the prompt, not on one that is still being searched.
		if ui.input.get_text(s.view.input) ~= s.query.filter.pattern or s.query.matching then
			s.view.input._on_change()
			vim.wait(500, function()
				return not s.query.matching
			end, 5)
			render.render(s)
		end
		local item = ui.list.selected(s.view.list)
		if not item then
			return
		end
		s:close()
		vim.schedule(function()
			s.on_confirm(item)
		end)
	end,
	-- Esc leaves VimClaude: the finder is the home screen, so there is nothing to fall back to.
	exit = function(s)
		s:close()
		vim.schedule(s.on_exit)
	end,
	focus_input = focus_input,
	focus_preview = function(s)
		if s.view.preview:is_valid() then
			vim.api.nvim_set_current_win(s.view.preview.win)
			vim.cmd("stopinsert")
		end
	end,
	refresh = function(s)
		if s.on_refresh then
			s.on_refresh()
		end
	end,
	noop = function() end,
}

---@alias VC.Finder.KeyBinding { [1]: string, [2]: string, modes?: string[] }

---@type VC.Finder.KeyBinding[]
local move = {
	{ "<C-j>", "down" },
	{ "<C-k>", "up" },
	{ "<C-n>", "down" },
	{ "<C-p>", "up" },
	{ "<Down>", "down" },
	{ "<Up>", "up" },
	{ "<Tab>", "down" },
	{ "<S-Tab>", "up" },
	{ "<ScrollWheelDown>", "wheel_down" },
	{ "<ScrollWheelUp>", "wheel_up" },
}
---@type VC.Finder.KeyBinding[]
local pick = {
	{ "<CR>", "confirm" },
	{ "<Esc>", "exit" },
	{ "<C-c>", "exit", modes = { "i", "n" } },
	{ "<C-r>", "refresh", modes = { "i", "n" } },
}

-- The preview cannot be changed; these keys would only fail with E21 and a "Press ENTER" prompt.
---@type VC.Finder.KeyBinding[]
local readonly = {}
local edit_keys =
	"i I a A o O gi gI c C s S d D x X r R p P gp gP ]p [p J gJ u U . ~ g~ gu gU g? < > = ! & <C-a> <C-x> <Del> <Insert>"
for _, key in ipairs(vim.split(edit_keys, " ")) do
	table.insert(readonly, { key, "noop" })
end

---@type table<"input"|"list"|"preview", { modes: string[], keys: VC.Finder.KeyBinding[][], redirect?: boolean }>
local panes = {
	input = {
		modes = { "i", "n" },
		keys = { move, pick, { { "<C-h>", "noop" }, { "<C-l>", "focus_preview" } } },
	},
	list = {
		modes = { "n" },
		keys = { move, pick, { { "<C-h>", "focus_input" }, { "<C-l>", "focus_preview" } } },
		redirect = true,
	},
	-- The preview keeps Vim's own keys (scrolling, folds, search); only leaving it is bound. Esc goes
	-- back to the prompt rather than out of VimClaude: it is also what dismisses a "Press ENTER" error.
	preview = {
		modes = { "n" },
		keys = {
			{
				{ "<C-j>", "down" },
				{ "<C-k>", "up" },
				{ "<Esc>", "focus_input" },
				{ "<C-r>", "refresh" },
				{ "<C-h>", "focus_input" },
				{ "<C-l>", "noop" },
			},
			readonly,
		},
	},
}

---@param session VC.Finder.Session
function M.mount(session)
	for role, spec in pairs(panes) do
		local view = session.view[role]
		local opts = { buffer = view.buf, nowait = true }
		for _, group in ipairs(spec.keys) do
			for _, binding in ipairs(group) do
				vim.keymap.set(binding.modes or spec.modes, binding[1], function()
					actions[binding[2]](session)
				end, opts)
			end
		end
		-- A key typed in the list belongs to the prompt: go there and type it.
		if spec.redirect then
			for byte = string.byte(" "), string.byte("~") do
				local char = string.char(byte)
				vim.keymap.set("n", char, function()
					focus_input(session)
					vim.api.nvim_feedkeys(char, "n", false)
				end, opts)
			end
		end
	end
end

return M
