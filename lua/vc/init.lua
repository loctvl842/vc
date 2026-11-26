--- VimClaude has two screens: the session finder and Claude Code. This module moves between them:
--- the finder is shown at start, Enter hands the window to Claude Code, and when Claude Code ends
--- the finder is shown again. Esc in the finder leaves Neovim.
local claude = require("vc.claude")
local finder = require("vc.finder")
local index = require("vc.sessions.index")
local theme = require("vc.theme")

local M = {}

---@type { index?: { root?: string, cache_path?: string } }
local opts = {}
local cancel_index ---@type fun()?

--- A plain empty buffer in the only window, with nothing else on screen.
local function reset_window()
	vim.cmd("silent! only")
	local buf = vim.api.nvim_create_buf(false, true)
	local old = vim.api.nvim_win_get_buf(0)
	vim.api.nvim_win_set_buf(0, buf)
	if old ~= buf and vim.api.nvim_buf_is_valid(old) then
		pcall(vim.api.nvim_buf_delete, old, { force = true })
	end
end

--- Show the finder: cached sessions at once, the rest as soon as they are scanned.
function M.show_finder()
	if cancel_index then
		cancel_index()
		cancel_index = nil
	end
	reset_window()
	local session
	--- Scan the sessions again; what is known shows at once and the rest follows. A scan in flight is replaced.
	local function load()
		if cancel_index then
			cancel_index()
		end
		session:busy(true)
		cancel_index = index.load(opts.index, function(rows, done)
			session:set_rows(rows)
			if done then
				session:busy(false)
			end
		end)
	end
	session = finder.open({
		on_confirm = M.open_item,
		on_refresh = load,
		on_exit = function()
			if cancel_index then
				cancel_index()
			end
			vim.cmd("qa!")
		end,
	})
	load()
end

--- Enter on a finder item: hand the window to Claude Code.
---@param item VC.Finder.Item
function M.open_item(item)
	if cancel_index then
		cancel_index()
		cancel_index = nil
	end
	reset_window()
	claude.run(item, function(code)
		M.show_finder()
		if code ~= 0 then
			vim.notify(
				code == 127 and "claude was not found on PATH" or ("claude exited with code " .. code),
				vim.log.levels.WARN
			)
		end
	end)
end

--- Only the finder and Claude Code are ever on screen: no statusline, tabline, intro or cmdline row.
local function set_ui_options()
	vim.o.laststatus = 0
	vim.o.showtabline = 0
	vim.o.cmdheight = 0
	vim.o.ruler = false
	vim.o.showmode = false
	vim.o.shortmess = vim.o.shortmess .. "I"
	vim.o.swapfile = false
	-- Palette colors until the terminal's real colors are known (`vc.theme`), so its theme paints everything.
	vim.o.termguicolors = false
end

---@param o? { index?: { root?: string, cache_path?: string } }
function M.start(o)
	opts = o or {}
	set_ui_options()
	-- Learn the terminal's colors before the first paint; a terminal that does not answer costs one timeout.
	theme.refresh()
	vim.wait(250, function()
		return not theme.pending
	end, 5)
	-- Messages show as cards from here on; the palette is known by now, so the cards use the terminal's colors.
	require("vc.notify").setup()
	require("vc.messages").setup()
	M.show_finder()
end

return M
