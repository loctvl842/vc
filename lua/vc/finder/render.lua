--- Draws the matched items into the list and keeps the preview following the highlighted row.
local config = require("vc.finder.config")
local debounce = require("vc.debounce")
local source = require("vc.finder.source")
local ui = require("vc.finder.ui")

local M = {}

---@type table<VC.Finder.Session, table>
local preview_debouncers = setmetatable({}, { __mode = "k" })

--- Show the highlighted row in the preview.
---@param session VC.Finder.Session
function M.update_preview(session)
	-- stylua: ignore
	if not session.view.list:is_valid() or not session.view.preview then return end
	local item = ui.list.selected(session.view.list)
	if not item then
		ui.preview.clear(session.view.preview)
	elseif item.new then
		ui.preview.note(session.view.preview, "New session", {
			"# New session",
			"",
			"Starts a fresh Claude Code session in",
			session.cwd,
		})
	else
		ui.preview.show(session.view.preview, item.row)
	end
end

--- Debounced preview update, so holding a movement key does not render every conversation.
---@param session VC.Finder.Session
function M.schedule_preview(session)
	local d = preview_debouncers[session]
	if not d then
		d = debounce(config.debounce.preview_ms, function()
			if not session.closed then
				M.update_preview(session)
			end
		end)
		preview_debouncers[session] = d
	end
	d()
end

---@param session VC.Finder.Session
function M.cleanup(session)
	local d = preview_debouncers[session]
	if d then
		d:close()
		preview_debouncers[session] = nil
	end
end

--- Items → list buffer → footer → preview.
---@param session VC.Finder.Session
function M.render(session)
	local pattern = session.query.filter.pattern
	local empty = pattern ~= "" and ('No sessions match "%s"'):format(pattern) or "No sessions"
	if session._keep_id then
		for i, item in ipairs(session.query.matched) do
			if item.row and item.row.id == session._keep_id then
				session.view.list.cursor = i
				break
			end
		end
		session._keep_id = nil
	end
	ui.list.render(session.view.list, session.query.matched, source.format, empty)
	ui.list.set_footer(session.view.list, #session.query.matched > 0 and source.footer or source.footer_empty)
	M.schedule_preview(session)
	vim.cmd("redraw")
end

return M
