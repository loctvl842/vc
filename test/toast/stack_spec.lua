local toast = require("vc.toast")

---@return { row: integer, text: string, width: integer }[] toasts, top first
local function toasts()
	local out = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local c = vim.api.nvim_win_get_config(win)
		local buf = vim.api.nvim_win_get_buf(win)
		if c.relative ~= "" and vim.bo[buf].filetype == "vc-toast" then
			out[#out + 1] = { row = c.row, text = vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1], width = c.width }
		end
	end
	table.sort(out, function(a, b)
		return a.row < b.row
	end)
	return out
end

describe("toast stack", function()
	before_each(function()
		toast.setup({ timeout = 60000, stagger = 1, anim_ms = 10 })
		vim.o.columns = 100
		vim.o.lines = 40
		vim.o.cmdheight = 0
		vim.o.laststatus = 0
		-- Toasts still queued from the previous spec appear after a dismiss, so keep dismissing.
		wait(function()
			toast.dismiss()
			return #toasts() == 0
		end)
	end)

	it("shows one line in the last row, right aligned", function()
		toast("written")
		wait(function()
			return #toasts() == 1
		end)
		local t = toasts()[1]
		eq(40, t.row) -- the bottom edge of the last row of 40
		eq(true, vim.startswith(t.text, "written"))
	end)

	it("merges an identical message into one line with a count", function()
		toast("written")
		wait(function()
			return #toasts() == 1
		end)
		for _ = 1, 4 do
			toast("written")
		end
		wait(function()
			return #toasts() == 1 and toasts()[1].text:find("x5", 1, true) ~= nil
		end)
	end)

	it("stacks different messages, newest at the bottom", function()
		toast("first")
		toast("second")
		toast("third")
		wait(function()
			return #toasts() == 3
		end)
		local t = toasts()
		eq(true, vim.startswith(t[1].text, "first"))
		eq(true, vim.startswith(t[3].text, "third"))
		eq(1, t[2].row - t[1].row)
	end)

	it("shows a multi-line message on one line", function()
		toast("one\ntwo")
		wait(function()
			return #toasts() == 1
		end)
		eq(true, vim.startswith(toasts()[1].text, "one two"))
	end)

	it("cuts a long message with an ellipsis", function()
		toast(string.rep("word ", 40))
		wait(function()
			return #toasts() == 1
		end)
		eq(true, toasts()[1].text:find("…", 1, true) ~= nil)
		eq(60, toasts()[1].width)
	end)

	it("shows a toast raised in a fast event", function()
		vim.uv.new_timer():start(0, 0, function()
			toast("from a timer")
		end)
		wait(function()
			return #toasts() == 1
		end)
	end)

	it("removes the oldest toasts instead of growing past the top", function()
		vim.o.lines = 6
		for i = 1, 10 do
			toast("m" .. i)
		end
		wait(function()
			local t = toasts()
			return #t > 0 and #t <= 6 and t[#t].text:find("m10", 1, true) ~= nil
		end)
	end)

	it("follows the terminal when it is resized", function()
		toast("written")
		wait(function()
			return #toasts() == 1
		end)
		vim.o.lines = 30
		vim.api.nvim_exec_autocmds("VimResized", {})
		wait(function()
			return toasts()[1].row == 30
		end)
	end)

	it("shows nothing below the configured level", function()
		toast.setup({ timeout = 60000, level = vim.log.levels.WARN })
		toast("quiet", "INFO")
		vim.wait(50)
		eq(0, #toasts())
	end)
end)
