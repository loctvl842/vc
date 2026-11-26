---
name: finder-list-item
description: Show each session's full folder, recap and last user message in the finder list - word-wrapped, folded when unselected, searchable - on top of new scanner fields (last message, branch, PR)
generated: 2026-11-26
---

> PM Spec: [docs/pm-specs/finder-list-item.md](../pm-specs/finder-list-item.md)

# Summary
The scanner learns three more things about a session (its last real user message in full, its last git branch, its PR number) and keeps the recap it already reads. The list renders each session as title / folder row / recap / last message, word-wrapped to the list width, folded to 3 lines per message unless selected. The matcher is unchanged: title and folder stay fuzzy, and recap plus last message are one substring-only region of the item's search text (the `fuzzy_len` mechanism already committed in `80d10ee`).

---

# Context

## Problem
`scan.parse` returns title, project, cwd, counts and (since `80d10ee`) a recap, but not what the user last said, the branch, or the PR. `source.format` returns a fixed two or three rows per item and truncates with "…"; the list (`ui/list.lua`) calls `format_fn(item, width)` with no notion of selection, so an item cannot be taller when selected. Claude Code's own `last-prompt` record cannot supply the last message: it is cut at about 200 characters.

### Solution
After this change a row carries `last_prompt`, `branch` and `pr`. `source.format(item, width, opts)` takes `opts.selected` and `opts.max_rows`, builds rows from a new `wrap` module that returns byte spans (so search highlights map back onto wrapped lines), and the list passes the cursor into every height calculation. Search highlighting, the "match is never hidden" rule and the fold/open behaviour all live in `format`, which stays a pure function.

---

# Research

### Repo Search
- Searched for: `last-prompt|lastPrompt|pr-link|gitBranch|isCompactSummary` in `lua/` and `test/`; `strdisplaywidth|strcharpart` helpers; every caller of `format_fn` / `_row_to_item` / `item_at_row`; `fuzzy_len` and `score_term` in the matcher.
- Found: no code reads `last-prompt`, `pr-link`, `gitBranch` or `isCompactSummary`. `source.fit` (cut head/tail by display width) exists and is reused for title and folder. The list's `height_of`, `last_visible`, `offset_for_cursor` and `render_visible` all call `view._format_fn(item, width)`; `autocmds.lua` maps mouse rows through `item_at_row`. The matcher already scores `item.text` fuzzily up to `fuzzy_len` and as a plain substring after it.
- Reuse opportunity: Yes - `source.fit`, `source.location`, `fuzzy_len`, the `right_align` chunk, the `ranges` mechanism (`row`, `s`, `e`).

### Built-in / Existing Module Check
- Checked: Neovim string APIs (`vim.fn.strdisplaywidth`, `strcharpart`, `vim.str_utf_pos`, `vim.str_byteindex`); the `wrap`/`linebreak`/`breakindent` window options; `nvim_win_text_height`; real transcripts (105 sessions on this machine).
- Found:
  - **`lastPrompt` is truncated.** 95 sessions have it; the longest is 201 characters, 10 are at the cap. It is also not reliably a "real" message (`/compact` appeared as one). It cannot be the source for "full message".
  - `pr-link` records are `{type, prNumber, prUrl, prRepository, timestamp}` (9 of 105 sessions). `gitBranch` is on user/assistant records; values seen: `main`, `HEAD` (22 sessions), feature branches; 14 sessions changed branch mid-session.
  - Compaction leaves a user-role record with `isCompactSummary:true` carrying a long summary; interrupted turns leave `[Request interrupted by user]`. Neither is something the user wrote.
  - A slash command is stored as a user message `<command-message>..</command-message><command-name>/x</command-name><command-args>ARGS</command-args>`; `scan.user_text` strips tag blocks, so a skill invocation with arguments currently yields nothing.
  - Neovim has no string word-wrap API (`gq`/`textwidth` work on buffers). Letting the window wrap (`wrap` + `breakindent`) would avoid our own wrap but the list scrolls in virtual item rows we compute ourselves, and the 3-line fold and match-extension rules need exact line counts, so we would end up wrapping to count anyway.
