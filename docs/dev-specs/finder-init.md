---
name: finder-init
description: Build the session finder - a cached index of every Claude Code session, a transcript-to-markdown preview, a trimmed copy of the BeastVim finder UI, and a finder/Claude Code two-screen loop
generated: 2026-11-26
---

> PM Spec: [docs/pm-specs/finder-init.md](../pm-specs/finder-init.md)

# Summary
VimClaude is a Neovim config that only ever shows two screens: the session finder, or Claude Code in a full-window terminal. We build (1) an incremental, disk-cached index over `~/.claude/projects/*/*.jsonl`, (2) a renderer that turns a transcript into markdown for the preview, (3) a trimmed copy of BeastVim's finder (matcher, list, input, preview, layout) wired to that one source, and (4) a small state machine that launches `claude --resume <id>` and returns to the finder when the process exits.

---

# Context

## Problem
The repo holds only skill scaffolding and `STRATEGY.md`; there is no Neovim config, no session reader, and no finder. Claude Code stores each session as one `.jsonl` file under a per-project directory, with no cross-project listing and no titles beyond an `ai-title` record. Everything the PM spec shows has to be built.

### Solution
After this change `nvim` (with this config) starts directly in a full-screen finder populated from a persistent index. Enter hands the whole window to a `claude` terminal process; when it exits the finder is shown again with a refreshed list. Esc in the finder runs `:qa`. BeastVim's finder is copied and trimmed, never required at runtime.

---

# Research

### Repo Search
- Searched for: `git ls-files` and a listing of the working tree; no `docs/CODEMAP/`.
- Found: only `.claude/` skills/agents, `STRATEGY.md`, the PM spec. No Lua code. The CODEMAP step was skipped because there is no code to map; run `update-codemap` after Phase 1 lands.
- Reuse opportunity: No (nothing in this repo).

