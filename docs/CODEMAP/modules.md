<!-- Generated: 2026-11-27 | Files scanned: 75 | Token estimate: ~1000 -->

# Modules

## vc (state machine)
**Path:** `lua/vc/init.lua`, `claude.lua`
- `start(opts?)`, `show_finder()`, `open_item(item)`
- `claude.command(item, here) -> cmd, notice?`, `claude.run(item, on_exit(code)) -> started`
- Deps: `vc.finder`, `vc.sessions.index`

## sessions
**Path:** `lua/vc/sessions/`
- `scan.parse(text, meta) -> VC.Row`, `scan.scan_file(path, stat)`, `scan.parse_ts(iso)`
- `cache.read(path)`, `cache.write(path, rows)`, `cache.default_path()`
- `index.load({root?, cache_path?}, on_rows(rows, done)) -> cancel`; rows newest first, `cwd_exists` set
- Row: `id path title project cwd recap last_prompt branch pr last_ts msg_count size mtime cwd_exists`
- `recap`: latest `/recap` or `away_summary`; `last_prompt`: last real user message (bare commands, compaction summaries, interruptions skipped); both capped at 2000 chars; `branch` nil when detached; cache `VERSION` 3

## theme
**Path:** `lua/vc/theme.lua`
- `refresh(on_done?)` queries OSC 10/11/4 (200 ms timeout), `palette` (nil if unanswered), `activate()`, `parse(seq)`, `mix(a, b, t)`, `hex(rgb)`
- Re-run from `finder.highlights` on `OptionSet background` and `FocusGained`

## notify
**Path:** `lua/vc/notify/`, `lua/vc/animate.lua`
- `setup(opts?)` replaces `vim.notify` (fast events are scheduled), `notify(message, level?, {title?, icon?, timeout?}) -> record`, `dismiss()`
- Cards: up to 80 columns (`config.width()` = min(80, columns - 2)), text wrapped with `vc.finder.wrap`, 10 rows max, `zindex` 200, fade in, slide out after `timeout` (3 s)
- Oldest cards slide out early when the stack would pass the bottom; a leaving card takes no room
- Level dispatch in `notify`: INFO -> `vc.toast`, WARN and ERROR -> cards, DEBUG and TRACE filtered; `dismiss()` clears both
- `animate.tween(ms, on_frame, on_done)`, `animate.run(win, from, to, ms, on_done, opts)`
- Deps: `vc.finder.view`, `vc.finder.wrap`, `vc.theme`; groups `VCNotify{Normal,Border,ERROR,WARN,INFO,DEBUG,TRACE}`

## toast
**Path:** `lua/vc/toast/`
- `toast(message, level?, opts?) -> record` (callable; a fast event is scheduled), `setup(opts?)`, `dismiss()`
- One borderless line in the last screen row (`anchor = "SE"`, 1 column margin), width 10 to 60% of the terminal, text then level icon; line breaks become spaces, long text ends with an ellipsis
- Identical visible toasts merge: `x2` .. `x99`, `x99+`; each merge restarts the 2.2 s timer; stack capped at the free rows, oldest leave early
- Deps: `vc.animate`, `vc.finder.view`; groups `VCToast{Normal,Body,TitleERROR..,Count}` defined in `vc.notify.highlights`

## messages
**Path:** `lua/vc/messages/`
- `setup(opts?)` enables `vim._core.ui2` (nvim 0.12) and wraps `ui2.messages.msg_show`; any error falls back to ui2's own output
- `router.resolve(routes, kind, text, passthrough) -> {drop} | {text, level, id?, cancels?} | nil`, `router.flatten(content)`
- Levels: `emsg echoerr lua_error rpc_error` ERROR, `wmsg` WARN, the rest INFO; `search_count` and empty text dropped; `confirm confirm_sub return_prompt number_prompt` stay with ui2
- Deps: `vc.notify`

## transcript
**Path:** `lua/vc/transcript.lua`, `markdown.lua`, `code.lua`, `toolline.lua`
- `render(text, row?) -> lines, folds, marks`; `render_file(path, row, on_done, on_partial?) -> cancel` (chunked: 50 records + 20 blocks per turn, top of the doc via `on_partial`)
- `builder(header?)` -> `:feed(line)`, `:render(final, max)`, `:finish()`; blocks: prompt, reply, thinking, call (result paired by tool_use_id), result
- `markdown.render(text) -> lines, marks` (tree-sitter; plain text if no parser); `code.marks(code, lang) -> marks`
- `toolline.call(name, input, cwd) -> name, args`, `result_lines(res)`, `diff(rec) -> {summary, lines, marks}`, `split`, `clean`
- Mark: `{l, c?, e?, hl, line?}`; fold = `{start, stop, label}`; tunables in `finder.config.preview`

## finder
**Path:** `lua/vc/finder/`
- `open({cwd?, on_confirm(item), on_exit()}) -> Session`, `close()`, `current()`
- Session: `set_rows(rows)`, `busy(on)`, `close()`, `relayout()`
- `source.items(rows, with_new)`: search text = title, folder (fuzzy) then recap, last message (substring only, `fuzzy_len`)
- `source.format(item, width, {selected?, max_rows?}) -> lines, ranges`: title, folder row (+branch, PR), wrapped recap and last message (3 lines unless selected, runs on to a match), blank row
- `wrap.lines(text, width) -> {s, e}[]` byte spans; `source.location(row)`, `source.relative_time`
- `ui.input`, `ui.list` (items span several rows; height depends on the cursor), `ui.preview` (`show(row)`, `note`, marks as extmarks, foldexpr/foldtext, hanging indent via breakindent)
- Deps: `vc.transcript`, `vc.debounce`; `VCFinder*` groups use the terminal palette (cterm 0-15, `NONE` bg); `highlights.setup()` re-tints the selected row on `OptionSet background`
