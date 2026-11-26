<!-- Generated: 2026-11-26 | Files scanned: 28 | Token estimate: ~356 -->

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
- Row: `id path title project cwd last_ts msg_count size mtime cwd_exists`

## theme
**Path:** `lua/vc/theme.lua`
- `refresh(on_done?)` queries OSC 10/11/4 (200 ms timeout), `palette` (nil if unanswered), `activate()`, `parse(seq)`, `mix(a, b, t)`, `hex(rgb)`
- Re-run from `finder.highlights` on `OptionSet background` and `FocusGained`

## transcript
**Path:** `lua/vc/transcript.lua`
- `render(text, row?) -> lines, folds`; `render_file(path, row, on_done) -> cancel` (chunked)
- `builder(header?)` -> `:feed(line)`, `:finish()`; fold = `{start, stop, label}`

## finder
**Path:** `lua/vc/finder/`
- `open({cwd?, on_confirm(item), on_exit()}) -> Session`, `close()`, `current()`
- Session: `set_rows(rows)`, `busy(on)`, `close()`, `relayout()`
- `source.items(rows, with_new)`, `source.format(item, width) -> lines, ranges`, `source.relative_time`
- `ui.input`, `ui.list` (items span several rows), `ui.preview` (`show(row)`, `note`, foldexpr/foldtext)
- Deps: `vc.transcript`, `vc.debounce`; `VCFinder*` groups use the terminal palette (cterm 0-15, `NONE` bg); `highlights.setup()` re-tints the selected row on `OptionSet background`