- Decision: **Reuse** `fit`, `location`, `fuzzy_len`, `ranges`. **Build** `wrap.lua` (small, pure, testable; returns byte spans). **Build** the new scanner fields in `scan.parse`. **Rejected**: window-level wrapping; `lastPrompt` as the source.

---

# Architecture Changes
- `lua/vc/sessions/scan.lua` (modified) - keep the last real user message, last branch, latest PR number; raise the recap cap; accept `<command-args>` text as a message.
- `lua/vc/sessions/cache.lua` (modified) - `VERSION` 2 -> 3 so cached rows are rescanned once.
- `lua/vc/finder/wrap.lua` (new) - word-wrap by display width, returning byte spans.
- `lua/vc/finder/source.lua` (modified) - `format(item, width, opts)` rewrite (rows, chips, fold, match extension, ranges); `items` builds the search text with both prose fields.
- `lua/vc/finder/ui/list.lua` (modified) - `FormatFn` gets `opts`; heights depend on the cursor; one item is capped at the window height.
- `lua/vc/finder/highlights.lua` (modified) - `VCFinderListLabel`, `VCFinderListPrompt`; `VCFinderListRecap` kept.
- `lua/vc/finder/matcher.lua`, `query.lua` (unchanged) - `fuzzy_len` already covers both prose fields.
- `test/finder/wrap_spec.lua` (new); `test/sessions/scan_spec.lua`, `test/sessions/fixtures.lua`, `test/finder/finder_spec.lua`, `test/finder/highlights_spec.lua` (modified).
- `docs/CODEMAP/` (regenerated at the end via `update-codemap`).

## Decisions and PM spec gaps (flagged, not silently assumed)

1. **"Full" has a ceiling: 2000 characters per message.** A pasted stack trace is not useful in a list and every stored character is cached on disk for every session. Text over the ceiling is stored cut and ends with "…". Realistic prompts and recaps are well below it (median last prompt 69 characters).
2. **A command with arguments is a message.** `/pm-spec Now I want...` counts, and the shown text is the arguments. A command with no arguments (`/recap`, `/clear`, `/compact`) does not. This reads the PM spec's "only a command" literally; without it, sessions driven by skills would show an older message.
3. **Not messages the user wrote:** compaction summaries (`isCompactSummary`), `[Request interrupted by user]`, tool results, meta records.
4. **"Identical to the title" is checked after the 120-character title cut:** when the title is an untitled session's first prompt, a one-message session would otherwise show it twice.
5. **The blank separator row is part of the item** and sits inside the selected row's highlight, which reads as padding. The mouse maps it to its session.
6. **Match extension uses the first match of that message.** With several typed words, the message extends to the line holding its earliest match, not to every match. Matches already within 3 lines need nothing.

---

## Implementation Phases

## Phase 1: Scanner data - last message, branch, PR (no UI change)
Goal: rows carry what the list needs; nothing visible changes. Mergeable alone.

1. **Message extraction helper** (File: `lua/vc/sessions/scan.lua`)
   - Action: add `MAX_MESSAGE = 2000`. Extend `user_text` to return the text of `<command-args>` when the message is a command with non-empty args (after stripping the other tags), and cut with `MAX_MESSAGE` and a trailing "…" when longer. Keep the 120-character title cut separate (title = first prompt cut to `MAX_TITLE`).
   - Why: one place decides what counts as a message, for title and last message alike.
   - Depends on: None
   - Risk: Medium (changes the title fallback for sessions whose first message is a command with arguments; add a test for it)
