<!-- Generated: 2026-11-26 | Files scanned: 28 | Token estimate: ~672 -->

# Architecture

## Entry Point
`init.lua` -> on `VimEnter` calls `require("vc").start()`. Run with `NVIM_APPNAME=VimClaude nvim`.

## Module Tree
```
init.lua                      entry (VimEnter -> vc.start)
lua/vc/
  init.lua                    two-screen state machine: finder <-> claude
  claude.lua                  Claude Code in a full-window terminal buffer
  transcript.lua              .jsonl -> markdown lines + fold map (whole conversation)
  debounce.lua                trailing-edge debounce (uv timer)
  sessions/
    scan.lua                  one .jsonl -> row (title, project, cwd, last_ts, msg_count)
    cache.lua                 versioned index file under stdpath("cache")/vc
    index.lua                 walk ~/.claude/projects, reuse cache, rescan changed, cancellable
  finder/                     trimmed copy of the BeastVim finder, one source
    init.lua                  Session: open/close/set_rows/busy/relayout
    source.lua                items + row format ("New session" only on empty query)
    render.lua                matched -> list, footer, debounced preview
    keymaps.lua autocmds.lua  keys per pane; cursor hiding, resize, focus guard
    layout.lua highlights.lua config.lua   full-screen geometry, terminal-palette groups
    query.lua filter.lua host.lua          state holders, pipeline-to-UI contract
    pipeline/match.lua        load items once, rescore per keystroke
    matcher.lua score.lua topk.lua async.lua   fuzzy engine (copied from BeastVim)
    view.lua                  Instance base + buf/win helpers
    ui/{input,list,preview}.lua   prompt, 2-row virtual list, folding preview
test/                         headless specs (make test), harness in test/harness.lua
scripts/bench-index.lua       cold/warm index timing on synthetic store
```

## Setup Flow
1. `vc.start` sets UI options (no statusline/tabline/cmdline, no intro) and `termguicolors` off, so the terminal theme paints everything, Claude Code included.
2. `show_finder`: reset to one empty window, `finder.open`, `index.load` (cache rows first, then rescan).
3. Enter -> `open_item` -> `claude.run`; `on_exit` -> `show_finder` again (any exit code).
4. Esc -> cancel index load, `qa!`.

## Claude Code Integration
- Reads `~/.claude/projects/*/*.jsonl` (read-only; top-level files only).
- Spawns `sh -c 'cd "$1" && exec claude --resume "$2"'` via `jobstart{term=true}`.
- Folder gone: prints a notice, runs from Neovim's cwd. New session: `cd <cwd> && exec claude`.

## Reload / Lifecycle Contracts
- Preview cache is keyed `id:size:mtime` (a resumed session is reread).
- `finder.highlights` autocmd (`OptionSet background`) only redefines highlight groups, never buffers or windows.
- `finder.autocmds.restore_cursor` runs on every close (guicursor is hidden while the list is focused).
