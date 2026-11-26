-- VimClaude: a Neovim config that only ever shows the Claude Code session finder or Claude Code.
-- Use with: NVIM_APPNAME=VimClaude nvim
vim.api.nvim_create_autocmd("VimEnter", {
	once = true,
	callback = function()
		require("vc").start()
	end,
})
