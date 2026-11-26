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
ROWS[1].branch, ROWS[1].pr = "main", 8
ROWS[1].last_prompt = "ok replace the wait with polling, and then push the branch"
ROWS[2].recap = "Roadmap outline is drafted; next step is sending it to Dana."
ROWS[2].last_prompt = "turn the outline into three bullets per quarter, keep it under a page, and then send it to Dana"
	.. " so she can review it before Friday's planning sync, then book the room for Thursday afternoon"

--- The text of each row of an item.
local function texts(lines)
	local out = {}
	for _, chunks in ipairs(lines) do
		local parts = {}
		for _, c in ipairs(chunks) do
			parts[#parts + 1] = c.text
		end
		out[#out + 1] = table.concat(parts)
	end
	return out
end

local function filter_of(text)
	local filter = require("vc.finder.filter").new()
	filter:update(text)
	return filter
end

local function item_of(r)
	return source.items({ r }, false)[1]
end

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
		return not session.query.matching and session.query.filter.text == text
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
			"4 / 4 ",
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

	it("Esc in the preview goes back to the prompt instead of exiting", function()
		local s, ev = open()
		vim.api.nvim_set_current_win(s.view.preview.win)
		press(s, "preview", "<Esc>")
		eq(s.view.input.win, vim.api.nvim_get_current_win())
		eq(false, ev.exited)
		s:close()
	end)

	it("editing keys in the read-only preview are swallowed, so E21 never shows", function()
		local s = open()
		vim.api.nvim_set_current_win(s.view.preview.win)
		for _, key in ipairs({ "d", "c", "x", "i", "a", "o", "p", "J", "u", "." }) do
			local map = vim.fn.maparg(key, "n", false, true)
			eq(s.view.preview.buf, map.buffer and vim.api.nvim_get_current_buf(), key)
		end
		s:close()
	end)

	it("Ctrl-R asks for a refresh from every pane", function()
		local refreshed = 0
		local s = open({
			on_refresh = function()
				refreshed = refreshed + 1
			end,
		})
		for _, role in ipairs({ "input", "list", "preview" }) do
			press(s, role, "<C-r>")
		end
		eq(3, refreshed)
		s:close()
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

	it("renders each session as a title row, a folder row, its messages and a blank row", function()
		local s = open()
		local lines = vim.api.nvim_buf_get_lines(s.view.list.buf, 0, -1, false)
		eq("+ New session", lines[1])
		eq("", lines[2])
		eq("Fix flaky login test", lines[3])
		-- the list is narrow here: the folder keeps its end and the PR, the branch gives way
		truthy(lines[4]:find("server · #8", 1, true), lines[4])
		truthy(lines[5]:find("You   › ok replace", 1, true), lines[5])
		local next_title = vim.fn.index(lines, "Draft Q4 roadmap outline") + 1
		truthy(next_title > 5, "the next session follows")
		eq("", lines[next_title - 1])
		s:close()
	end)

	it("marks a session whose folder is gone", function()
		local lines = texts((source.format(item_of(ROWS[4]), 60)))
		truthy(lines[2]:find("/x/proto (folder gone)", 1, true), lines[2])
	end)

	it("a session with neither recap nor last message is a title, a folder row and a blank row", function()
		local r = row("n", "Nothing else", "scratch", 7200)
		eq(3, #(source.format(item_of(r), 60)))
	end)

	it("folds long messages to 3 lines unless the session is selected", function()
		local item = item_of(ROWS[2])
		local folded = texts((source.format(item, 50, { selected = false })))
		-- title, folder row, 2 recap lines, 3 message lines, blank row
		eq(8, #folded)
		truthy(vim.endswith(folded[7], "…"), folded[7])
		local open_ = texts((source.format(item, 50, { selected = true })))
		truthy(#open_ > #folded)
		truthy(not vim.endswith(open_[#open_ - 1], "…"))
		truthy(table.concat(open_, " "):find("Thursday afternoon", 1, true))
	end)

	it("cuts an item taller than the window with an ellipsis", function()
		local lines = texts((source.format(item_of(ROWS[2]), 50, { selected = true, max_rows = 5 })))
		eq(5, #lines)
		truthy(vim.endswith(lines[5], "…"), lines[5])
	end)

	it("opens the selected session and folds the one the cursor left", function()
		local s = open()
		local function joined()
			return table.concat(vim.api.nvim_buf_get_lines(s.view.list.buf, 0, -1, false), "\n")
		end
		press(s, "input", "<C-n>")
		press(s, "input", "<C-n>")
		eq(3, s.view.list.cursor)
		truthy(joined():find("Thursday afternoon", 1, true), "the selected message is open")
		press(s, "input", "<C-p>")
		truthy(not joined():find("Thursday afternoon", 1, true), "it folds when the cursor leaves")
		s:close()
	end)

	it("wraps messages to the list width with a hanging indent", function()
		local lines = texts((source.format(item_of(ROWS[1]), 34, { selected = true })))
		eq("  You   › ok replace the wait", lines[3])
		eq("          with polling, and then", lines[4])
	end)

	it("keeps the chips and the end of the folder in a narrow list", function()
		local r = vim.deepcopy(ROWS[1])
		r.cwd = "/Users/someone/work/clients/acme/services/api-server"
		local folder = texts((source.format(item_of(r), 60)))[2]
		truthy(folder:find("^  …"), folder)
		truthy(folder:find("api%-server · main · #8"), folder)
	end)

	it("shortens a long branch before the folder row overflows a narrow list", function()
		local r = vim.deepcopy(ROWS[1])
		r.branch, r.pr = "feat/preview-style-with-a-very-long-name", nil
		for _, width in ipairs({ 38, 50, 80 }) do
			local folder = texts((source.format(item_of(r), width)))[2]
			truthy(vim.fn.strdisplaywidth(folder) <= width - 2, ("%d columns: %q"):format(width, folder))
		end
		truthy(texts((source.format(item_of(r), 38)))[2]:find("· feat/…", 1, true))
		eq(true, texts((source.format(item_of(r), 80)))[2]:find(r.branch, 1, true) ~= nil)
	end)

	it("shows the full location with the home folder as ~", function()
		local r = row("h", "Home", "x", 60)
		r.cwd = vim.env.HOME .. "/work/api-server"
		eq("~/work/api-server", source.location(r))
		eq("/x/api-server", source.location(ROWS[1]))
	end)

	it("searches the recap, and highlights the match on the recap row", function()
		local s = open()
		type_query(s, "'dana")
		eq({ "Draft Q4 roadmap outline" }, titles(s))
		local lines, ranges = source.format(s.query.matched[1], 80)
		-- "Dana" is in the recap and in the last message: each field is matched on its own
		eq(2, #ranges)
		eq(3, ranges[1].row)
		eq("Dana", texts(lines)[3]:sub(ranges[1].s + 1, ranges[1].e))
		eq("Dana", texts(lines)[ranges[2].row]:sub(ranges[2].s + 1, ranges[2].e))
		type_query(s, "rmpldanta") -- scattered letters do not match recap prose
		eq({}, titles(s))
		s:close()
	end)

	it("searches the last message and highlights the match, past the fold", function()
		local s = open()
		type_query(s, "'thursday")
		eq({ "Draft Q4 roadmap outline" }, titles(s))
		local item = s.query.matched[1]
		-- "Thursday" is far beyond the third line of the message, yet an unselected session shows it
		local lines, ranges = source.format(item, 50, { selected = false })
		local rows = texts(lines)
		eq(1, #ranges)
		eq("Thursday", rows[ranges[1].row]:sub(ranges[1].s + 1, ranges[1].e))
		truthy(#rows > 8, "the message runs on to the match")
		-- and without a match the same session folds to 3 lines
		eq(8, #texts((source.format(item_of(ROWS[2]), 50, { selected = false }))))
		s:close()
	end)

	it("draws a match over the selected row's background and the text's own colour", function()
		local s = open()
		type_query(s, "'thursday")
		local list = s.view.list
		local marks = vim.api.nvim_buf_get_extmarks(list.buf, list.ns, 0, -1, { details = true })
		local match, row_bg, text
		for _, m in ipairs(marks) do
			local d = m[4]
			if d.hl_group == "VCFinderListMatch" then
				match = d
			elseif d.line_hl_group == "VCFinderListCursorLine" then
				row_bg = d
			elseif d.hl_group == "VCFinderListPrompt" then
				text = d
			end
		end
		truthy(match and row_bg and text, "the selected item has a match, a row background and message text")
		truthy(match.priority > row_bg.priority, "the match is above the selected row")
		truthy(match.priority > text.priority, "the match is above the text colour")
		s:close()
	end)

	it("matches a word of the recap or of the last message from any session", function()
		local s = open()
		type_query(s, "'polling")
		eq({ "Fix flaky login test" }, titles(s))
		type_query(s, "'DANA") -- a capital makes it case sensitive
		eq({}, titles(s))
		type_query(s, "'dana")
		eq({ "Draft Q4 roadmap outline" }, titles(s))
		s:close()
	end)

	it("does not match scattered letters inside the last message", function()
		local s = open()
		type_query(s, "pllng") -- p, l, l, n, g appear in order in "replace the wait with polling"
		eq({}, titles(s))
		s:close()
	end)

	it("highlights each typed word where it appears in the message", function()
		local s = open()
		type_query(s, "wait 'polling")
		eq({ "Fix flaky login test" }, titles(s))
		local lines, ranges = source.format(s.query.matched[1], 60, { selected = true })
		local rows = texts(lines)
		local found = {}
		for _, r in ipairs(ranges) do
			found[#found + 1] = rows[r.row]:sub(r.s + 1, r.e)
		end
		eq({ "wait", "polling" }, found)
		s:close()
	end)

	it("matches the query inside one field, never across the title, location and messages", function()
		local s = open()
		type_query(s, "flaky 'polling") -- the title has one word and the last message the other
		eq({}, titles(s))
		type_query(s, "flaky login") -- both words are in the title
		eq({ "Fix flaky login test" }, titles(s))
		type_query(s, "testapi") -- the end of the title and the start of the location, joined by nothing
		eq({}, titles(s))
		s:close()
	end)

	it("lists a session once for a query that matches several of its fields", function()
		local s = open()
		type_query(s, "'login")
		eq({ "Fix flaky login test", "Add SSO login to admin panel" }, titles(s))
		type_query(s, "'api") -- the location of one session, nothing else
		eq({ "Fix flaky login test" }, titles(s))
		s:close()
	end)

	it("ranks a session higher when more of its fields match", function()
		local r1 = row("p", "Dana sync", "other", 60)
		local r2 = row("q", "Dana sync", "other", 30)
		r1.recap = "talked to Dana"
		local scores = {}
		for i, r in ipairs({ r1, r2 }) do
			local m = require("vc.finder.matcher")
			local done
			m.run(
				source.items({ r }, false),
				filter_of("dana"),
				{ ignorecase = true, smartcase = true },
				function(matched, st)
					if st then
						scores[i] = matched[1].score
						done = true
					end
				end
			)
			wait(function()
				return done
			end)
		end
		truthy(scores[1] > scores[2], "recap match adds to the title match")
	end)

	it("keeps the end of a long location and maps match highlights onto it", function()
		local r = row("z", "Deploy", "very-long-project-name", 60)
		r.cwd = "/Users/someone/work/clients/acme/services/very-long-project-name"
		local item = source.items({ r }, false)[1]
		item.positions = { #"Deploy" + 2 + #r.cwd } -- the last byte of the location
		local lines, ranges = source.format(item, 50)
		local shown = lines[2][1].text
		truthy(vim.startswith(shown, "  …"), shown)
		eq("e", shown:sub(ranges[1].s + 1, ranges[1].e))
		eq(true, vim.endswith(shown, "very-long-project-name"))
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
			return vim.startswith(s.view.preview.shown or "", "a:")
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

	it("restores the cursor when closed from the list pane", function()
		local before = vim.o.guicursor
		local s = open()
		vim.api.nvim_set_current_win(s.view.list.win)
		s:close()
		eq(before, vim.o.guicursor)
	end)

	it("closes every pane and exits when one is closed with :q", function()
		local s, ev = open()
		local wins = { s.view.input.win, s.view.list.win, s.view.preview.win }
		vim.api.nvim_set_current_win(s.view.preview.win)
		vim.cmd("q")
		wait(function()
			return s.closed
		end)
		for _, w in ipairs(wins) do
			eq(false, vim.api.nvim_win_is_valid(w))
		end
		wait(function()
			return ev.exited
		end)
	end)

	it("Enter acts on the typed query even before the debounce fires", function()
		local s, ev = open()
		local buf = s.view.input.buf
		vim.api.nvim_buf_set_lines(buf, 0, 1, false, { " roadmap" })
		press(s, "input", "<CR>") -- no wait: the 30 ms debounce has not run
		wait(function()
			return ev.confirmed ~= nil
		end)
		eq("b", ev.confirmed.row.id)
	end)

	it("keeps the highlighted session when new rows arrive", function()
		local s = open()
		press(s, "input", "<C-n>")
		press(s, "input", "<C-n>") -- "Draft Q4 roadmap outline"
		local newer = vim.list_extend({ row("z", "Brand new", "p", 1) }, ROWS)
		s:set_rows(newer)
		wait(function()
			return #s.query.matched == 6
		end)
		eq("b", ui.list.selected(s.view.list).row.id)
		s:close()
	end)

	it("reads a resumed session again (preview cache keyed on size and mtime)", function()
		local s = open()
		local r = ROWS[1]
		local key1 = r.id .. ":" .. r.size .. ":" .. r.mtime
		ui.preview.show(s.view.preview, r)
		eq(key1, s.view.preview.shown)
		local grown = vim.tbl_extend("force", r, { size = r.size + 10 })
		ui.preview.show(s.view.preview, grown)
		eq(r.id .. ":" .. grown.size .. ":" .. r.mtime, s.view.preview.shown)
		s:close()
	end)

	it("shows tool calls as one line and keeps long results folded until opened", function()
		local F = require("test.sessions.fixtures")
		local d = tmpdir()
		local out = {}
		for i = 1, 8 do
			out[i] = "row " .. i
		end
		write_file(d .. "/s.jsonl", {
			F.user("go", "t"),
			F.assistant({ { type = "tool_use", id = "1", name = "Bash", input = { command = "ls" } } }, "t"),
			F.tool_result("t", nil, { id = "1", text = table.concat(out, "\n") }),
			F.assistant({ { type = "text", text = "done" } }, "t"),
		})
		local s = open()
		local r = vim.tbl_extend("force", ROWS[1], { id = "tool", path = d .. "/s.jsonl", title = "T", cwd = "/x" })
		ui.preview.show(s.view.preview, r)
		local buf, win = s.view.preview.buf, s.view.preview.win
		wait(function()
			return vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "● Bash(ls)")
		end)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local at = vim.fn.index(lines, "     row 4") + 1
		vim.api.nvim_win_call(win, function()
			local call = vim.fn.index(lines, "● Bash(ls)") + 1
			eq(call, vim.fn.foldclosed(call)) -- the run of calls is one line
			eq("  Ran 1 shell command", vim.fn.foldtextresult(call))
			-- the cursor on a fold brightens its label; elsewhere it keeps the dim fold group
			vim.v.foldstart, vim.v.foldend = call, call + 1
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			eq("string", type(ui.preview.foldtext()))
			vim.api.nvim_win_set_cursor(0, { call, 0 })
			eq("VCFinderPreviewFoldHover", ui.preview.foldtext()[1][2])
			vim.cmd(call .. "foldopen")
			eq(-1, vim.fn.foldclosed(call))
			eq(at, vim.fn.foldclosed(at)) -- the long result inside it is still folded
			eq("     … +5 lines", vim.fn.foldtextresult(at))
			vim.cmd("normal! zR")
			eq(-1, vim.fn.foldclosed(at))
		end)
		s:close()
	end)

	it("paints the document's marks as extmarks", function()
		local F = require("test.sessions.fixtures")
		local d = tmpdir()
		write_file(d .. "/s.jsonl", { F.user("hello", "t") })
		local s = open()
		local r = vim.tbl_extend("force", ROWS[1], { id = "marks", path = d .. "/s.jsonl", title = "T", cwd = "/x" })
		ui.preview.show(s.view.preview, r)
		local buf = s.view.preview.buf
		wait(function()
			return vim.tbl_contains(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "❯ hello")
		end)
		local marks = vim.api.nvim_buf_get_extmarks(buf, s.view.preview.ns, 0, -1, { details = true })
		local groups = {}
		for _, m in ipairs(marks) do
			groups[m[4].hl_group or m[4].line_hl_group] = true
		end
		truthy(groups.VCFinderPreviewPrompt)
		truthy(groups.VCFinderPreviewBand)
		s:close()
	end)
	describe("field terms", function()
		local ALL =
			{ "Fix flaky login test", "Draft Q4 roadmap outline", "Add SSO login to admin panel", "Old prototype" }

		it("narrows by the folder, not by a message that mentions the word", function()
			local s = open()
			type_query(s, "'dana") -- the recap and the last message of one session
			eq({ "Draft Q4 roadmap outline" }, titles(s))
			type_query(s, "cwd:dana")
			eq({}, titles(s))
			type_query(s, "cwd:notes")
			eq({ "Draft Q4 roadmap outline" }, titles(s))
			s:close()
		end)

		it("searches the rest of the query in what is left, in any order of terms", function()
			local s = open()
			type_query(s, "cwd:web login")
			eq({ "Add SSO login to admin panel" }, titles(s))
			type_query(s, "login cwd:web")
			eq({ "Add SSO login to admin panel" }, titles(s))
			type_query(s, "cwd:api login cwd:server")
			eq({ "Fix flaky login test" }, titles(s))
			s:close()
		end)

		it("needs both terms for the same field", function()
			local s = open()
			type_query(s, "cwd:x cwd:web")
			eq({ "Add SSO login to admin panel" }, titles(s))
			type_query(s, "cwd:api cwd:web")
			eq({}, titles(s))
			s:close()
		end)

		it("keeps the newest first for field terms alone, and drops New session", function()
			local s = open()
			type_query(s, "cwd:x")
			eq(ALL, titles(s))
			s:close()
		end)

		it("narrows nothing for a name with no value, and searches an unknown name as text", function()
			local s = open()
			type_query(s, "cwd:")
			eq(ALL, titles(s))
			type_query(s, "ticket:42")
			eq({}, titles(s))
			local r = vim.tbl_extend("force", ROWS[3], { id = "t", recap = "see ticket:42 for details" })
			s:set_rows({ r })
			type_query(s, "ticket:42") -- not a field, so it is found as text in the recap
			eq({ "Add SSO login to admin panel" }, titles(s))
			s:close()
		end)

		it("is not misled by the typing sequence cwd, cwd:, cwd:w", function()
			local s = open()
			type_query(s, "cwd")
			type_query(s, "cwd:w") -- straight from the plain word, as a paste would
			eq({ "Add SSO login to admin panel" }, titles(s))
			type_query(s, "cwd")
			type_query(s, "cwd:")
			eq(ALL, titles(s))
			type_query(s, "cwd:w")
			eq({ "Add SSO login to admin panel" }, titles(s))
			type_query(s, "cwd:wx")
			eq({}, titles(s))
			type_query(s, "cwd:w")
			eq({ "Add SSO login to admin panel" }, titles(s))
			s:close()
		end)

		it("matches the title loosely and the last message as written", function()
			local s = open()
			type_query(s, "title:flk")
			eq({ "Fix flaky login test" }, titles(s))
			type_query(s, "msg:pllng")
			eq({}, titles(s))
			type_query(s, "msg:polling")
			eq({ "Fix flaky login test" }, titles(s))
			s:close()
		end)

		it("reads a recap or a last message only from the sessions that have one", function()
			local s = open()
			type_query(s, "recap:roadmap")
			eq({ "Draft Q4 roadmap outline" }, titles(s))
			type_query(s, "recap:polling") -- only in a last message
			eq({}, titles(s))
			type_query(s, "msg:o") -- the sessions with no message never match
			eq({ "Fix flaky login test", "Draft Q4 roadmap outline" }, titles(s))
			s:close()
		end)

		it("takes a quoted value as one phrase", function()
			local s = open()
			type_query(s, 'title:"login test"')
			eq({ "Fix flaky login test" }, titles(s))
			type_query(s, 'title:"flaky test"') -- both words are there, not together
			eq({}, titles(s))
			type_query(s, "title:flaky polling") -- "polling" is a normal word: it is searched in every field
			eq({ "Fix flaky login test" }, titles(s))
			s:close()
		end)

		it("follows the case of the value", function()
			local s = open()
			type_query(s, "title:fix")
			eq({ "Fix flaky login test" }, titles(s))
			type_query(s, "title:FIX")
			eq({}, titles(s))
			type_query(s, "title:Fix")
			eq({ "Fix flaky login test" }, titles(s))
			s:close()
		end)

		it("highlights the matched letters of the field", function()
			local s = open()
			type_query(s, "cwd:api")
			local lines, ranges = source.format(s.query.matched[1], 60, { selected = true })
			local rows = texts(lines)
			local found = {}
			for _, r in ipairs(ranges) do
				found[#found + 1] = rows[r.row]:sub(r.s + 1, r.e)
			end
			eq({ "api" }, found)
			s:close()
		end)

		it("records the typed text and the field terms in the match state", function()
			local matcher = require("vc.finder.matcher")
			local items = source.items({ ROWS[1], ROWS[3] }, false)
			local state
			matcher.run(items, filter_of("cwd:api x"), { ignorecase = true, smartcase = true }, function(_, st)
				state = st or state
			end)
			wait(function()
				return state ~= nil
			end)
			eq("cwd:api x", state.pattern)
			truthy(state.has_terms)
		end)
		it("colours a recognised prefix in the prompt, even before it has a value", function()
			local s = open()
			local input = s.view.input
			local function marked()
				local out = {}
				local marks = vim.api.nvim_buf_get_extmarks(input.buf, input.field_ns, 0, -1, { details = true })
				for _, m in ipairs(marks) do
					local line = vim.api.nvim_buf_get_lines(input.buf, 0, 1, false)[1]
					eq("VCFinderField", m[4].hl_group)
					out[#out + 1] = line:sub(m[3] + 1, m[4].end_col)
				end
				return out
			end
			type_query(s, "cwd:")
			eq({ "cwd:" }, marked())
			type_query(s, "x title:nvim msg:y")
			eq({ "title:", "msg:" }, marked())
			type_query(s, "ticket:42 Cwd:x")
			eq({}, marked())
			type_query(s, "cwd:jarvix")
			type_query(s, "")
			eq({}, marked())
			s:close()
		end)
	end)
end)
