-- Reads one Claude Code transcript (.jsonl) into a finder row.
-- Lines are classified with plain-text finds and only a few are JSON-decoded,
-- so a 50 MB transcript full of api-request blobs scans quickly.
local M = {}

local MAX_TITLE = 120
local MAX_MESSAGE = 2000 -- a stored recap or last message; longer text ends with "…"
local CANDIDATES = 5 -- trailing user lines decoded when looking for the last message
local RECAP_HINT = " (disable recaps in /config)" -- Claude Code appends this to its first recaps

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

--- Whitespace collapsed to single spaces, trimmed.
---@param text string
---@return string
local function squash(text)
	return (text:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

--- `text` cut to `max` characters, ending with "…" when it was cut.
---@param text string
---@param max integer
---@return string
local function cap(text, max)
	if vim.fn.strchars(text) <= max then
		return text
	end
	return vim.fn.strcharpart(text, 0, max - 1) .. "…"
end

--- First readable text of a user record, or nil. A command with arguments reads as its arguments;
--- a bare command (`/clear`) has none.
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
	local args = content:match("<command%-args>(.-)</command%-args>")
	local text = squash((content:gsub("<[%w%-]+>.-</[%w%-]+>", " ")))
	if text == "" and args then
		text = squash(args)
	end
	return text ~= "" and text or nil
end

--- Prompt text of a user line, whole; nil for tool results and unreadable lines.
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

--- Recap text of a transcript line, or nil when the line is not a recap. Claude Code writes the automatic recap
--- as an `away_summary` system record and `/recap` as the stdout of a local command.
---@param line string
---@return string?
local function recap_of(line)
	local content
	if line:find('"subtype":"away_summary"', 1, true) then
		local o = decode(line)
		content = o and o.content
	elseif line:find('"subtype":"local_command"', 1, true) and line:find('"command":"recap"', 1, true) then
		local o = decode(line)
		content = o and o.commandRun and o.commandRun.command == "recap" and o.content
		content = type(content) == "string" and content:match("^<local%-command%-stdout>(.-)</local%-command%-stdout>$")
	end
	if type(content) ~= "string" then
		return nil
	end
	if content:sub(-#RECAP_HINT) == RECAP_HINT then
		content = content:sub(1, -#RECAP_HINT - 1)
	end
	content = squash(content)
	return content ~= "" and cap(content, MAX_MESSAGE) or nil
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
---@field recap string? latest session recap, when Claude Code wrote one
---@field last_prompt string? the last message the user wrote (never a bare command); nil when it is the title
---@field branch string? git branch of the session's last message; nil when unknown or detached
---@field pr integer? number of the pull request the session is linked to
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
	local cwd, ai_title, first_prompt, last_ts_line, recap, last_line, pr
	local candidates = {} -- the last few user lines that may hold the user's last message
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
		elseif line:find('"type":"system"', 1, true) then
			recap = recap_of(line) or recap
		elseif line:find('"type":"pr-link"', 1, true) then
			local o = decode(line)
			pr = o and type(o.prNumber) == "number" and o.prNumber or pr
		else
			local is_user = line:find('"type":"user"', 1, true)
			local is_asst = not is_user and line:find('"type":"assistant"', 1, true)
			if
				(is_user or is_asst)
				and not line:find('"isSidechain":true', 1, true)
				and not line:find('"isMeta":true', 1, true)
			then
				count = count + 1
				last_line = line
				if not cwd then
					local c = line:match('"cwd":"(.-[^\\])"')
					if c then
						local ok, v = pcall(vim.json.decode, '"' .. c .. '"')
						cwd = ok and v or c
					end
				end
				if is_user and not first_prompt then
					local first = M.prompt_of(line)
					first_prompt = first and vim.fn.strcharpart(first, 0, MAX_TITLE)
				end
				if
					is_user
					and not line:find('"type":"tool_result"', 1, true)
					and not line:find('"isCompactSummary":true', 1, true)
				then
					candidates[#candidates + 1] = line
					if #candidates > CANDIDATES then
						table.remove(candidates, 1)
					end
				end
			end
		end
	end

	local title = ai_title or first_prompt or "(untitled)"

	local last_prompt
	for i = #candidates, 1, -1 do
		local t = M.prompt_of(candidates[i])
		-- A built-in command such as /compact is stored as plain text, with no command tags to strip.
		if t and not t:find("^%[Request interrupted") and not t:find("^/[%w:_%-]+$") then
			last_prompt = t
			break
		end
	end
	if last_prompt and vim.fn.strcharpart(last_prompt, 0, MAX_TITLE) == title then
		last_prompt = nil
	end

	local branch = last_line and last_line:match('"gitBranch":"([^"]*)"')
	if branch == "" or branch == "HEAD" then
		branch = nil
	end

	local last_ts = M.parse_ts(last_ts_line and last_ts_line:match('"timestamp":"([^"]+)"')) or meta.mtime
	return {
		id = id,
		path = meta.path,
		title = title,
		project = project_of(cwd, dirname),
		cwd = cwd,
		recap = recap,
		last_prompt = last_prompt and cap(last_prompt, MAX_MESSAGE),
		branch = branch,
		pr = pr,
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