2. **Track the last real user message** (File: `lua/vc/sessions/scan.lua`)
   - Action: in `parse`, for user lines that pass the existing filters, skip lines containing `"isCompactSummary":true`, and remember (up to the last 5) the candidate lines whose content is not a `tool_result` (plain find, no decode). After the loop, decode candidates newest first and take the first that yields text and does not start with `[Request interrupted`. Store as `last_prompt`; drop it when it equals the title's source text after the 120-character cut.
   - Why: decoding every user line would break the scanner's "few JSON decodes" performance contract; five candidates are enough because most trailing user lines are real prompts.
   - Depends on: Step 1
   - Risk: Medium (performance; verified with the bench in Phase 4)
3. **Branch and PR** (File: `lua/vc/sessions/scan.lua`)
   - Action: `branch` = `gitBranch` of the last counted user/assistant line (matched once after the loop, not per line); nil when empty or `HEAD`. `pr` = `prNumber` of the last `pr-link` line (plain find `"type":"pr-link"`, decode only that line).
   - Why: the chips in the PM spec.
   - Depends on: None
   - Risk: Low
4. **Raise the recap cap and add the new fields to the row** (File: `lua/vc/sessions/scan.lua`)
   - Action: `MAX_RECAP` becomes `MAX_MESSAGE`; add `last_prompt`, `branch`, `pr` to `VC.Row` and its doc comment.
   - Why: "full text" for the recap too.
   - Depends on: Steps 1-3
   - Risk: Low
5. **Invalidate the cache** (File: `lua/vc/sessions/cache.lua`)
   - Action: `VERSION = 3`.
   - Why: existing cached rows lack the new fields.
   - Depends on: None
   - Risk: Low (one full rescan on first launch)
6. **Tests** (Files: `test/sessions/fixtures.lua`, `test/sessions/scan_spec.lua`)
   - Action: fixtures for a command with args, a bare `/clear`, a compact summary, an interrupted turn, a `pr-link`, a branch change mid-session and a `HEAD` branch. Specs: last message is the latest real one; command args count; bare commands, compaction summaries and interruptions do not; text over 2000 characters ends with "…"; branch is the last non-`HEAD`; PR is the latest; `last_prompt` is nil when it equals the title.
   - Why: the rules in the PM spec's Behavior Rules.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 2: Wrapped, folded rows in the list
Goal: the list shows title / folder row / recap / last message in the PM spec's layout, folded unless selected. Mergeable alone (search highlight on the prose rows comes in Phase 3).

1. **Wrap module** (File: `lua/vc/finder/wrap.lua`, new)
   - Action: `wrap.lines(text, width) -> { {s: integer, e: integer}, ... }` (1-based inclusive byte spans). Break at single spaces (the space belongs to no span); a word wider than `width` display columns is split at a character boundary; never split a UTF-8 character; width measured with `vim.fn.strdisplaywidth`; empty text -> no lines. Messages are already whitespace-collapsed by the scanner.
   - Why: spans (not rewritten strings) let Phase 3 map search positions back to lines and columns.
   - Depends on: None
   - Risk: Medium (display width of wide characters; covered by tests)
