--- The terminal's real colors. Neovim cannot read them, so ask the terminal (OSC 10/11/4) and keep the
--- answer; `highlights` blends tints from it. A terminal that does not answer leaves `palette` nil and
--- the finder falls back to the 16-color palette indexes.
local M = {}

---@alias VC.RGB integer[] r, g, b in 0-255
---@class VC.Palette : table<integer|string, VC.RGB>
---@field fg VC.RGB
---@field bg VC.RGB

---@type VC.Palette?
M.palette = nil
M.pending = false

local TIMEOUT_MS = 200
local EXPECTED = 18 -- foreground, background, 16 palette slots

--- `ESC ] 10 ; rgb:RRRR/GGGG/BBBB ST` -> "fg", {r, g, b}; slot replies (`ESC ] 4 ; N ; ...`) -> N.
---@param seq string
---@return (string|integer)?, VC.RGB?
function M.parse(seq)
	local code, rest = seq:match("^\27%](%d+);(.*)$")
	local key ---@type (string|integer)?
	if code == "10" then
		key = "fg"
	elseif code == "11" then
		key = "bg"
	elseif code == "4" then
		local idx
		idx, rest = rest:match("^(%d+);(.*)$")
		key = idx and tonumber(idx)
	end
	local r, g, b = (rest or ""):match("^rgb:(%x+)/(%x+)/(%x+)")
	if not key or not r then
		return
	end
	local function channel(h)
		return math.floor(tonumber(h, 16) / (16 ^ #h - 1) * 255 + 0.5)
	end
	return key, { channel(r), channel(g), channel(b) }
end

---@param c VC.RGB
---@return string
function M.hex(c)
	return ("#%02x%02x%02x"):format(c[1], c[2], c[3])
end

--- `a` moved `t` (0-1) of the way to `b`.
---@param a VC.RGB
---@param b VC.RGB
---@param t number
---@return string
function M.mix(a, b, t)
	local out = {}
	for i = 1, 3 do
		out[i] = math.floor(a[i] + (b[i] - a[i]) * t + 0.5)
	end
	return M.hex(out)
end

--- Query the terminal. `on_done(palette?)` runs once, with the new palette, the previous one if the
--- terminal answered only in part, or nil. Without a terminal UI it runs at once.
---@param on_done? fun(palette: VC.Palette?)
function M.refresh(on_done)
	if M.pending then
		return
	end
	if #vim.api.nvim_list_uis() == 0 then
		if on_done then
			on_done(M.palette)
		end
		return
	end
	M.pending = true
	local got, count = {}, 0
	local group = vim.api.nvim_create_augroup("VCTheme", { clear = true })
	local function finish()
		if not M.pending then
			return
		end
		M.pending = false
		pcall(vim.api.nvim_del_augroup_by_id, group)
		if count == EXPECTED then
			M.palette = got
		end
		if on_done then
			on_done(M.palette)
		end
	end
	vim.api.nvim_create_autocmd("TermResponse", {
		group = group,
		callback = function(ev)
			local key, rgb = M.parse(ev.data.sequence or "")
			if key and not got[key] then
				got[key], count = rgb, count + 1
				if count == EXPECTED then
					finish()
				end
			end
		end,
	})
	local query = { "\27]10;?\27\\", "\27]11;?\27\\" }
	for i = 0, 15 do
		query[#query + 1] = ("\27]4;%d;?\27\\"):format(i)
	end
	vim.api.nvim_ui_send(table.concat(query))
	vim.defer_fn(finish, TIMEOUT_MS)
end

--- Switch to true colors when the terminal told us its colors, and give `:terminal` buffers (Claude
--- Code) the same 16 colors. Otherwise stay on palette indexes.
function M.activate()
	if not M.palette then
		return
	end
	vim.o.termguicolors = true
	for i = 0, 15 do
		vim.g["terminal_color_" .. i] = M.hex(M.palette[i])
	end
end

return M
