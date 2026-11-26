local cfg = {
	preview_ratio = 0.5,
	prompt_prefix = " ",
	selection_prefix = "▌",
	debounce = { normal_ms = 30, preview_ms = 60 },
	-- Conversation preview: result and diff lines shown before the rest folds, and the width of a call's arguments.
	preview = { result_lines = 3, diff_lines = 24, args_width = 80 },
	matcher = { smartcase = true, ignorecase = true },
}

return setmetatable({}, {
	__index = function(_, key)
		return cfg[key]
	end,
	__newindex = function(_, key)
		error(("vc.finder.config is read-only; cannot assign '%s'"):format(tostring(key)), 2)
	end,
})
