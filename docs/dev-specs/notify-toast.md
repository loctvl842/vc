---
name: notify-toast
description: Copy BeastVim's toast lib (one-line bottom-right line, merged repeats) into vc.toast, drop its progress feature, and make vc.notify send INFO to it while WARN and ERROR stay cards
generated: 2026-11-27
---

> PM Spec: [docs/pm-specs/notify-toast.md](../pm-specs/notify-toast.md)

# Summary
Port BeastVim's `toast` lib as `lua/vc/toast/` (no progress), with its highlights added to the existing `vc.notify.highlights` so both styles share one palette refresh. `vc.notify.notify` becomes the single dispatch point: INFO goes to the toast, WARN and ERROR to the existing card stack. Callers (`vim.notify`, the ui2 message routing) are untouched.

---

# Context

## Problem
Every message is a boxed card in the top right (`vc.notify`). Routine INFO messages need a lighter, one-line, bottom-right style with repeat merging, which VimClaude lacks.

### Solution
`vc.toast` (copied) owns a queue, a bottom-up stack of one-line floats, merging of identical visible messages (`xN`), fade in/out, and relayout on resize. `vc.notify.notify(message, level, opts)` checks the level: INFO -> `vc.toast.toast`, otherwise the card stack as today.

---

# Research

### Repo Search
- Searched for: `notify.notify`, `vim.notify`, `highlights`, `VimResized`, `relayout` across `lua/` and `test/`.
- Found: one dispatch point already exists (`lua/vc/notify/init.lua` `M.notify`); the callers are `lua/vc/init.lua:62` (`vim.notify`, WARN) and `lua/vc/messages/init.lua` (`vc.notify.notify`). `vc.notify.highlights` already derives groups from `vc.theme` and refreshes on `OptionSet background` / `FocusGained`. `vc.animate`, `vc.finder.view` (`new_buf`, `wo`, `Instance:extend`) are reusable. Existing specs in `test/notify/stack_spec.lua` use `notify.notify("...")` with the default INFO level and count floats, so they must move to WARN.
- Reuse opportunity: Yes - animate, view, theme, highlights refresh, dispatch point.

### Built-in / Existing Module Check
- Checked: BeastVim `lua/beast/libs/toast/{init,config,record,state,stack,ui,highlights}.lua` (progress.lua and its config skipped); `lua/vc/notify/*`.
- Found: the toast lib is self-contained apart from `View`, `animate`, `Theme`/`Util.colors`, `beast.apply_highlights`. Toast `ui.lua` uses `View.buf.new` / `View.win.wo`, same swap as notify. `config.normalize_message` already flattens to one line.
- Decision: **Reuse (copy)** the toast lib with `beast.*` renamed to `vc.*`; **Build** only: dispatch, shared highlights, stack cap, resize relayout.

### What is NOT copied
- `toast/progress.lua`, `toast/health.lua`, `toast/test.lua` (demo), the `progress` config block, `Update`/`dismiss_id` API (only used by progress).

---

# Architecture Changes
- New `lua/vc/toast/config.lua` - copy; drop `progress`; `timeout = 2200`, `max_width()` 60% of columns, `padding_right = 1`.
- New `lua/vc/toast/record.lua` - copy; width = min(60%, max(10, text + icon)); count badge `x2`..`x99+`; merge key = message + level + title.
- New `lua/vc/toast/state.lua` - copy as is.
- New `lua/vc/toast/stack.lua` - copy minus `update`; add: cap the stack so it never grows past the top of the screen (oldest removed early); `relayout` (re-render each view, then reflow) for `VimResized`.
- New `lua/vc/toast/ui.lua` - copy; `View.buf.new` -> `view.new_buf`, `View.win.wo` -> `view.wo`; group names `VCToast*`; drop the `segments` code path (progress only).
- New `lua/vc/toast/init.lua` - copy minus progress and meta; `setup(opts)` and `toast(message, level, opts)` (callable); `dismiss()`; `VimResized` autocmd.
- Modified `lua/vc/notify/highlights.lua` - add `VCToast{Normal,Body,TitleERROR,TitleWARN,TitleINFO,TitleDEBUG,TitleTRACE,Count}` to the same `groups()` (RGB and palette-index fallback); one refresh handles both.
- Modified `lua/vc/notify/init.lua` - `setup` also calls `require("vc.toast").setup(opts and opts.toast)`; `notify` sends INFO to `vc.toast.toast`; `dismiss` also dismisses toasts.
- Modified `test/notify/stack_spec.lua` - use WARN where cards are expected.
- New tests `test/toast/record_spec.lua`, `test/toast/stack_spec.lua`, `test/notify/dispatch_spec.lua`.
- Modified `docs/CODEMAP/*` (via `/update-codemap`).

## Implementation Phases

