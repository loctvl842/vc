local render = require("vc.finder.render")
local ui = require("vc.finder.ui")

local M = {}

local saved_guicursor ---@type string?

local function hide_cursor()
	if not saved_guicursor then
		saved_guicursor = vim.o.guicursor
		vim.o.guicursor = "a:block-VCFinderListCursor"
	end
end

function M.restore_cursor()
	if saved_guicursor then
		vim.o.guicursor = saved_guicursor
		saved_guicursor = nil
	end
end

---@param session VC.Finder.Session
function M.mount(session)
	local group = vim.api.nvim_create_augroup("VCFinder", { clear = true })
	session.augroup = group
	local list_buf = session.view.list.buf

	vim.api.nvim_create_autocmd("BufEnter", { group = group, buffer = list_buf, callback = hide_cursor })
	vim.api.nvim_create_autocmd("BufLeave", { group = group, buffer = list_buf, callback = M.restore_cursor })
	vim.api.nvim_create_autocmd("BufWipeout", { group = group, buffer = list_buf, callback = M.restore_cursor })

	-- A click in the list moves the selection.
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = list_buf,
		callback = function()
			-- stylua: ignore
			if not session.view.list:is_valid() then return end
			local row = vim.api.nvim_win_get_cursor(session.view.list.win)[1]
			local idx = ui.list.item_at_row(session.view.list, row)
			if idx and idx ~= session.view.list.cursor then
				ui.list.set_cursor(session.view.list, idx)
				vim.cmd("redraw")
				render.schedule_preview(session)
			end
		end,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			session:relayout()
		end,
	})

	-- Closing any pane (e.g. `:q` in the preview) leaves the finder, like Esc does.
	for _, v in pairs(session.view) do
		vim.api.nvim_create_autocmd("WinClosed", {
			group = group,
			pattern = tostring(v.win),
			once = true,
			callback = function()
				vim.schedule(function()
					if not session.closed then
						session:close()
						vim.schedule(session.on_exit)
					end
				end)
			end,
		})
	end

	-- The finder is the home screen: focus that wanders outside it comes back to the prompt.
	vim.api.nvim_create_autocmd("WinEnter", {
		group = group,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			for _, v in pairs(session.view) do
				if v.win == current then
					return
				end
			end
			vim.schedule(function()
				if not session.closed and session.view.input:is_valid() then
					vim.api.nvim_set_current_win(session.view.input.win)
					vim.cmd("startinsert!")
				end
			end)
		end,
	})
end

return M