### Built-in / Existing Module Check
- Checked: Neovim 0.12.6 APIs (`vim.uv` fs + `vim.uv.new_work`/`vim.system` for off-thread scanning, `vim.json.decode`, `vim.fn.jobstart({term=true})`, `vim.fn.stdpath("cache")`, `nvim_open_win`); BeastVim finder at `~/.config/BeastVim/lua/beast/libs/finder/` (~5.6k lines: `matcher.lua`, `score.lua`, `topk.lua`, `match_hl.lua`, `layout.lua`, `render.lua`, `queue.lua`, `session.lua`, `keymaps.lua`, `ui/{input,list,preview,backdrop,hint}.lua`, plus source/chain/gh/gl/diff/live_grep index that we do NOT take); BeastVim test harness (`Makefile`, `test/helper.lua`, `test/libs/finder/*_spec.lua`); the real transcript format (`~/.claude/projects/-Users-loctvl842--config-VimClaude/*.jsonl`, 176 files / 187 MB across 25 project dirs on this machine); `claude --help`.
- Found:
  - Records are typed lines: `user`, `assistant`, `ai-title` (`aiTitle`), `last-prompt`, `system`, `attachment`, `api-request*` (large, not dialogue), etc. `user`/`assistant` records carry `cwd`, `sessionId`, `timestamp`, `isSidechain`, `message`.
  - The project directory name is a lossy path encoding, so the real folder must come from the `cwd` field.
  - `claude --resume <id>` found a session by id when launched from an unrelated directory (`/tmp`) on 2.1.311, so the missing-folder fallback is supported. This check used `-p`, which ran a real model turn and appended to the session it resumed (this session's own transcript). Re-verify the interactive case in Phase 4 using a throwaway session.
  - `--fork-session` exists but is not used: the PM spec continues the same session.
- Decision: **Build** the index, scan and transcript renderer (nothing suitable). **Reuse by copy-and-trim** BeastVim's matcher/score/topk/match_hl/layout/UI/session lifecycle. **Use** Neovim built-ins for terminal, fs, JSON, cache path.

---

# Architecture Changes

All new (repo is empty of code). Namespace `vc`.

- `init.lua` - config entry: sets options, calls `require("vc").start()` on `VimEnter`.
- `lua/vc/init.lua` - state machine: `finder` <-> `claude`; owns "only window" invariant.
- `lua/vc/sessions/scan.lua` - parse one `.jsonl` into a row `{id, path, title, project, cwd, cwd_exists, last_ts, msg_count, size, mtime}`.
- `lua/vc/sessions/index.lua` - walk `~/.claude/projects/*/*.jsonl`, reuse cached rows when `size+mtime` match, rescan the rest off the main loop, return rows sorted by `last_ts` desc.
- `lua/vc/sessions/cache.lua` - read/write the index file under `stdpath("cache")/vc/index.json` (versioned, atomic write).
- `lua/vc/transcript.lua` - `.jsonl` -> markdown lines plus a fold map, full conversation including tool calls, tool results and thinking.
- `lua/vc/finder/` - trimmed BeastVim copy: `matcher.lua`, `score.lua`, `topk.lua`, `match_hl.lua`, `layout.lua`, `render.lua`, `queue.lua`, `session.lua`, `keymaps.lua`, `highlights.lua`, `ui/{input,list,preview,backdrop,hint}.lua`, and `source.lua` (the single Claude sessions source).
- `lua/vc/claude.lua` - launch `claude` in a full-window terminal, report exit.
- `test/` + `Makefile` - headless specs using the same harness approach as BeastVim.
- `scripts/bench-index.lua` - cold/warm open timing over a synthetic large store.

## Implementation Phases

## Phase 1: Session index - Reliable metadata for every session, fast on warm start
1. **Row scanner** (File: `lua/vc/sessions/scan.lua`)
   - Action: stream a `.jsonl`, take `cwd` from the first `user`/`assistant` record, `title` from the last `ai-title` record (fallback: first user text, trimmed to one line; fallback: "(untitled)"), `last_ts` from the last timestamped record, `msg_count` = number of conversation records (`user` + `assistant`, which includes tool calls and tool results, since those are records of those types), non-sidechain, excluding bookkeeping records. This is the "full conversation" size. Tolerate bad JSON lines and empty files (an empty file is still listed).
   - Why: the row metadata is what the query matches and the user recognizes.
   - Depends on: None
   - Risk: Medium (large files; format drift - rely on named fields only, ignore unknown record types).
2. **Cache** (File: `lua/vc/sessions/cache.lua`)
   - Action: persist rows keyed by absolute path with `size`+`mtime`; versioned schema, atomic write (tmp + rename); a corrupt or old-version file is discarded and rebuilt.
   - Why: "opening stays fast however many sessions exist".
   - Depends on: Step 1
   - Risk: Low
3. **Index walk** (File: `lua/vc/sessions/index.lua`)
   - Action: list project dirs and top-level `*.jsonl` only (ignore nested subagent dirs); emit cached rows immediately, rescan changed/new files in `vim.uv` work threads or chunked, drop rows whose file vanished, sort by `last_ts` desc; compute `cwd_exists` with `uv.fs_stat`. Never writes under `~/.claude`.
   - Why: all projects, one flat list, read-only.
   - Depends on: Steps 1-2
   - Risk: Medium (thread data copying; fall back to chunked main-loop scan if `new_work` is awkward).
4. **Tests + Makefile** (Files: `Makefile`, `test/helper.lua`, `test/sessions/{scan,index,cache}_spec.lua`)
   - Action: fixtures built into a temp store: titled session, untitled, empty file, corrupt line, deleted folder, subagent subdir; assert rows, ordering, cache hit/miss, no writes to the store.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 2: Transcript renderer - Whole conversation as readable markdown
1. **Renderer** (File: `lua/vc/transcript.lua`)
   - Action: map `user` text to `## You`, `assistant` text to `## Claude`. Tool calls (`tool_use`), tool results (`tool_result`) and `thinking` blocks are NOT dropped: each consecutive run of them is emitted in full as a fenced block and recorded in a fold map `{start, end, kind, count}`. Skip only non-conversation records (`attachment`, `api-request*`, `system`, `mode`, snapshots, bookkeeping). Header line with title, folder and message count. Never truncates; yields lines in chunks so a very large transcript does not block the UI. Returns `lines, folds`.
   - Why: the preview must show the whole conversation; folds keep tool noise from burying the dialogue while leaving everything readable.
   - Fold behavior (applied by the preview in Phase 3 step 2): the preview window uses `foldmethod=expr` with a `foldexpr` reading the fold map, `foldlevel=0` so every run starts closed, and a `foldtext` showing `▸ 4 tool calls`, `▸ thinking`, or `▸ 2 tool results`. Standard fold keys (`za`, `zo`, `zc`, `zR`, `zM`) work; folds are created automatically for every run, the user never creates them.
   - Depends on: Phase 1 step 1 (shared record helpers)
   - Risk: Medium (content block shapes: string vs array; slash-command and meta user records)
2. **Tests** (File: `test/transcript_spec.lua`)
   - Action: fixtures for plain turns, tool runs, thinking, string content, array content, a 2k-turn synthetic session (last line present, no cap), sidechain records skipped; assert the fold map covers exactly the tool/thinking runs and tool text is present in the lines.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Finder UI - Trimmed BeastVim finder over the one source
1. **Copy and trim** (Files: `lua/vc/finder/*`)
   - Action: copy only the files listed under Architecture Changes; replace `beast.*` requires with `vc.finder.*`; remove `View`, chain, forge, gh, gl, diff, live_grep and level code; strip config to the keys we use. No `require("beast...")` may remain (grep gate).
   - Why: "behavior and look carried over, no dependence on BeastVim".
   - Depends on: Phases 1-2
   - Risk: High (hidden coupling to BeastVim globals; do this in small commits with tests passing at each).
2. **Sessions source** (File: `lua/vc/finder/source.lua`)
   - Action: items from the index; a synthetic first "+ New session" item present only when the query is empty; match text = title + project (never transcript text); row format as in the PM spec (title, project, relative time, message count, `(folder gone)` marker); preview via `transcript.lua`, applying its fold map (auto folds, all closed on open).
   - Depends on: Step 1
   - Risk: Medium
3. **Full-screen layout and keys** (Files: `lua/vc/finder/layout.lua`, `keymaps.lua`)
   - Action: layout fills the whole editor (no backdrop, no float margin); `<C-n>/<C-p>`/arrows, `<CR>` select, `<Esc>` -> `:qa`, empty-result Enter is a no-op, selection resets to first row on every query change, footer hints per PM spec.
   - Depends on: Step 2
   - Risk: Medium
4. **Tests** (Files: `test/finder/{source,query,keys}_spec.lua`)
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 4: Two-screen loop - Enter opens Claude Code, exit returns to the finder
1. **Claude runner** (File: `lua/vc/claude.lua`)
   - Action: Claude Code runs inside a Neovim terminal buffer, i.e. a PTY owned by this Neovim instance. Sequence on Enter:
     1. Close the finder windows and buffers so only one window remains.
     2. Create a scratch buffer, `nvim_win_set_buf(0, buf)` in that window, then `vim.fn.jobstart(cmd, { term = true, on_exit = cb })`. The terminal gets the full window size; `startinsert` puts it in terminal mode so keys go straight to Claude Code. Buffer options: `bufhidden=wipe`, no number/sign/fold columns, statusline and tabline hidden (laststatus=0, showtabline=0) so Claude Code is the only thing on screen.
     3. Resume a session: `cmd = { vim.o.shell, "-c", 'cd "$1" && exec claude --resume "$2"', "vc", row.cwd, row.id }`. This is exactly `cd <cwd> && claude --resume <id>` run in a shell, with the cwd and id passed as positional arguments (never interpolated into the string, so paths with spaces or quotes are safe). `exec` replaces the shell so Claude Code's exit ends the job directly.
     4. New session: `cmd = { vim.o.shell, "-c", 'cd "$1" && exec claude', "vc", vim.fn.getcwd() }`.
     5. Folder gone: skip the `cd` and print the notice first: `{ vim.o.shell, "-c", 'printf "%s\\n" "$1"; exec claude --resume "$2"', "vc", notice, row.id }`, started in `vim.fn.getcwd()`.
     6. `on_exit(job, code)` is scheduled onto the main loop (`vim.schedule`) and calls the state machine's `back_to_finder()` (Phase 4 step 2). A non-zero exit code or a missing `claude` binary is shown as a one-line message above the finder, not swallowed.
     7. Neovim's own working directory is never changed by this (the `cd` happens inside the child shell), so "New session" always means the directory Neovim started in.
   - Why: PM scenarios 1, 2, 5, 8; terminal-in-Neovim keeps Claude Code the only window and gives a reliable exit signal.
   - Depends on: Phase 3
   - Risk: Medium (terminal key handling; confirm the interactive missing-folder resume on a throwaway session).
2. **State machine + entry** (Files: `lua/vc/init.lua`, `init.lua`)
   - Action: `start()` opens the finder on `VimEnter`; selecting runs the runner; exit wipes the terminal buffer, closes other windows (`:only`), reopens the finder with an empty query and a refreshed index; no mapping or command opens the finder manually; startup shows no dashboard, no intro, no other buffer.
   - Why: "only two screens".
   - Depends on: Step 1
   - Risk: Medium
3. **Integration tests** (File: `test/loop_spec.lua`)
   - Action: stub `claude` with a fake executable that exits on demand; assert finder -> claude -> finder, window count is 1 at every point, refreshed ordering after return.
   - Depends on: Steps 1-2
   - Risk: Medium

## Phase 5: Performance and polish - "Opening stays fast"
1. **Bench** (File: `scripts/bench-index.lua`)
   - Action: generate 5,000 synthetic sessions (mixed sizes up to 50 MB); report cold build, warm open-to-first-paint, and incremental refresh after one new session.
   - Depends on: Phase 1
   - Risk: Low
2. **Tune** (Files: `lua/vc/sessions/*`)
   - Action: only if the bench misses the budget (warm first paint under ~100 ms at 5k sessions): bound per-file read to head/tail windows for metadata, batch cache writes.
   - Depends on: Step 1
   - Risk: Medium
3. **Pixel pass** (Files: `lua/vc/finder/highlights.lua`, `ui/*`)
   - Action: compare against the HTML mockup in `docs/pm-specs/finder-init.html` for alignment, truncation, selection bar and empty state; fix drift.
   - Depends on: Phase 3
   - Risk: Low

---

# Testing Strategy
- Headless tests: `make test` (same harness approach as BeastVim); one spec file per module above. Add a grep gate test that fails on any `require("beast` in `lua/`.
- Bench: `nvim --headless -l scripts/bench-index.lua` after touching `sessions/*`.
- Manual (PM spec scenarios): 1 find and continue, 2 new session, 3 long-session preview scrolls to the last message, 4 no match, 5 deleted folder (rename a project dir copy to simulate), 6 Esc exits, 7 start a session elsewhere then return, 8 quit Claude Code and see the finder. Verify against the real `~/.claude/projects`, and confirm `~/.claude` is unmodified (compare `find ~/.claude/projects -newer <marker>`).

# Decisions
- Ctrl-C: keep Claude Code's own quit behavior (first Ctrl-C interrupts, a second Ctrl-C or `/exit` quits). The finder returns whenever the process exits, however it exits. Agreed in review.
- Message count: the row shows the size of the full conversation (all `user` + `assistant` records, tool calls and results included). The preview shows the same full conversation. Decided in review.

# Success Criteria
- [x] Sessions from all projects in one list, newest first
- [x] "New session" first with an empty query, absent as soon as anything is typed
- [x] Typing narrows by title or project; preview follows the highlighted row
- [x] Preview of a very long session scrolls to its final message
- [x] Tool calls, results and thinking are in the preview, auto-folded and closed on open, and can be opened with standard fold keys
- [x] Enter on a session opens Claude Code, only window, in that session
- [x] Enter on "New session" opens a fresh session in the current directory
- [x] Deleted-folder session continues from the current directory with a notice
- [x] Esc exits VimClaude and changes nothing
- [x] Launch shows the finder immediately; no manual open step exists
- [x] Quitting Claude Code brings the finder back, refreshed
- [x] At no point is an editor buffer visible
- [x] The finder appears instantly with thousands of sessions (bench gate)
- [x] No action alters any session; no write under `~/.claude`
- [x] `grep -r 'require("beast' lua/` is empty; `make test` is green

---

## Completed

2026-11-26 - Phases 1-5 implemented in one pass.

Phases: 1 session index, 2 transcript renderer, 3 finder UI (BeastVim engine trimmed, view layer rewritten for two-row items and full screen), 4 two-screen loop, 5 bench and review fixes.

- `d88c44b` build: add headless spec harness and stylua config
- `8d6a608` feat(sessions): scan a transcript into a finder row
- `593c512` feat(sessions): persist the index in a versioned cache
- `ade1e05` feat(sessions): index every project with incremental rescan
- `c4b19c3` feat(transcript): render the whole conversation with foldable tool runs
- `ec73743` feat(finder): copy the match engine from BeastVim, trimmed to one source
- `46c4625` feat(finder): full-screen input, list and folding preview panes
- `d80a25c` feat(finder): sessions source, keys and finder session
- `ca9dcdb` feat(claude): run Claude Code in a full-window terminal
- `cf5f6ce` feat: finder and Claude Code two-screen loop with entry point
- `2ebad7d` fix(finder): Esc exits from the prompt, hide filler lines, pad the count
- `8325269` test(finder): expect the padded count label
- `05f3fc5` feat(sessions): show partial results while a long rescan runs
- `2ffef6f` perf(sessions): add index bench over a synthetic store
- `cb59513` fix(finder): no blank title gap in the empty preview
- `51d7e02` fix(preview): reread a resumed session and skip empty thinking folds
- `739d4d9` fix(sessions): cancel an index load when the finder is left
- `2cb5ba6` fix(finder): restore cursor on close, flush query on Enter, keep selection across refresh
- `43fcc32` refactor(finder): drop unused topk, async and highlight leftovers

Deviations from the spec:
- Tests use a small in-repo harness (`test/harness.lua`, `make test`) instead of BeastVim's downloaded Nvim harness; the finder specs are folded into `test/finder/finder_spec.lua`.
- The list view was rewritten rather than copied (sessions are two buffer rows each); matcher, score, topk, async and the match pipeline are copied and trimmed.
- Index rescans are batched on the main loop (the allowed fallback) and emit partial results every ~150 ms; a load can be cancelled.
- Esc runs `qa!` from every pane.

Verification: `make test` 41 passed, 0 failed; `make lint` clean; bench (5,005 sessions, ~200 MB): cold first paint ~190 ms, warm ~48 ms, one new session ~38 ms. End to end in tmux on the real store: finder -> resume -> Ctrl-C twice -> finder -> Esc exits. A code-review pass found 2 blocking and 4 warning issues, all fixed with regression tests. Not done: byte-bounded rescan batches for very large transcripts (a 50 MB file is still read whole in one turn).
