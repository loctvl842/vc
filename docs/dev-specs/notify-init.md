---
name: notify-init
description: Copy BeastVim's notify card stack and its ui2 message routing into VimClaude, adapt colors to the terminal palette, add wrapping, narrow-terminal fit and overflow trimming, and route every message to a card
generated: 2026-11-27
---

> PM Spec: [docs/pm-specs/notify-init.md](../pm-specs/notify-init.md)

# Summary
Port two BeastVim libs almost verbatim: `notify` (stacked, animated floating cards, replaces `vim.notify`) and `messages` (enables Neovim's ui2 and intercepts every `msg_show`). The copies are re-namespaced to `vc.*`, recolored from `vc.theme` like the finder, and changed in only four places the PM spec requires: wrap long lines, fit narrow terminals, trim overflow, and send every message (not just a few kinds) to a card.

---

# Context

## Problem
`cmdheight` is 0 and nothing handles messages, so Neovim shows its default hit-enter prompt for `E21` and friends and blocks input. There is no card UI in VimClaude: only `vim.notify` calls from `vc.init` (which fall back to the same blocking message line).

### Solution
After this change `vim.notify` is replaced by a card stack (`lua/vc/notify/`), ui2 is enabled and its `msg_show` handler is wrapped so every message is turned into a card (`lua/vc/messages/`), and the card colors come from the terminal palette. Prompts that need an answer (confirm, return prompts) still go through ui2 untouched.

---

# Research

### Repo Search
- Searched for: `vim.notify`, `cmdheight`, `msg_show`, `ui2`, `zindex`, `animate`, `defer_fn` across `lua/`, `test/`.
- Found: one `vim.notify` caller (`lua/vc/init.lua:62`), `cmdheight = 0` set at `lua/vc/init.lua:74`. No message routing, no animation helper. `lua/vc/finder/view.lua` already is BeastVim's `View` (Instance, `extend`, `new_buf`, `wo`). `lua/vc/finder/wrap.lua` gives byte-span word wrapping. `lua/vc/theme.lua` has `palette`, `mix`, `hex`, `activate`, `refresh`. Finder floats use zindex 101-103.
- Reuse opportunity: Yes - `vc.finder.view`, `vc.finder.wrap`, `vc.theme`, the `VCFinderHighlights` refresh pattern (`finder/highlights.lua`).

### Built-in / Existing Module Check
- Checked: BeastVim `lua/beast/libs/notify/{init,config,record,state,stack,ui,highlights}.lua`, `libs/messages/{init,config,router,highlights}.lua`, `libs/animate.lua`, `libs/view`; Neovim 0.12.6 `vim._core.ui2` (`enable`, `messages.msg_show`); BeastVim `test/libs/messages/router_spec.lua`.
- Found: BeastVim's two libs already do exactly this. Only dependencies outside them: `View` (already in VC), `animate` (copy), `Theme`/`Util.colors` (replace with `vc.theme`), `Toast` (replace with notify), `Beast.Lib.Meta` annotations and `beast.apply_highlights` (drop).
- Decision: **Reuse (copy)** - copy files, rename `beast.libs.*` to `vc.*`, drop BeastVim-only glue. **Build** only the four PM-required changes below. ui2 is experimental, so the wrapper keeps BeastVim's "fall back to ui2 on any error" guard.

### What is NOT copied
- `notify/health.lua`, `notify/test.lua` (demo), `messages/health.lua`, `libs/review/notify.lua` (unrelated).
- `messages` Toast titles and the `spill` first-line-only rule (PM spec wants up to 10 lines, level word as title).

---

# Architecture Changes
- New `lua/vc/animate.lua` - copy of `beast/libs/animate.lua` (tween + float animator), meta annotation removed.
- New `lua/vc/notify/init.lua` - copy; `vim.notify = M.notify`, fast-event scheduling, level filter. Drop `beast.apply_highlights`; call `highlights.setup()`.
- New `lua/vc/notify/config.lua` - copy; add `margin` and clamp helper `width()` = `min(80, columns - 2)`.
- New `lua/vc/notify/record.lua` - copy; `dimensions(width)` uses wrapped line count capped at 10; message lines wrapped with `vc.finder.wrap.lines` (CHANGE 1, wrap).
- New `lua/vc/notify/state.lua` - copy as is.
- New `lua/vc/notify/stack.lua` - copy; `show` evicts oldest cards when the stack would pass the screen bottom (CHANGE 3); `reflow` also runs on `VimResized`.
- New `lua/vc/notify/ui.lua` - copy; `View.buf.new` -> `view.new_buf`, `View.win.wo` -> `view.wo`; `wrap = false` kept because lines are pre-wrapped; width from `config.width()` (CHANGE 2, narrow fit); `final_col` uses the clamped width.
- New `lua/vc/notify/highlights.lua` - NOT a copy: groups `VCNotifyNormal/Border/ERROR/WARN/INFO/DEBUG/TRACE` from `vc.theme` (palette slots red/yellow/blue, `mix` for surface), terminal-index fallback when no palette; re-applied on `OptionSet background` and `FocusGained` like `finder/highlights.lua`.
- New `lua/vc/messages/init.lua` - copy; wrapper calls `vc.notify.notify` instead of `Toast`; unmatched kinds become INFO cards (CHANGE 4) except pass-through prompt kinds.
- New `lua/vc/messages/config.lua` - copy; routes without titles; add `passthrough = { "confirm", "confirm_sub", "return_prompt", "number_prompt" }` and drop empty messages.
- New `lua/vc/messages/router.lua` - copy; remove `spill`, default route returns INFO for unmatched kinds, `drop` for empty text.
- Modified `lua/vc/init.lua` - `start()` calls `require("vc.notify").setup()` and `require("vc.messages").setup()` after `set_ui_options()` and before `show_finder()`.
- New tests `test/notify/record_spec.lua`, `test/notify/stack_spec.lua`, `test/messages/router_spec.lua` (port of BeastVim's, on `test/harness.lua`).
- Modified `docs/CODEMAP/*` (via `/update-codemap`).

## Implementation Phases

## Phase 1: Notify cards - `vim.notify` shows stacked cards
1. **Copy animate** (File: `lua/vc/animate.lua`)
   - Action: copy `~/.config/BeastVim/lua/beast/libs/animate.lua`; remove `Beast.Lib.Meta` line.
   - Why: tween for fade/slide, no VC equivalent.
   - Depends on: None
   - Risk: Low

2. **Copy notify core** (File: `lua/vc/notify/{config,state,record,stack,ui,init}.lua`)
   - Action: copy; rename requires to `vc.notify.*`, `vc.animate`, `vc.finder.view`; swap `View.buf.new`/`View.win.wo` for `new_buf`/`wo`; remove `Beast.*` annotations and `beast.apply_highlights`.
   - Why: working card stack with queue, stagger, fade-in, slide-out, reflow.
   - Depends on: Step 1
   - Risk: Low

3. **Terminal-palette highlights** (File: `lua/vc/notify/highlights.lua`)
   - Action: write groups from `theme.palette` (ERROR red slot 1, WARN yellow 3, INFO blue 4; card bg `mix(bg, fg, 0.08)`, border `mix(bg, fg, 0.3)`), index fallback; `setup()` applies and registers `OptionSet background` + `FocusGained` -> `theme.refresh(apply)`.
   - Why: PM rule "colors follow the terminal palette, no fixed values".
   - Depends on: Step 2
   - Risk: Medium (two refresh autocmds, finder's and notify's, both query the terminal; harmless but verify no flicker)

4. **Wrap, narrow fit, overflow** (File: `lua/vc/notify/record.lua`, `ui.lua`, `stack.lua`, `config.lua`)
   - Action: wrap message lines to card width with `vc.finder.wrap`; cap at 10 lines; width = `min(80, columns - 2)`; before showing, remove oldest cards until the new card fits above `vim.o.lines`; reflow on `VimResized`.
   - Why: PM scenarios 4, 5 and State 3, 4.
   - Depends on: Step 2
   - Risk: Medium (wrap bytes vs display width for wide/CJK text; use `strdisplaywidth` when slicing)

5. **Wire into start** (File: `lua/vc/init.lua`)
   - Action: call `require("vc.notify").setup()` in `M.start` after `set_ui_options()`.
   - Why: replace `vim.notify` before the finder opens.
   - Depends on: Steps 2-3
   - Risk: Low

6. **Tests** (File: `test/notify/record_spec.lua`, `test/notify/stack_spec.lua`)
   - Action: record (string split, wrap, 10-line cap, level normalize), stack slots/overflow eviction, level filter, fast-event scheduling.
   - Depends on: Step 4
   - Risk: Low

## Phase 2: Message capture - every message becomes a card
1. **Copy messages** (File: `lua/vc/messages/{init,config,router}.lua`)
   - Action: copy; rename requires; replace `Toast(...)` with `require("vc.notify").notify(text, level)`; remove titles; remove `spill`.
   - Why: ui2 interception is the part that kills the hit-enter prompt.
   - Depends on: Phase 1
   - Risk: Medium (ui2 is experimental; keep the pcall fallback)

2. **Catch-all routing** (File: `lua/vc/messages/router.lua`, `config.lua`)
   - Action: after the explicit routes, any non-empty message of a non-pass-through kind resolves to INFO; kinds `emsg echoerr lua_error rpc_error` ERROR, `wmsg` WARN; `search_count` and empty text dropped; `confirm`, `confirm_sub`, `return_prompt`, `number_prompt` return nil (ui2 handles).
   - Why: PM "every message goes to a card", rule 1 and scenario 6.
   - Depends on: Step 1
   - Risk: Medium (a kind missing from pass-through could swallow a prompt; verify with `:s/x/y/c`)

3. **Wire into start** (File: `lua/vc/init.lua`)
   - Action: `require("vc.messages").setup()` after `notify.setup()`.
   - Depends on: Steps 1-2
   - Risk: Low

4. **Tests** (File: `test/messages/router_spec.lua`)
   - Action: port BeastVim `router_spec.lua` to `test/harness.lua` (flatten, E486 pattern, search wrap, drop count) plus catch-all INFO, pass-through nil, empty drop.
   - Depends on: Step 2
   - Risk: Low

## Phase 3: Verify and document
1. **Manual run** (File: none)
   - Action: run PM scenarios 1-6 in a real terminal (see Testing Strategy); check Claude Code screen and `silent! only` in `reset_window` do not leave stale cards or lose them.
   - Depends on: Phase 2
   - Risk: Medium (`reset_window` may close or orphan float windows)

2. **Codemap** (File: `docs/CODEMAP/*`)
   - Action: run `/update-codemap` (notify, messages, animate modules).
   - Depends on: Step 1
   - Risk: Low

# Testing Strategy
- Headless tests: `make test` (new specs above); `make lint` (stylua).
- Bench: n/a (not on a hot path; cards run only on messages).
- Manual: open `NVIM_APPNAME=VimClaude nvim`. PM scenario 1: move into preview, press `x`, expect E21 card, no "Press ENTER". Scenario 2: `:lua vim.notify("a"); vim.notify("b", 2)`. Scenario 3: open a session, `:lua vim.notify("hi", 2)` from another way (e.g. `nvim --remote-expr`) while Claude Code is shown. Scenario 4: press `x` five times quickly, and a tall stack with `:lua for i=1,40 do vim.notify("m"..i) end`. Scenario 5: resize to 40 columns. Scenario 6: `/zzz`, `n` for wrap/not found, an empty `:echo ""`. Check light/dark flip recolors cards, and `:s/x/y/c` still prompts.

# Success Criteria
- [ ] Pressing an editing key in the read-only preview shows the E21 text as a card in the top right.
- [ ] "Press ENTER or type command to continue" never appears, in the finder or in Claude Code.
- [ ] The finder is never pushed or covered by message text.
- [ ] Typing continues uninterrupted while a card is visible.
- [ ] Cards are colored by level from the terminal palette in light and dark.
- [ ] Several messages stack without overlapping and close the gap when one leaves.
- [ ] Messages longer than 10 lines are cut at 10.
- [ ] A 40-column terminal shows a readable card (38 wide, wrapped).
- [ ] A background (fast-event) message shows as a card with no error.
- [ ] Confirm prompts (`:s///c`, `:q` with changes) still work.
- [ ] `make test` and `make lint` pass.
