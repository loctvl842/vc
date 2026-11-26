---
name: cross-terminal-theme
description: Turn off 24-bit colors and define the finder highlights from the terminal's own 16-color palette, re-applied when Neovim's background flips light/dark
generated: 2026-11-26
---

> PM Spec: [docs/pm-specs/cross-terminal-theme.md](../pm-specs/cross-terminal-theme.md)

# Summary
The finder gets its colors from the terminal instead of from Neovim's built-in scheme. We switch Neovim to palette colors (`termguicolors` off), define every `VCFinder*` group with terminal palette indexes and a transparent background, and re-apply the few light/dark dependent groups when `'background'` changes. Neovim already detects the terminal's light/dark state and follows live changes, so no detection code is written.

---

# Context

## Problem
`lua/vc/finder/highlights.lua` links every `VCFinder*` group to a default-scheme group (`NormalFloat`, `Title`, `Comment`, ...). Neovim enables `termguicolors` on its own when the terminal supports 24-bit color, so those groups resolve to Neovim's fixed RGB colors: a grey background and a fixed accent set that ignore the terminal theme. Nothing in the code reacts to `'background'` changing either.

### Solution
`vc.start` sets `termguicolors` off. `highlights.lua` defines each `VCFinder*` group with `ctermfg`/`ctermbg` palette indexes (0-15) and `NONE` backgrounds, so the terminal paints its own palette and background. The groups whose right value depends on light vs dark (selected row) are computed from `vim.o.background`, and an `OptionSet background` autocmd re-applies them. Query, selection and scroll live in buffers and windows, so repainting highlights leaves them untouched.

---

# Research

### Repo Search
- Searched for: `colorscheme|background|theme|highlight|nvim_set_hl|winhl|termguicolors|OptionSet|ColorScheme` across `lua/`, `test/`, `init.lua`.
- Found: all color logic is in `lua/vc/finder/highlights.lua` (16 link groups plus `VCFinderListCursor`), called from `finder.open`. Windows consume the groups through `winhl` in `ui/input.lua`, `ui/list.lua`, `ui/preview.lua`; `autocmds.lua` uses `VCFinderListCursor` for `guicursor`. No colorscheme is loaded, nothing sets `termguicolors` or `background`, no test covers highlights.
- Reuse opportunity: Yes - keep the group names and the `highlights.setup()` entry point so no window code changes. Follow the augroup pattern in `finder/autocmds.lua`.

### Built-in / Existing Module Check
- Checked: Neovim 0.12.6 docs for `'termguicolors'`, `'background'`, `news-0.10`, `news-0.11`; `nvim_set_hl`, `OptionSet`; the `:terminal` buffer notes in `news-0.11`.
- Found: Neovim auto-enables `termguicolors` when the terminal supports it (news-0.10), so it must be set off explicitly. With it off, `cterm*` attributes are used, indexes 0-15 map to the terminal's own palette, and `NONE` keeps the terminal background. Neovim detects `'background'` from the terminal on start and updates it on theme-change notifications (DEC mode 2031, news-0.11, terminals such as Ghostty). `OptionSet background` fires on each change.
- Decision: **Use** - built-in palette colors plus the built-in background detection. **Build** only the group table and the one autocmd. No terminal queries (OSC 4/10/11) are written. See Decisions.

---

# Architecture Changes
- Modified `lua/vc/init.lua` - `set_ui_options` sets `vim.o.termguicolors = false` so palette indexes reach the terminal.
- Modified `lua/vc/finder/highlights.lua` - replace the link table with explicit cterm definitions, split into static groups and background-dependent groups, add `apply()` and the `OptionSet background` autocmd.
- New `test/finder/highlights_spec.lua` - headless checks of the group definitions and the light/dark switch.
- Modified `docs/CODEMAP/modules.md` - note that highlights are palette-based (via `/update-codemap`, not by hand edits to generated lines).

## Palette map (the contract for Phase 1)