2. **Rewrite `format`** (File: `lua/vc/finder/source.lua`)
   - Action: `M.format(item, width, opts)` with `opts = { selected: boolean, max_rows: integer? }`. Rows, in order: title (`fit`, head); folder row (`fit` tail on the folder, then ` · branch`, ` · #pr`, ` (folder gone)`, stats right-aligned, as today); recap rows (label chunk `"Recap › "` in `VCFinderListLabel`, text in `VCFinderListRecap`, continuation rows indented by the label's width); last-message rows (`"You   › "`, text in `VCFinderListPrompt`); one trailing blank row. Text width = `width - 12` (gutter 2, indent 2, label 8), at least 10. Unselected: each message shows at most 3 lines, the last ending in "…". Selected: all lines. `max_rows` cuts the item and ends its last row with "…". No recap / no last message: those rows are absent (two-row item). The "New session" item stays one row (plus the blank row).
   - Why: the Target Behavior and Behavior Rules of the PM spec.
   - Depends on: Phase 1, Step 1
   - Risk: Medium
3. **Selection- and height-aware list** (File: `lua/vc/finder/ui/list.lua`)
   - Action: `FormatFn` becomes `fun(item, width, opts)`. `height_of`, `render_visible` pass `{ selected = idx == view.cursor, max_rows = view._win_height }`. `last_visible` and `offset_for_cursor` keep using `height_of`, so the open item's height is used wherever the cursor is. No other change: rows, `_row_to_item`, extmarks and `right_align` work per row as today.
   - Why: the selected item's height depends on the cursor; `clamp_offset` must see that height or the selected item can run past the window bottom.
   - Depends on: Step 2
   - Risk: Medium (scrolling; covered by tests that move the cursor through tall items)
4. **Highlights** (File: `lua/vc/finder/highlights.lua`)
   - Action: add `ListLabel` (dim) and `ListPrompt` (normal foreground); keep `ListRecap`, dropping italic if it reads poorly next to the prompt. Same fallbacks as the other groups (palette indexes when the theme is unknown).
   - Why: label, recap and message must be told apart without relying on position.
   - Depends on: None
   - Risk: Low
5. **Tests** (Files: `test/finder/wrap_spec.lua` (new), `test/finder/finder_spec.lua`, `test/finder/highlights_spec.lua`)
   - Action: wrap: exact fit, long word split, UTF-8 and wide characters, empty text. Finder: a session with recap and message renders four rows plus a blank; unselected long message ends with "…" at 3 lines; selected shows all lines; moving the cursor re-folds the previous item; an item taller than the window is cut with "…"; a session with neither renders two rows; the folder shows in full with `~`; narrow width keeps the end of the folder; branch and PR chips present/absent; the new highlight groups exist.
   - Why: scenarios 1, 2, 5, 6, 7, 8.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 3: Search the prose and highlight matches
Goal: recap and last message are searchable (substring only) and matches are highlighted and never hidden. Mergeable alone.

1. **Search text** (File: `lua/vc/finder/source.lua`)
   - Action: `items` builds `text = title .. "  " .. location [.. "  " .. recap] [.. "  " .. last_prompt]` and `fuzzy_len = #title + 2 + #location`. Remember each field's start offset on the item (`item._recap_at`, `item._prompt_at`) so `format` can map positions.
   - Why: one substring-only region for both prose fields reuses the matcher as is; typed words contain no spaces, so a match cannot straddle the field separator.
   - Depends on: Phase 1
   - Risk: Low
2. **Map positions onto wrapped rows** (File: `lua/vc/finder/source.lua`)
   - Action: for each `item.positions` entry past `fuzzy_len`, find the field (recap or last message), then the wrap span containing `p - field_start + 1`, and emit a range `{row, s, e}` in bytes (label prefix included); merge consecutive bytes into one range per row. Title and folder mapping stays as in `80d10ee` (folder rows with a cut-off head still skip hidden bytes).
   - Why: highlights on wrapped lines, including a match that spans a wrap point.
   - Depends on: Step 1, Phase 2
   - Risk: Medium (off-by-one in byte math; tests assert the highlighted substring)
3. **Never hide a match** (File: `lua/vc/finder/source.lua`)
   - Action: for an unselected item, if the earliest position inside a message lies beyond the 3rd line, show lines up to and including that line (limited by `max_rows`); lines hidden before it are not elided (the message is shown from its first line).
   - Why: Scenario 3, step 2.
   - Depends on: Step 2
   - Risk: Low
4. **Tests** (Files: `test/finder/finder_spec.lua`)
   - Action: query on a word only in the last message finds the session, highlights it, and the highlighted text equals the query; the same for the recap; scattered letters do not match; a match in line 5 of an unselected message shows through line 5; two typed words (title + message) both highlight; `'exact` terms keep working; the existing "recap fuzzy flood" test stays.
   - Why: Scenarios 3, 4, 7.
   - Depends on: Steps 1-3
   - Risk: Low

## Phase 4: Verify on real data and document
Goal: the numbers and the look hold up on the real store. Not code-heavy.

1. **Scanner bench** (File: `scripts/bench-index.lua`)
   - Action: run against the real store before and after Phase 1; the full rescan time must stay in the same range as before (the bench prints the number). If decoding candidates is slow, lower the candidate count.
   - Why: the scanner's cheapness is a design constraint.
   - Depends on: Phase 1
   - Risk: Medium
2. **Manual scenarios** (see Testing Strategy)
   - Action: open the finder in a real terminal; walk PM spec scenarios 1-8 on the author's sessions; check light/dark, a narrow window and the selected row's highlight over the blank separator row.
   - Why: the project rule is pixel-level checking of the real UI.
   - Depends on: Phases 1-3
   - Risk: Low
3. **Codemap** (Files: `docs/CODEMAP/*`)
   - Action: run `update-codemap`.
   - Why: new module `wrap`, new row fields, new `format` signature.
   - Depends on: Phases 1-3
   - Risk: Low

---

# Testing Strategy
- Headless tests: `make test` (all) and `make test SPEC=test/sessions/scan_spec.lua`, `test/finder/wrap_spec.lua`, `test/finder/finder_spec.lua`, `test/finder/highlights_spec.lua`; `make lint` (stylua). Baseline is 64 passing.
- Bench: `nvim --headless -u NONE -l scripts/bench-index.lua` before and after Phase 1 (hot path: `scan.parse`).
- Manual: open the finder (`nvim` in this repo) and run PM spec scenarios 1-8: pick by where it left off; long messages open on selection; find by something said ("Dana"-style query); recap search exact, never loose; a session with nothing of its own; narrow list; two same-named folders; folder gone. Compare against STATE 1-6 in the PM spec.

# Success Criteria
- [x] Every session shows its full folder with the home folder as ~
- [x] Two folders with the same name can be told apart in the list
- [x] A session with a recap shows it in full; one without shows no recap line
- [x] Each session shows the last real message the user wrote, in full (up to 2000 characters)
- [x] A command-only message (/recap, /clear, /compact) is never shown as the last message; a command with arguments is
- [x] Long messages wrap to the list width, over as many lines as they need
- [x] The selected session shows all lines; the others show at most 3 and end with "…"
- [x] Searching a word from a recap or a last message finds the session and highlights it
- [x] Scattered letters do not match inside a recap or last message
- [x] A match beyond line 3 of an unselected session is still visible
- [x] Branch and PR show when known and are hidden otherwise
- [x] A session with no recap and no message of its own shows two rows
- [x] "(folder gone)", "New session" and the preview behave as before
- [x] `make test` and `make lint` pass; the full rescan time is not noticeably slower than before

---

## Completed

2026-11-26 - all four phases, in a worktree (`feat/finder-list-item`), delivered as a pull request.

- `4ddb81f` feat(sessions): scan the last message, branch and pull request
- `55158ad` feat(finder): wrap the recap and last message in the list, fold them unless selected
- `2136d43` feat(finder): search the last message and keep matches in view
- `f91218d` fix(sessions): skip a built-in command stored as plain text as the last message (found on real data: `/compact` is stored as plain text, with no command tags)
- `43d9f52` fix(finder): shorten a long branch before the folder row overflows a narrow list (found in a 80-column terminal: the branch chip overflowed the folder row)

Deviations from the plan:
- `ListRecap` is plain dim, not dim italic (the spec allowed dropping italic).
- "New session" also gets the trailing blank row, so every item has the same rhythm.
- A plain-text built-in command (`/compact`) is skipped as a last message by pattern, as well as the tagged commands.
- At narrow widths the branch chip shrinks (and below about 4 columns is dropped) before the folder row can overflow; the PR chip stays.

Verification: `make test` 92 passing, `make lint` clean. Cold scan of the 106 real sessions (187 MB): 627 ms on `origin/main`, 707 ms here (best of 3); warm path unchanged. Checked in a real terminal at 150x42 and 80x30: layout, folding and opening of the selected session, search (`'worktree`), match highlighting (bold yellow), narrow widths.
