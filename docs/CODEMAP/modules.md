<!-- Generated: 2026-11-26 | Files scanned: 31 | Token estimate: ~593 -->

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

## transcript
**Path:** `lua/vc/transcript.lua`
- `render(text, row?) -> lines, folds`; `render_file(path, row, on_done) -> cancel` (chunked)
- `builder(header?)` -> `:feed(line)`, `:finish()`; fold = `{start, stop, label}`

## finder
**Path:** `lua/vc/finder/`
- `open({cwd?, on_confirm(item), on_exit()}) -> Session`, `close()`, `current()`
- Session: `set_rows(rows)`, `busy(on)`, `close()`, `relayout()`
- `source.items(rows, with_new)`: search text = title, folder (fuzzy) then recap, last message (substring only, `fuzzy_len`)
- `source.format(item, width, {selected?, max_rows?}) -> lines, ranges`: title, folder row (+branch, PR), wrapped recap and last message (3 lines unless selected, runs on to a match), blank row
- `wrap.lines(text, width) -> {s, e}[]` byte spans; `source.location(row)`, `source.relative_time`
- `ui.input`, `ui.list` (items span several rows; height depends on the cursor), `ui.preview` (`show(row)`, `note`, foldexpr/foldtext)
- Deps: `vc.transcript`, `vc.debounce`; `VCFinder*` groups use the terminal palette (cterm 0-15, `NONE` bg); `highlights.setup()` re-tints the selected row on `OptionSet background`