| Role | Groups | Definition |
|---|---|---|
| Surface | `VCFinderNormal`, `VCFinderBorder`-bg | `ctermfg=NONE ctermbg=NONE` (terminal text and background) |
| Border | `VCFinderBorder` | `ctermfg=8` |
| Accent | `VCFinderInputTitle`, `PreviewTitle`, `PreviewHeading`, `Spinner`, `ListSelectionPrefix`, `PreviewYou` | `ctermfg=6` (bold for titles) |
| Match | `VCFinderListMatch` | `ctermfg=3 bold` |
| Dim | `VCFinderListDim`, `Hint` | `ctermfg=8` |
| New / Claude | `VCFinderListNew`, `PreviewClaude` | `ctermfg=2` |
| Error | `VCFinderListGone` | `ctermfg=1` |
| Selected row | `VCFinderListCursorLine` | `ctermbg=0` when background is dark, `ctermbg=7` when light |
| List cursor | `VCFinderListCursor` | unchanged (`blend=100`) |

`ListTitle` keeps the surface definition (plain text).

## Implementation Phases

## Phase 1: Palette colors - finder follows the terminal theme
1. **Turn off 24-bit color** (File: `lua/vc/init.lua`)
   - Action: add `vim.o.termguicolors = false` to `set_ui_options` with a one-line comment on why.
   - Why: with it on, Neovim ignores `cterm*` and uses fixed RGB.
   - Depends on: None
   - Risk: Medium - a `:terminal` buffer then downsamples RGB from Claude Code to 256 colors. Verified manually in Phase 3.

2. **Define groups from the palette** (File: `lua/vc/finder/highlights.lua`)
   - Action: replace the `links` table with a table of cterm specs following the Palette map; `setup()` applies them with `nvim_set_hl(0, name, { ctermfg=..., ctermbg=..., bold=..., default = true })`. Selected-row group reads `vim.o.background`.
   - Why: gives palette-based, transparent-background groups; `default = true` keeps user overrides possible.
   - Depends on: Step 1
   - Risk: Medium - palette index 8 (dim) can be invisible in themes where index 8 equals the background (some Solarized variants). Checked manually on Monokai Pro and a light theme.

3. **Unit specs** (File: `test/finder/highlights_spec.lua`)
   - Action: after `highlights.setup()`, assert `VCFinderNormal` has no `ctermbg`, accent group has `ctermfg == 6`, selected row has `ctermbg == 0` for `background=dark`, and no group is a link to a default-scheme group.
   - Why: locks the "terminal owns the colors" rule.
   - Depends on: Step 2
   - Risk: Low

## Phase 2: Live light/dark
1. **Re-apply on background change** (File: `lua/vc/finder/highlights.lua`)
   - Action: in `setup()`, create augroup `VCFinderHighlights` (clear = true) with `OptionSet` pattern `background` calling `apply()`. `apply()` is the same function `setup()` uses and only sets highlight groups.
   - Why: PM scenarios 3 and 5 - repaint in place when Neovim learns the terminal flipped. No buffer or window is touched, so query, selection and scroll survive.
   - Depends on: Phase 1
   - Risk: Low

2. **Spec for the switch** (File: `test/finder/highlights_spec.lua`)
   - Action: open the finder, type a query, set `vim.o.background = "light"`, assert selected-row `ctermbg == 7`, then assert query text and selection index are unchanged. Assert the default (nothing reported) is the dark variant.
   - Why: covers success criteria on persistence and default.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Verify in real terminals and document
1. **Manual run** (no file)
   - Action: run PM scenarios 1-6 in Ghostty (Monokai Pro and a light theme), inside tmux, and with `TERM=xterm` for the 16-color case. Compare Claude Code rendering (colors, syntax in diffs) before and after in a `:terminal` buffer.
   - Why: color fidelity cannot be asserted headless.
   - Depends on: Phase 2
   - Risk: Medium - if dim text, selected row or Claude Code colors are unacceptable, switch to the fallback in Decisions before merging.

