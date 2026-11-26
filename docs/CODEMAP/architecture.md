<!-- Generated: 2026-11-27 | Files scanned: 66 | Token estimate: ~1100 -->

# Architecture

## Entry Point
`init.lua` -> on `VimEnter` calls `require("vc").start()`. Run with `NVIM_APPNAME=VimClaude nvim`.

## Module Tree
```
init.lua                      entry (VimEnter -> vc.start)
lua/vc/
  init.lua                    two-screen state machine: finder <-> claude
  claude.lua                  Claude Code in a full-window terminal buffer
  transcript.lua              .jsonl -> blocks -> VC.Doc (lines, marks, folds), Claude Code layout, chunked
  markdown.lua                reply text -> clean lines + marks (tree-sitter markdown, tables, code fences)
  code.lua                    fence language -> syntax marks from tree-sitter highlight queries
  toolline.lua                tool call line, result lines, diff from structuredPatch
  debounce.lua                trailing-edge debounce (uv timer)
  theme.lua                   asks the terminal for its colors (OSC 10/11/4), blend helpers
  animate.lua                 frame-loop tween + float window animator (copied from BeastVim)
  notify/                     copy of the BeastVim notify cards: vim.notify -> stacked floats, top right
    init.lua config.lua       setup (replaces vim.notify, VimResized relayout), read-only config (width() clamps to the terminal)
    record.lua state.lua      one message (wrapped rows, 10-row cap), stack state
    stack.lua ui.lua          queue, stagger, eviction at the screen bottom, reflow; float, fade-in, slide-out
    highlights.lua            VCNotify* groups from the terminal palette
  messages/                   copy of the BeastVim messages lib: ui2 on, every msg_show -> a notify card
    init.lua config.lua       wraps ui2 msg_show; routes, passthrough kinds
    router.lua                pure: (kind, text) -> drop | card text + level | nil (ui2 keeps it)
  sessions/
    scan.lua                  one .jsonl -> row (title, cwd, recap, last message, branch, PR, last_ts, msg_count)
    cache.lua                 versioned index file under stdpath("cache")/vc
    index.lua                 walk ~/.claude/projects, reuse cache, rescan changed, cancellable
  finder/                     trimmed copy of the BeastVim finder, one source
    init.lua                  Session: open/close/set_rows/busy/relayout
    source.lua                items + item format: title, folder row, wrapped recap/last message ("New session" only on empty query)
    wrap.lua                  word wrap to byte spans (search matches map back onto rows)
    render.lua                matched -> list, footer, debounced preview
    keymaps.lua autocmds.lua  keys per pane; cursor hiding, resize, focus guard
    layout.lua highlights.lua config.lua   full-screen geometry, terminal-palette groups
    query.lua filter.lua host.lua          state holders, pipeline-to-UI contract
    pipeline/match.lua        load items once, rescore per keystroke
    matcher.lua score.lua topk.lua async.lua   fuzzy engine (copied from BeastVim)
    view.lua                  Instance base + buf/win helpers
    ui/{input,list,preview}.lua   prompt, virtual list (items of many rows, open when selected), styled preview (marks -> extmarks, folds)
test/                         headless specs (make test), harness in test/harness.lua
scripts/bench-index.lua       cold/warm index timing on synthetic store
scripts/bench-preview.lua     preview render time, first screen and longest step on a synthetic session
```

## Setup Flow
1. `vc.start` sets UI options (no statusline/tabline/cmdline, no intro) then waits up to 250 ms for the terminal's colors (`theme.refresh`). Answered: `termguicolors` on, tints blended from them, `g:terminal_color_N` set. Not answered: `termguicolors` off, palette indexes.
2. `notify.setup` (replaces `vim.notify`) and `messages.setup` (ui2 on, `msg_show` -> cards), so no message ever shows the hit-enter prompt.
3. `show_finder`: reset to one empty window, `finder.open`, `index.load` (cache rows first, then rescan).
4. Enter -> `open_item` -> `claude.run`; `on_exit` -> `show_finder` again (any exit code).
5. Esc -> cancel index load, `qa!`.

## Claude Code Integration
- Reads `~/.claude/projects/*/*.jsonl` (read-only; top-level files only).
- Spawns `sh -c 'cd "$1" && exec claude --resume "$2"'` via `jobstart{term=true}`.
- Folder gone: prints a notice, runs from Neovim's cwd. New session: `cd <cwd> && exec claude`.

## Reload / Lifecycle Contracts
- Preview cache is keyed `id:size:mtime` (a resumed session is reread) and holds the whole doc (lines, folds, marks).
- Marks are `{l, c, e, hl}` with `hl` = group name after `VCFinderPreview`; the doc is built once, theme flips only redefine groups.
- `finder.highlights` autocmd (`OptionSet background`) only redefines highlight groups, never buffers or windows.
- `notify.highlights` and `finder.highlights` both re-apply on `OptionSet background` / `FocusGained`; cards that are open keep their text and only recolor.
- `finder.autocmds.restore_cursor` runs on every close (guicursor is hidden while the list is focused).
