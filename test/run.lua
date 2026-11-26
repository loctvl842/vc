-- nvim --headless -u NONE -l test/run.lua [spec files...]
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.runtimepath:prepend(root)
package.path = root .. "/?.lua;" .. root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path
local h = require("test.harness")

local files = {}
for i = 1, #_G.arg do
	files[#files + 1] = _G.arg[i]
end
if #files == 0 then
	files = vim.fn.glob(root .. "/test/**/*_spec.lua", false, true)
end
table.sort(files)
for _, f in ipairs(files) do
	local ok, err = pcall(dofile, f)
	if not ok then
		h.failed = h.failed + 1
		io.stdout:write("ERROR loading " .. f .. "\n" .. tostring(err) .. "\n")
	end
end
io.stdout:write(("passed %d, failed %d\n"):format(h.passed, h.failed))
vim.cmd(h.failed == 0 and "qa!" or "cquit 1")