## Phase 1: Toast lib - copy and recolor (nothing routes to it yet)
1. **Copy toast core** (File: `lua/vc/toast/{config,record,state,stack,ui,init}.lua`)
   - Action: copy from `~/.config/BeastVim/lua/beast/libs/toast/`, rename requires to `vc.toast.*`, `vc.animate`, `vc.finder.view`; swap View helpers; remove progress, `update`, `segments`, meta, `beast.apply_highlights`.
   - Why: working one-line stack with merge, fade, stagger.
   - Depends on: None
   - Risk: Low

2. **Toast highlights** (File: `lua/vc/notify/highlights.lua`)
   - Action: add the `VCToast*` groups from the palette (Body dim, Title* level colors, Count bold yellow, Normal NONE background) with index fallback; `vc.toast.setup` only requires nothing extra.
   - Why: one palette refresh for both styles; PM rule no fixed colors.
   - Depends on: Step 1
   - Risk: Low

3. **Stack cap and resize** (File: `lua/vc/toast/stack.lua`, `init.lua`)
   - Action: when `#views` would exceed the free rows above the base row, remove the oldest; `VimResized` -> `relayout`.
   - Why: PM rules "stack past the top" and small terminal (scenario 6).
   - Depends on: Step 1
   - Risk: Medium (re-render changes width; check anchor/col after resize)

4. **Tests** (File: `test/toast/record_spec.lua`, `test/toast/stack_spec.lua`)
   - Action: record (newline flatten, width bounds 10..60%, count label x99+, key/mergeable), stack (shows at last row, merge into one view with count, different messages stack newest at bottom, stack cap, dismiss).
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 2: Dispatch - INFO to toast, WARN/ERROR stay cards
1. **Route by level** (File: `lua/vc/notify/init.lua`)
   - Action: in `notify`, after the level filter, `if level_num == vim.log.levels.INFO then return require("vc.toast").toast(message, level, opts) end`; `setup` calls `vc.toast.setup`; `dismiss` clears both.
   - Why: PM "information goes to a toast, warnings and errors to cards".
   - Depends on: Phase 1
   - Risk: Low (single dispatch; fast events are already scheduled by the callable and by the toast queue)

2. **Fix and add tests** (File: `test/notify/stack_spec.lua`, `test/notify/dispatch_spec.lua`)
   - Action: stack spec cards use WARN; dispatch spec: INFO makes a one-row float at the last row, WARN makes a card, DEBUG shows nothing, five identical INFO messages give one view with count 5, a fast-event INFO shows.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Verify and document
1. **Manual run** (File: none)
   - Action: PM scenarios 1-7 in a real terminal (tmux): search wrap while in the preview, `x` plus wrap for card and toast together, repeat, burst of different messages, 40 columns, a WARN, light/dark flip; check the toast over the finder's bottom border and after Enter into Claude Code (finder window reset must not leave a stale toast).
   - Depends on: Phase 2
   - Risk: Medium (last row overlaps the finder footer border)

2. **Codemap** (File: `docs/CODEMAP/*`)
   - Action: `/update-codemap` (toast module, dispatch).
   - Depends on: Phase 2
   - Risk: Low

# Testing Strategy
- Headless tests: `make test` (new and updated specs), `make lint`.
- Bench: n/a (not a hot path).
- Manual: PM scenarios 1-7 via `NVIM_APPNAME=VimClaude nvim` in tmux; compare screen captures for the bottom-right line, `x3` merge, ellipsis at 40 columns, WARN card.

# Success Criteria
- [x] An information message is one dim line at the bottom right, no box.
- [x] A warning or error is a card at the top right, as before.
- [x] Five identical information messages in a row show one line with "x5".
- [x] Multi-line messages show on one line; long ones end with an ellipsis.
- [x] Colored icon at the right end; follows the terminal palette in light and dark.
- [x] Toasts fade in and out and the stack closes gaps.
- [x] Typing continues uninterrupted while toasts are visible.
- [x] A 40-column terminal shows a readable, shortened toast.
- [x] A background message shows as a toast with no error.
- [x] "Press ENTER or type command to continue" still never appears.
- [x] `make test` and `make lint` pass.

---

## Completed

2026-11-27. Phase 1: `vc.toast` copied from BeastVim (no progress), stack cap and resize relayout, toast colors in the shared notify highlights. Phase 2: `vc.notify.notify` sends INFO to the toast, WARN and ERROR stay cards. Phase 3: real-terminal run, codemap.

- `8deda2e` feat(toast): add the one-line toast stack copied from BeastVim (the copied callable now schedules itself in a fast event, since building a record uses `vim.fn`)
- `ac2ce4b` feat(notify): show INFO as a toast, keep WARN and ERROR as cards
- `b3122a3` docs: update codemap for toast

Verification: `make test` 214 passed, 0 failed; `make lint` clean. Real terminal (tmux, `NVIM_APPNAME=VimClaude`): a failed search showed a WARN card top right; three identical INFO messages showed one toast "hello from toast x3" and a different message stacked below it; the nerd-font icon is in the line; the toast survived `show_finder`'s window reset and expired on time; at 40 columns a long message was cut to "This is a very long m…" and a WARN card fit.
