local Finder = require("vc.finder")
local source = require("vc.finder.source")
local ui = require("vc.finder.ui")

local function row(id, title, project, ago, cwd_exists)
	return {
		id = id,
		path = "/nope/" .. id .. ".jsonl",
		title = title,
		project = project,
		cwd = "/x/" .. project,
		last_ts = os.time() - ago,
		msg_count = 10,
		size = 1,
		mtime = 1,
		cwd_exists = cwd_exists ~= false,
	}
end

local ROWS = {
	row("a", "Fix flaky login test", "api-server", 120),
	row("b", "Draft Q4 roadmap outline", "notes", 3600),
	row("c", "Add SSO login to admin panel", "web-app", 5 * 86400),
	row("d", "Old prototype", "proto", 90 * 86400, false),
}

local function titles(session)
	local out = {}
	for _, item in ipairs(session.query.matched) do
		out[#out + 1] = item.new and "+new" or item.row.title
	end
	return out
end

local function open(overrides)
	local ev = { confirmed = nil, exited = false }
	local session = Finder.open(vim.tbl_extend("force", {
		cwd = "/work/here",
		on_confirm = function(item)
			ev.confirmed = item
		end,
		on_exit = function()
			ev.exited = true
		end,
	}, overrides or {}))
	session:set_rows(ROWS)
	wait(function()
		return #session.query.matched > 0
	end)
	return session, ev
end

local function type_query(session, text)
	local buf = session.view.input.buf
	vim.api.nvim_buf_set_lines(buf, 0, 1, false, { " " .. text })
	vim.api.nvim_exec_autocmds("TextChangedI", { buffer = buf })
	wait(function()
		return not session.query.matching and session.query.filter.pattern == text
	end)
end

local function press(session, role, key)
	local lhs = vim.api.nvim_replace_termcodes(key, true, true, true)
	for _, mode in ipairs({ "i", "n" }) do
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(session.view[role].buf, mode)) do
			if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == lhs then
				m.callback()
				return
			end
		end
	end
	error("no mapping for " .. key)
end

describe("finder", function()
	it("opens with New session first, then sessions newest first", function()
		local s = open()
		eq({
			"+new",
			"Fix flaky login test",
			"Draft Q4 roadmap outline",
			"Add SSO login to admin panel",
			"Old prototype",
		}, titles(s))
		eq(
			"4 / 4",
			vim.api.nvim_buf_get_extmarks(
				s.view.input.buf,
				vim.api.nvim_create_namespace("vc-finder-input"),
				0,
				-1,
				{ details = true }
			)[1][4].virt_text[1][1]
		)
		s:close()
	end)

	it("drops New session as soon as a query is typed and brings it back when cleared", function()
		local s = open()
		type_query(s, "login")
		eq({ "Fix flaky login test", "Add SSO login to admin panel" }, titles(s))
		type_query(s, "")
		eq("+new", titles(s)[1])
		s:close()
	end)

	it("matches the project name too, never transcript text", function()
		local s = open()
		type_query(s, "notes")
		eq({ "Draft Q4 roadmap outline" }, titles(s))
		s:close()
	end)

	it("shows an empty message when nothing matches, and Enter does nothing", function()
		local s, ev = open()
		type_query(s, "zzz")
		eq({}, titles(s))
		local line = vim.api.nvim_buf_get_lines(s.view.list.buf, 0, 1, false)[1]
		truthy(line:find('No sessions match "zzz"', 1, true), line)
		press(s, "input", "<CR>")
		vim.wait(50)
		eq(nil, ev.confirmed)
		eq(false, s.closed)
		s:close()
	end)

	it("Enter on a session confirms it; the finder closes", function()
		local s, ev = open()
		press(s, "input", "<C-n>")
		press(s, "input", "<CR>")
		wait(function()
			return ev.confirmed ~= nil
		end)
		eq("a", ev.confirmed.row.id)
		eq(true, s.closed)
	end)

	it("Enter on the first row confirms New session", function()
		local s, ev = open()
		press(s, "input", "<CR>")
		wait(function()
			return ev.confirmed ~= nil
		end)
		eq(true, ev.confirmed.new)
	end)

	it("Esc exits and closes every window", function()
		local before = #vim.api.nvim_list_wins()
		local s, ev = open()
		eq(before + 3, #vim.api.nvim_list_wins())
		press(s, "input", "<C-c>")
		wait(function()
			return ev.exited
		end)
		eq(before, #vim.api.nvim_list_wins())
	end)

	it("the first row is selected again after each query change", function()
		local s = open()
		press(s, "input", "<C-n>")
		press(s, "input", "<C-n>")
		eq(3, s.view.list.cursor)
		type_query(s, "o")
		eq(1, s.view.list.cursor)
		s:close()
	end)

	it("renders a title row and a detail row per session, with a folder-gone marker", function()
		local s = open()
		local lines = vim.api.nvim_buf_get_lines(s.view.list.buf, 0, -1, false)
		eq("+ New session", lines[1])
		eq("Fix flaky login test", lines[2])
		truthy(lines[3]:find("api-server", 1, true))
		local gone = vim.tbl_filter(function(l)
			return l:find("(folder gone)", 1, true)
		end, lines)
		truthy(#gone == 1 or s.view.list._visible_last < 5, "folder gone marker present when the row is visible")
		s:close()
	end)

	it("the preview follows the highlighted row", function()
		local s = open()
		local function first_line()
			return vim.api.nvim_buf_get_lines(s.view.preview.buf, 0, 1, false)[1]
		end
		wait(function()
			return first_line() == "# New session"
		end)
		press(s, "input", "<C-n>")
		wait(function()
			return s.view.preview.shown == "a"
		end)
		s:close()
	end)

	it("relative time labels", function()
		local now = 1000000
		eq("just now", source.relative_time(now - 5, now))
		eq("2m ago", source.relative_time(now - 120, now))
		eq("1h ago", source.relative_time(now - 3600, now))
		eq("yesterday", source.relative_time(now - 86400, now))
		eq("5d ago", source.relative_time(now - 5 * 86400, now))
		eq("3mo ago", source.relative_time(now - 90 * 86400, now))
	end)

	it("keeps no dependency on BeastVim", function()
		local hits = vim.fn.systemlist({ "grep", "-rniE", "beast|beastvim", vim.fn.getcwd() .. "/lua" })
		eq({}, hits)
	end)
end)
