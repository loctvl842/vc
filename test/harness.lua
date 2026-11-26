-- Minimal headless spec harness: nvim --headless -l test/run.lua [spec files]
local M = { failed = 0, passed = 0 }
local stack, befores = {}, {}

function _G.describe(name, fn)
	stack[#stack + 1] = name
	local saved = vim.deepcopy(befores)
	fn()
	befores = saved
	stack[#stack] = nil
end

function _G.before_each(fn)
	befores[#befores + 1] = fn
end

function _G.it(name, fn)
	local full = table.concat(stack, " ") .. " " .. name
	for _, b in ipairs(befores) do
		b()
	end
	local ok, err = xpcall(fn, debug.traceback)
	if ok then
		M.passed = M.passed + 1
	else
		M.failed = M.failed + 1
		io.stdout:write("FAIL " .. full .. "\n" .. tostring(err) .. "\n")
	end
end

function _G.eq(expected, actual, msg)
	if not vim.deep_equal(expected, actual) then
		error(
			(msg or "not equal") .. "\nexpected: " .. vim.inspect(expected) .. "\nactual:   " .. vim.inspect(actual),
			2
		)
	end
end

function _G.truthy(v, msg)
	if not v then
		error(msg or ("expected truthy, got " .. vim.inspect(v)), 2)
	end
end

--- Run `fn` until `cond()` is true or `ms` elapse, pumping the event loop.
function _G.wait(cond, ms)
	local ok = vim.wait(ms or 2000, cond, 5)
	if not ok then
		error("wait timed out", 2)
	end
end

--- Make a fresh temp dir; returns its path.
function _G.tmpdir()
	local d = vim.fn.tempname()
	vim.fn.mkdir(d, "p")
	return d
end

function _G.write_file(path, lines)
	vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
	local f = assert(io.open(path, "w"))
	f:write(type(lines) == "table" and table.concat(lines, "\n") .. "\n" or lines)
	f:close()
end

return M