2. **Codemap** (File: `docs/CODEMAP/`)
   - Action: run `/update-codemap` after the change.
   - Why: highlights and the `termguicolors` setting are architecture facts.
   - Depends on: Step 1 of this phase
   - Risk: Low

---

# Decisions for you

| Option | What it is | Trade-off |
|---|---|---|
| **A. Terminal palette (recommended)** | `termguicolors` off, cterm indexes 0-15, transparent background | Simple and robust; palette changes follow with no code; no OSC queries. The selected row and dim text use palette slots, not a computed tint, so a few themes look less subtle. Claude Code RGB colors are downsampled to 256 colors. |
| B. Query the terminal | Keep `termguicolors`, read palette and bg/fg with OSC 4/10/11, compute tint and dim by blending, set `g:terminal_color_N` | Exact tints and exact Claude Code colors; needs async queries, a timeout, tmux passthrough care and a fallback to A anyway. |

Phase 3 decides: if A passes the manual checks, B is not built. If dim text or Claude Code colors fail, B becomes a follow-up dev spec; Phases 1-2 stay valid as its fallback path.

---

# Testing Strategy
- Headless tests: `make test` (all specs) and `make test SPEC=test/finder/highlights_spec.lua`. Existing finder specs must still pass. `make lint` for stylua.
- Bench: n/a (no hot path touched).
- Manual: PM scenarios 1-6 as in Phase 3. Scenario 3 is checked by flipping the terminal's light/dark in Ghostty with the finder open; scenario 5 by running without a terminal that reports its theme (plain `TERM=xterm` inside tmux without focus events).

# Success Criteria
- [x] In a dark themed terminal the finder background is indistinguishable from the terminal background.
- [x] In a light themed terminal all text, hints and the selected row are clearly readable.
- [x] Two terminals with different themes show visibly different finder colors, each matching its own terminal.
- [x] Changing the terminal theme or light/dark mode with the finder open repaints it without losing query, selection or scroll.
- [x] After quitting Claude Code following a theme change, the finder shows the new theme.
- [x] No theme setting, install step or restart is needed.
- [x] When the terminal does not report light/dark, the finder opens dark and readable with no error.
- [x] Matched letters, selected row, dim text and error red stay distinguishable from normal text in every theme tested.
- [x] `make test` and `make lint` pass; no `VCFinder*` group links to a default-scheme group.
- [ ] Claude Code inside the terminal buffer shows no visible color regression versus before.

---

## Completed

2026-11-26 - Phases 1 and 2 done; Phase 3 automated and tmux checks done, hand checks listed below remain.

- `395f64d` feat(theme): use the terminal palette instead of 24-bit colors
- `2389f5c` feat(theme): define finder highlights from the terminal palette
- `c75ec23` feat(theme): repaint the selected row when the background flips

Verification: `make test` 47 passed, 0 failed; `make lint` clean. Real Neovim in tmux emits only palette codes (90, 36, 32, 40; no RGB), and `background=light` moves the selected row from 40 to 47.

Not verified here (needs a human in a real terminal): flipping Ghostty light/dark live, a light theme's readability, Claude Code colors in the terminal buffer after the 256-color downsampling, and dim text on themes where palette slot 8 equals the background. If any fail, option B in Decisions becomes a follow-up spec.

### Follow-up: option B built (Phase 3 manual check failed)
Screenshot review showed dim text almost invisible on Monokai Pro (palette slot 8 close to the background) and a weak selected-row tint, so option B was built.
- `cff0990` feat(theme): blend finder colors from the terminal's real palette (new `lua/vc/theme.lua`; `highlights.lua` blends dim, border, selected row and match tints from the terminal's fg/bg/palette, sets `g:terminal_color_N`, falls back to the cterm palette when the terminal does not answer)
- Verification: `make test` 56 passed; a fake terminal in a pty answered all 18 OSC queries and the finder drew Monokai Pro yellow/green, a blended dim and a bg tint as 24-bit colors.
