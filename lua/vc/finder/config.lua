local cfg = {
	preview_ratio = 0.5,
	prompt_prefix = " ",
	selection_prefix = "▌",
	debounce = { normal_ms = 30, preview_ms = 60 },
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
