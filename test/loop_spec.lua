local F = require("test.sessions.fixtures")
local vc = require("vc")
local claude = require("vc.claude")

local function press(role, key)
	local session = require("vc.finder").current()
	local lhs = vim.api.nvim_replace_termcodes(key, true, true, true)
	for _, mode in ipairs({ "i", "n" }) do
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(session.view[role].buf, mode)) do
			if vim.api.nvim_replace_termcodes(m.lhs, true, true, true) == lhs then
				return m.callback()
			end
		end
	end
	error("no mapping " .. key)
end

local function normal_wins()
	return vim.tbl_filter(function(w)
		return vim.api.nvim_win_get_config(w).relative == ""
	end, vim.api.nvim_list_wins())
end

describe("command", function()
	local store = F.store()
	local function item_for(row)
		return { row = row }
	end
	it("resumes in the session's folder, args passed positionally", function()
		local cmd, notice = claude.command(item_for({ id = "abc", cwd = store.alive }), "/here")
		eq({ vim.o.shell, "-c", 'cd "$1" && exec claude --resume "$2"', "vc", store.alive, "abc" }, cmd)
		eq(nil, notice)
	end)
	it("new session starts in Neovim's directory", function()
		local cmd = claude.command({ new = true }, "/here")
		eq({ vim.o.shell, "-c", 'cd "$1" && exec claude', "vc", "/here" }, cmd)
	end)
	it("a gone folder continues from here with a notice line", function()
		local cmd, notice = claude.command(item_for({ id = "abc", cwd = "/no/such/dir" }), "/here")
		eq("Original folder /no/such/dir is gone, continuing from /here", notice)
		eq({ "vc", notice, "abc" }, vim.list_slice(cmd, 4, 6))
	end)
end)

describe("loop", function()
	it("finder -> claude -> finder, one window while Claude Code runs", function()
		local store = F.store()
		-- a fake `claude` that records how it was started and quits when it reads a line
		local bin = tmpdir()
		local out = bin .. "/out.txt"
		write_file(bin .. "/claude", '#!/bin/sh\necho "$PWD|$*" > ' .. out .. "\nread line\nexit 0\n")
		vim.fn.system({ "chmod", "+x", bin .. "/claude" })
		local old_path = vim.env.PATH
		vim.env.PATH = bin .. ":" .. old_path

		vc.start({ index = { root = store.root, cache_path = tmpdir() .. "/idx.json" } })
		local finder = require("vc.finder")
		wait(function()
			return finder.current() and #finder.current().query.matched > 1
		end)
		eq(1, #normal_wins())

		local picked
		for i, item in ipairs(finder.current().query.matched) do
			if item.row and item.row.id == "titled" then
				picked = item.row
				require("vc.finder.ui").list.set_cursor(finder.current().view.list, i)
			end
		end
		press("input", "<CR>")
		wait(function()
			return finder.current() == nil and vim.fn.filereadable(out) == 1
		end)
		eq(1, #vim.api.nvim_list_wins())
		eq(vim.fn.resolve(picked.cwd), vim.fn.resolve(vim.fn.readfile(out)[1]:match("^(.-)|")))
		truthy(vim.fn.readfile(out)[1]:find("--resume " .. picked.id, 1, true))

		-- let the fake claude exit
		vim.fn.chansend(vim.bo.channel, "go\n")
		wait(function()
			return finder.current() ~= nil
		end, 5000)
		eq(1, #normal_wins())
		finder.close()
		vim.env.PATH = old_path
	end)
end)
