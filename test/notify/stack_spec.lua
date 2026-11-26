local notify = require("vc.notify")

local function open_cards()
	local n = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			n = n + 1
		end
	end
	return n
end

local function card_rows()
	local rows = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local c = vim.api.nvim_win_get_config(win)
		if c.relative ~= "" then
			rows[#rows + 1] = c.row
		end
	end
	table.sort(rows)
	return rows
end

describe("notify stack", function()
	before_each(function()
		notify.setup({ timeout = 60000, stagger = 1, anim_ms = 10 })
		vim.o.columns = 100
		vim.o.lines = 40
		-- Cards still queued from the previous spec appear after a dismiss, so keep dismissing.
		wait(function()
			notify.dismiss()
			return open_cards() == 0
		end)
	end)

	it("shows a card and stacks the next one below it", function()
		notify.notify("first", "ERROR")
		notify.notify("second", "WARN")
		wait(function()
			return open_cards() == 2
		end)
		local rows = card_rows()
		eq(0, rows[1])
		eq(4, rows[2] - rows[1]) -- title row + 1 line + 2 border rows
	end)

	it("filters messages below the configured level", function()
		notify.setup({ timeout = 60000, level = vim.log.levels.WARN })
		notify.notify("quiet", "INFO")
		vim.wait(50)
		eq(0, open_cards())
	end)

	it("shows a message raised in a fast event", function()
		vim.uv.new_timer():start(0, 0, function()
			vim.notify("from a timer", vim.log.levels.WARN)
		end)
		wait(function()
			return open_cards() == 1
		end)
	end)

	it("slides the oldest cards out when the stack would pass the bottom", function()
		vim.o.lines = 12
		for i = 1, 6 do
			notify.notify("m" .. i, "WARN")
		end
		wait(function()
			local rows = card_rows()
			return #rows > 0 and #rows <= 3 and rows[#rows] + 3 <= 12
		end)
	end)

	it("closes every card on dismiss", function()
		notify.notify("a", "WARN")
		notify.notify("b", "WARN")
		wait(function()
			return open_cards() == 2
		end)
		notify.dismiss()
		wait(function()
			return open_cards() == 0
		end)
	end)
end)
