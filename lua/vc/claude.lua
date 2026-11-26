--- Runs Claude Code in a Neovim terminal buffer that fills the only window.
local M = {}

--- The shell command that starts Claude Code for a finder item.
--- cwd, id and notice travel as positional arguments (never interpolated), so odd paths are safe.
---@param item VC.Finder.Item
---@param here string Neovim's working directory
---@return string[] cmd
---@return string? notice shown to the user when the original folder is gone
function M.command(item, here)
	local sh = vim.o.shell
	if item.new then
		return { sh, "-c", 'cd "$1" && exec claude', "vc", here }
	end
	local row = item.row
	if row.cwd and vim.uv.fs_stat(row.cwd) then
		return { sh, "-c", 'cd "$1" && exec claude --resume "$2"', "vc", row.cwd, row.id }
	end
	local notice = ("Original folder %s is gone, continuing from %s"):format(row.cwd or "(unknown)", here)
	return { sh, "-c", 'printf "%s\\n" "$1"; exec claude --resume "$2"', "vc", notice, row.id }, notice
end

--- Start Claude Code in the current (only) window.
---@param item VC.Finder.Item
---@param on_exit fun(code: integer) called on the main loop when the process ends
---@return boolean started
function M.run(item, on_exit)
	if vim.fn.executable("claude") == 0 then
		vim.schedule(function()
			on_exit(127)
		end)
		return false
	end
	local cmd = M.command(item, vim.fn.getcwd())
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, buf)
	local win = vim.api.nvim_get_current_win()
	for _, opt in ipairs({ "number", "relativenumber", "list", "cursorline", "spell" }) do
		vim.api.nvim_set_option_value(opt, false, { scope = "local", win = win })
	end
	vim.api.nvim_set_option_value("signcolumn", "no", { scope = "local", win = win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { scope = "local", win = win })
	vim.api.nvim_buf_call(buf, function()
		vim.fn.jobstart(cmd, {
			term = true,
			on_exit = function(_, code)
				vim.schedule(function()
					on_exit(code)
				end)
			end,
		})
	end)
	vim.cmd("startinsert")
	return true
end

return M
