-- Index of every Claude Code session on the machine. Read-only on the store.
local scan = require("vc.sessions.scan")
local cache = require("vc.sessions.cache")

local M = {}

local BATCH = 8 -- files rescanned per event-loop turn
local PARTIAL_MS = 150 -- while rescanning, show what is known at most this often

---@return string
function M.default_root()
	return vim.fs.joinpath(vim.env.HOME or vim.uv.os_homedir(), ".claude", "projects")
end

--- Top-level *.jsonl files of every project dir (subagent dirs are ignored).
---@param root string
---@return { path: string, stat: table }[]
local function list_files(root)
	local files = {}
	for dir, kind in vim.fs.dir(root) do
		if kind == "directory" then
			local base = vim.fs.joinpath(root, dir)
			for name, k in vim.fs.dir(base) do
				if k == "file" and name:sub(-6) == ".jsonl" then
					local path = vim.fs.joinpath(base, name)
					local stat = vim.uv.fs_stat(path)
					if stat then
						files[#files + 1] = { path = path, stat = stat }
					end
				end
			end
		end
	end
	return files
end

---@param rows table<string, VC.Row>
---@return VC.Row[]
local function sorted(rows)
	local list = {}
	for _, row in pairs(rows) do
		row.cwd_exists = row.cwd ~= nil and vim.uv.fs_stat(row.cwd) ~= nil
		list[#list + 1] = row
	end
	table.sort(list, function(a, b)
		if a.last_ts ~= b.last_ts then
			return a.last_ts > b.last_ts
		end
		return a.id < b.id
	end)
	return list
end

--- Load the index. `on_rows(rows, done)` is called once with the cached rows
--- right away (when any exist) and again after changed files are rescanned.
---@param opts? { root?: string, cache_path?: string }
---@param on_rows fun(rows: VC.Row[], done: boolean)
---@return fun() cancel stops a rescan in flight; nothing more is delivered or cached
function M.load(opts, on_rows)
	opts = opts or {}
	local root = opts.root or M.default_root()
	local cache_path = opts.cache_path or cache.default_path()

	local cached = cache.read(cache_path)
	local files = list_files(root)
	local todo = {}
	local rows = {}
	for _, file in ipairs(files) do
		local c = cached[file.path]
		if c and c.size == file.stat.size and c.mtime == file.stat.mtime.sec then
			rows[file.path] = c
		else
			todo[#todo + 1] = file
		end
	end

	local cancelled = false
	local function cancel()
		cancelled = true
	end

	if #todo == 0 then
		if vim.tbl_count(cached) ~= #files then
			cache.write(cache_path, rows)
		end
		on_rows(sorted(rows), true)
		return cancel
	end
	if next(rows) then
		on_rows(sorted(rows), false)
	end

	local i = 1
	local last_emit = vim.uv.hrtime()
	local function step()
		-- stylua: ignore
		if cancelled then return end
		local stop = math.min(i + BATCH - 1, #todo)
		for j = i, stop do
			local row = scan.scan_file(todo[j].path, todo[j].stat)
			if row then
				rows[todo[j].path] = row
			end
		end
		i = stop + 1
		if i <= #todo then
			if (vim.uv.hrtime() - last_emit) / 1e6 > PARTIAL_MS then
				last_emit = vim.uv.hrtime()
				on_rows(sorted(rows), false)
			end
			vim.schedule(step)
			return
		end
		cache.write(cache_path, rows)
		on_rows(sorted(rows), true)
	end
	step()
	return cancel
end

return M
