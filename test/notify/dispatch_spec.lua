local notify = require("vc.notify")

---@param ft string
---@return integer
local function floats(ft)
	local n = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_win_get_config(win).relative ~= "" and vim.bo[buf].filetype == ft then
			n = n + 1
		end
	end
	return n
end

---@return string
local function toast_text()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.bo[buf].filetype == "vc-toast" then
			return vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1]
		end
	end
	return ""
end

describe("notify dispatch by level", function()
	before_each(function()
		notify.setup({
			timeout = 60000,
			stagger = 1,
			anim_ms = 10,
			toast = { timeout = 60000, stagger = 1, anim_ms = 10 },
		})
		vim.o.columns = 100
		vim.o.lines = 40
		vim.o.cmdheight = 0
		vim.o.laststatus = 0
		wait(function()
			notify.dismiss()
			return floats("vc-toast") + floats("vc-notify") == 0
		end)
	end)

	it("shows INFO as a toast and not as a card", function()
		notify.notify("hello there", "INFO")
		wait(function()
			return floats("vc-toast") == 1
		end)
		eq(0, floats("vc-notify"))
	end)

	it("treats a message without a level as INFO", function()
		notify.notify("hello there")
		wait(function()
			return floats("vc-toast") == 1
		end)
		eq(0, floats("vc-notify"))
	end)

	it("shows WARN and ERROR as cards and not as toasts", function()
		notify.notify("careful", "WARN")
		notify.notify("broken", vim.log.levels.ERROR)
		wait(function()
			return floats("vc-notify") == 2
		end)
		eq(0, floats("vc-toast"))
	end)

	it("shows nothing for DEBUG and TRACE", function()
		notify.notify("noise", "DEBUG")
		notify.notify("noise", "TRACE")
		vim.wait(50)
		eq(0, floats("vc-toast") + floats("vc-notify"))
	end)

	it("shows a toast and a card side by side", function()
		notify.notify("fine", "INFO")
		notify.notify("not fine", "ERROR")
		wait(function()
			return floats("vc-toast") == 1 and floats("vc-notify") == 1
		end)
	end)

	it("merges five identical INFO messages into one toast with a count", function()
		for _ = 1, 5 do
			notify.notify("written to disk", "INFO")
		end
		wait(function()
			return floats("vc-toast") == 1 and toast_text():find("x5", 1, true) ~= nil
		end)
	end)

	it("shows an INFO raised through vim.notify from a fast event", function()
		vim.uv.new_timer():start(0, 0, function()
			vim.notify("from a timer")
		end)
		wait(function()
			return floats("vc-toast") == 1
		end)
	end)

	it("clears both kinds on dismiss", function()
		notify.notify("fine", "INFO")
		notify.notify("not fine", "WARN")
		wait(function()
			return floats("vc-toast") == 1 and floats("vc-notify") == 1
		end)
		notify.dismiss()
		wait(function()
			return floats("vc-toast") + floats("vc-notify") == 0
		end)
	end)
end)
