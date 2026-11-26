-- Reads one Claude Code transcript (.jsonl) into a finder row.
-- Lines are classified with plain-text finds and only a few are JSON-decoded,
-- so a 50 MB transcript full of api-request blobs scans quickly.
local M = {}

local MAX_TITLE = 120

--- Days since the unix epoch for a proleptic Gregorian date.
local function days_from_civil(y, m, d)
	y = m <= 2 and y - 1 or y
	local era = math.floor(y / 400)
	local yoe = y - era * 400
	local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
	local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
	return era * 146097 + doe - 719468
end

--- "2026-11-26T10:20:30.123Z" -> epoch seconds (UTC), or nil.
---@param iso string?
---@return integer?
function M.parse_ts(iso)
	local y, mo, d, h, mi, s = (iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not y then
		return nil
	end
	return days_from_civil(tonumber(y), tonumber(mo), tonumber(d)) * 86400
		+ tonumber(h) * 3600
		+ tonumber(mi) * 60
		+ tonumber(s)
end

local function decode(line)
	local ok, obj = pcall(vim.json.decode, line, { luanil = { object = true, array = true } })
	return ok and type(obj) == "table" and obj or nil
end

--- First readable text of a user record, or nil.
local function user_text(obj)
	local content = obj.message and obj.message.content
	if type(content) == "table" then
		for _, b in ipairs(content) do
			if b.type == "text" and type(b.text) == "string" then
				content = b.text
				break
			end
		end
	end
	if type(content) ~= "string" then
		return nil
	end
	content = content:gsub("<[%w%-]+>.-</[%w%-]+>", " "):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
	if content == "" then
		return nil
	end
	return vim.fn.strcharpart(content, 0, MAX_TITLE)
end

--- Prompt text of a user line; nil for tool results and unreadable lines.
---@param line string
---@return string?
function M.prompt_of(line)
	local o = decode(line)
	if not o or o.type ~= "user" then
		return nil
	end
	local content = o.message and o.message.content
	if type(content) == "table" and content[1] and content[1].type == "tool_result" then
		return nil
	end
	return user_text(o)
end

--- Project name from a folder path.
local function project_of(cwd, dirname)
	if cwd and cwd ~= "" then
		return vim.fs.basename(cwd)
	end
	return dirname
end

---@class VC.Row
---@field id string
---@field path string
---@field title string
---@field project string
---@field cwd string?
---@field last_ts integer
---@field msg_count integer
---@field size integer
---@field mtime integer
---@field cwd_exists boolean?

--- Parse the text of one transcript.
---@param text string
---@param meta { path: string, size: integer, mtime: integer }
---@return VC.Row
function M.parse(text, meta)
	local id = vim.fs.basename(meta.path):gsub("%.jsonl$", "")
	local dirname = vim.fs.basename(vim.fs.dirname(meta.path))
	local cwd, ai_title, first_prompt, last_ts_line
	local count = 0

	for line in text:gmatch("[^\n]+") do
		if line:find('"timestamp":"', 1, true) then
			last_ts_line = line
		end
		if line:find('"type":"ai-title"', 1, true) then
			local o = decode(line)
			if o and o.type == "ai-title" and type(o.aiTitle) == "string" and o.aiTitle ~= "" then
				ai_title = o.aiTitle
			end
		else
			local is_user = line:find('"type":"user"', 1, true)
			local is_asst = not is_user and line:find('"type":"assistant"', 1, true)
			if
				(is_user or is_asst)
				and not line:find('"isSidechain":true', 1, true)
				and not line:find('"isMeta":true', 1, true)
			then
				count = count + 1
				if not cwd then
					local c = line:match('"cwd":"(.-[^\\])"')
					if c then
						local ok, v = pcall(vim.json.decode, '"' .. c .. '"')
						cwd = ok and v or c
					end
				end
				if is_user and not first_prompt then
					first_prompt = M.prompt_of(line)
				end
			end
		end
	end

	local last_ts = M.parse_ts(last_ts_line and last_ts_line:match('"timestamp":"([^"]+)"')) or meta.mtime
	return {
		id = id,
		path = meta.path,
		title = ai_title or first_prompt or "(untitled)",
		project = project_of(cwd, dirname),
		cwd = cwd,
		last_ts = last_ts,
		msg_count = count,
		size = meta.size,
		mtime = meta.mtime,
	}
end

--- Read and parse a transcript file; nil when it cannot be read.
---@param path string
---@param stat { size: integer, mtime: { sec: integer } }
---@return VC.Row?
function M.scan_file(path, stat)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local text = f:read("*a") or ""
	f:close()
	return M.parse(text, { path = path, size = stat.size, mtime = stat.mtime.sec })
end

return M
