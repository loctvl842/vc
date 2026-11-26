---
name: finder-field-search
description: Parse field:value terms out of the finder query, narrow items by one field each in the matcher, then run the rest of the query as today; colour recognised prefixes in the prompt
generated: 2026-11-27
---

> PM Spec: [docs/pm-specs/finder-field-search.md](../pm-specs/finder-field-search.md)

# Summary
A pure parser (`vc.finder.fieldquery`) splits the typed text into field terms (`cwd:jarvix`) and a remaining pattern. The filter keeps both. The matcher first requires every field term to match its own field of the item (reusing the existing term parser and scorer), then scores the remaining pattern exactly as it does now. The prompt colours recognised `field:` prefixes. Nothing else in the finder changes for a query without field terms.

---

# Context

## Problem
`Filter` holds one string, `pattern`, and `matcher.score_item` scores it against every field span of an item (title, location, recap, last message). There is no way to say which span a word must match, and branch and PR are not in `item.text` at all. Everything that reads `filter.pattern` (the empty-query checks, the Enter-while-typing check, the empty message, `is_superset`) assumes it is the typed text.

### Solution
`Filter:update(text)` stores the typed text (`text`), the field terms (`terms`) and the remainder (`pattern`). `source.items` names each field span (`title`, `cwd`, `recap`, `msg`) and adds hidden spans for branch and PR that only field terms search. The matcher drops items that fail any field term, then scores `pattern` as today (an empty remainder gives score 1, so the order stays newest first). Callers that mean "what the user typed" move to `filter.text`. `format` maps highlight positions for the two new spans.

---

# Research

### Repo Search
- Searched for: `filter.pattern`, `filter:update`, `parse_pattern`, `score_item`, `is_superset`, `item.fields`, `plain`, `recap_at`, `VCFinderSpinner` in `lua/vc/finder/`; existing tests in `test/finder/`.
- Found:
  - `matcher.parse_pattern` already turns a string into AND-groups of terms with fzf operators (`'exact`, `^prefix`, `suffix$`, `!inverse`, `a|b`), smartcase included. `score_text(hay_orig, hay_lower, and_groups, plain, base)` scores one span and returns positions offset by `base`.
  - `score_item` scores the whole query inside each `item.fields` span and sums; a span matches only if all the query's groups match inside it. This is today's behaviour for several normal words and stays.
  - `^8$` through `score_term` is an exact whole-span match (prefix and suffix both checked on the first occurrence), which gives `pr:8` its exact-number rule without special code.
  - `Filter.pattern` is read in: `finder/init.lua` (`_sync_items`, `set_rows`: "New session only on empty query"), `finder/keymaps.lua:39` (Enter while typing), `finder/render.lua` (empty message), `matcher.run` (pattern, state), `pipeline/match.lua` (state).
  - `ui/input.lua` already owns extmarks on the prompt (count, spinner) and a `TextChanged(I)` autocmd.
  - `source.format` maps `item.positions` onto the title row, the location and the messages only.
- Reuse opportunity: Yes - the term parser, `score_text`, the field-span mechanism, the prompt extmark pattern, `VCFinder*` highlight groups.

### Built-in / Existing Module Check
- Checked: `vim.split`, `vim.regex`, `string.find` for tokenising; `nvim_buf_set_extmark` with `hl_group` for the prefix colour; the finder's `highlights.lua` for group definitions.
- Found: a hand tokeniser is needed (quotes plus `field:` recognition); `string.find`/`gmatch` style scanning is enough. Extmark `hl_group` colours the prefix.
- Decision: **Reuse** the matcher's parser and scorer; **Build** one small pure module for tokenising (`fieldquery`), plus a highlight group.

### Findings that differ from the PM spec text
- **Quoted phrase must be an exact substring.** `title` matches loosely, so `title:"fix login"` run through the fuzzy parser would match "Fix flaky login test" (letters in order). Scenario 8 requires it not to match, so a quoted value becomes one exact term whose text keeps its spaces. A new `matcher.term()` builds a term directly instead of going through whitespace splitting.
- **Operators leak into field values.** An unquoted value goes through the same term parser as a normal word, so `cwd:^jar`, `cwd:a|b` and `cwd:!work` behave like their normal-search forms. This is deliberate reuse, not a promised feature: negation stays out of scope in the PM spec and gets no tests or docs.
- **Several normal words** still must all match inside one field (`score_item` today). Field terms narrow before that and do not change it.
- **Subset elimination breaks** for typing `cwd` then `cwd:` then `cwd:j` (the word `cwd` was a plain word, then stopped being one), so it is limited to queries with no field terms (Phase 1).
- **PM spec State 5 mock** showed an invented "(no sessions)" text; it now shows today's `No sessions match "<text>"`.

---

# Architecture Changes
- New `lua/vc/finder/fieldquery.lua` - pure tokeniser: `parse(text) -> {terms, rest, spans}`; field-name table.
- Modified `lua/vc/finder/filter.lua` - holds `text`, `terms`, `pattern` (the remainder); `update(text)` parses.
- Modified `lua/vc/finder/matcher.lua` - extract `make_term`; field-term pass in `score_item`; state keyed on `filter.text`; subset elimination only without field terms.
- Modified `lua/vc/finder/source.lua` - named field spans; hidden spans for branch and PR; `branch_at`/`pr_at`; `format` highlight mapping for both.
- Modified `lua/vc/finder/init.lua`, `keymaps.lua`, `render.lua` - read `filter.text` where they mean the typed text.
- Modified `lua/vc/finder/ui/input.lua` - colour recognised prefixes immediately on each text change.
- Modified `lua/vc/finder/highlights.lua` - `VCFinderField` group.
- Modified `test/finder/finder_spec.lua`, new `test/finder/fieldquery_spec.lua` - tests.
- Modified `docs/CODEMAP/modules.md` - via `/update-codemap` after merge (not by hand).

## Implementation Phases

## Phase 1: Narrow by field - `cwd:`, `title:`, `recap:`, `msg:` end to end in the matcher
Mergeable on its own: works without prompt colours or branch/PR.

1. **Tokeniser** (File: `lua/vc/finder/fieldquery.lua`)
   - Action: `parse(text)` scans the text. A term is a whitespace-delimited token `name:value` where `name` is one of `cwd title branch pr recap msg` (lowercase, directly followed by `:`) at the start of the token. Value is the rest of the token; if it starts with `"`, the value runs to the next `"` (or the end of the text when unterminated) and `quoted = true`. Returns `terms = {{name, value, quoted}}` only for non-empty values, `rest` = the text with every recognised term (empty-valued ones too) removed and spaces collapsed, and `spans = {{s, e}}` of each recognised `name:` prefix (empty values included) for colouring. Unknown names stay in `rest`.
   - Why: single, testable place for the syntax; pure so it needs no UI.
   - Depends on: None
   - Risk: Low

2. **Filter state** (File: `lua/vc/finder/filter.lua`)
   - Action: add `text` and `terms`; `update(text)` sets `text`, calls `fieldquery.parse`, sets `terms` and `pattern = rest`. `new()` initialises all three.
   - Why: `pattern` keeps meaning "what the matcher scores"; `text` is "what the user typed".
   - Depends on: Step 1
   - Risk: Low

3. **Callers read the typed text** (Files: `lua/vc/finder/init.lua`, `lua/vc/finder/keymaps.lua`, `lua/vc/finder/render.lua`)
   - Action: `init.lua` (`_sync_items`, `set_rows`) uses `filter.text == ""` for "New session" (a query of field terms only must remove it: its empty text matches nothing, so it would otherwise survive a score of 1). `keymaps.lua:39` compares the input text with `filter.text`. `render.lua` builds the empty message from `filter.text`.
   - Why: otherwise `cwd:j` alone would keep "New session", Enter-while-typing would never see the text as current, and the message would show only the remainder.
   - Depends on: Step 2
   - Risk: Medium (easy to miss a reader; grep `filter.pattern` after)

4. **Name the spans** (File: `lua/vc/finder/source.lua`)
   - Action: in `items`, give each field span a `name`: `title`, `cwd`, `recap`, `msg`.
   - Why: field terms look spans up by name.
   - Depends on: None
   - Risk: Low

5. **Matcher** (File: `lua/vc/finder/matcher.lua`)
   - Action:
     a. Extract the per-term construction in `parse_pattern` into `make_term(text, ignorecase, smartcase)` (operators, entropy, smartcase), used by `parse_pattern` unchanged.
     b. In `M.run`, build once per run `field_terms = {{name, groups}}`: unquoted values via `parse_pattern(value, ...)`; quoted values as one group with one `exact` term whose `text` is the value (spaces kept, lowercased unless smartcase finds a capital).
     c. In `score_item`, before the normal scoring: for each field term, find the item's span with that name (none, or `item.row` lacking it, means the item is excluded), run `score_text(span, ..., groups, span.plain, span.from - 1)`; any 0 excludes the item. Collect the positions. If the remainder has no groups, return `1, positions`; otherwise score the remainder as today and add the field positions to the result.
     d. Use `filter.text` as the state pattern, and only allow `use_subset` when both the previous and the current run had no field terms (store `has_terms` in the state).
   - Why: field narrowing reuses the existing matching, and the ranking comes from the remainder only (field scores are not added).
   - Depends on: Steps 2, 4
   - Risk: Medium (hot path; subset logic; keep the no-field path byte-identical)

6. **Tests** (Files: `test/finder/fieldquery_spec.lua`, `test/finder/finder_spec.lua`)
   - Action: tokeniser cases (below); finder cases: `cwd:` narrows by folder only, field plus remainder, term order irrelevant, two terms for one field, `cwd:` alone changes nothing, `ticket:42` is plain text, `title:"fix login"` exactness, loose vs plain per field, case sensitivity, "New session" gone for a field-only query, the typing sequence `cwd`, `cwd:`, `cwd:j` giving the right list at each step.
   - Why: PM scenarios 1 to 10 become executable.
   - Depends on: Steps 1 to 5
   - Risk: Low

## Phase 2: Prompt feedback - colour recognised prefixes
1. **Highlight group** (File: `lua/vc/finder/highlights.lua`)
   - Action: add `VCFinderField` (terminal palette, bold, accent that reads on `NONE` bg), alongside the other `VCFinder*` groups, re-tinted by the same refresh.
   - Why: consistent with the finder's palette handling.
   - Depends on: None
   - Risk: Low

2. **Prefix extmarks** (File: `lua/vc/finder/ui/input.lua`)
   - Action: a `M.mark_fields(view)` that clears its own namespace and sets an extmark with `hl_group = "VCFinderField"` on each `fieldquery` span of the current text (offset by the prompt prefix length). Call it from the `TextChangedI`/`TextChanged` autocmd directly, not through the debounce, so the colour appears as the colon is typed.
   - Why: PM scenario 6 - the prefix changes colour on the colon, before any list change.
   - Depends on: Phase 1 Step 1, Step 1
   - Risk: Low

3. **Tests** (File: `test/finder/finder_spec.lua`)
   - Action: type `cwd:`, assert one extmark over `cwd:`; type `ticket:`, assert none; the colour is present for an empty value.
   - Depends on: Step 2
   - Risk: Low

## Phase 3: Branch and PR - `branch:`, `pr:` and their highlights
1. **Hidden spans** (File: `lua/vc/finder/source.lua`)
   - Action: in `items`, when the row has a branch or PR, append them to `item.text` as spans named `branch` (plain) and `pr` (the number as a string, no `#`) with `only = true`, recording `branch_at` and `pr_at`. `matcher.score_item` skips `only` spans in the normal pass (normal words never search them). Field terms for `pr` strip a leading `#` and use `^N$`.
   - Why: they are not in `item.text` today, and the normal query must not start matching branches.
   - Depends on: Phase 1
   - Risk: Medium (the normal-pass skip must not change scores or the cache `_lower`)

2. **Highlight mapping** (File: `lua/vc/finder/source.lua`)
   - Action: `format` maps positions in the branch and PR spans onto the folder row chips, accounting for `fit(branch, room, "head")` cutting the end and the `· #` literals; positions in a cut part draw nothing, as for the title today.
   - Why: PM rule "matches are highlighted inside the field they matched".
   - Depends on: Step 1
   - Risk: Medium (column arithmetic on a row that already shifts with age and message count)

3. **Tests** (File: `test/finder/finder_spec.lua`)
   - Action: `branch:ma` finds the `main` session and highlights it; `pr:8` finds #8 and not #80; `pr:#8` the same; a session without branch or PR never matches; `main` as a normal word does not match a session only by its branch.
   - Depends on: Steps 1, 2
   - Risk: Low

---

# Testing Strategy
- Headless tests: `make test` (all); `make test SPEC=test/finder/fieldquery_spec.lua` and `SPEC=test/finder/finder_spec.lua` per phase. `make lint` (stylua) before each commit.
  - `fieldquery_spec`: `cwd:jarvix` -> one term, empty rest; `cwd:` -> no term, one prefix span; `foo:bar` -> rest `foo:bar`; `title:"fix login" x` -> quoted term, rest `x`; unterminated quote; `cwd:a cwd:b` -> two terms; `Cwd:x` -> rest (names are lowercase); `https://x` -> rest; spans point at `cwd:` only.
  - Regression: every existing finder spec passes untouched (queries without a field term behave as before).
- Bench: `scripts/bench-index.lua` is not affected (no index change). Run a quick 5 000-row timing of a plain query and of `cwd:x y` through `matcher.run` to confirm the no-field path is unchanged and the field path is not slower than a normal query; no new bench file.
- Manual: open `NVIM_APPNAME=VimClaude nvim` and walk the PM spec scenarios: 1 (narrow by folder then title), 2 (term order), 3 (same word with and without a field), 4 (same field twice), 5 (no match: counter `0 / N`, message `No sessions match "..."`), 6 (type `cwd:` letter by letter and watch the prefix colour and the list), 7 (`ticket:42`, a URL), 8 (quoted phrase), 9 (`title:nvm` vs `msg:nvm`), 10 (capital letter). Check the prefix colour in a light and a dark terminal, and highlights inside folder, recap, message, branch and PR on a narrow list (34 columns).

# Success Criteria
- [ ] `cwd:jarvix` shows only sessions whose folder matches jarvix, not ones that merely mention it
- [ ] `cwd:jarvix title:nvim` shows the sessions that satisfy both
- [ ] `cwd:jarvix startup` narrows by folder, then searches "startup" as today, best match first
- [ ] Term order in the box makes no difference to which sessions are shown
- [ ] A recognised `field:` prefix has its own colour; an unknown prefix does not
- [ ] `cwd:` with no value leaves the list unchanged
- [ ] `ticket:42` and URLs are searched as plain text
- [ ] `title:"fix login"` requires both words together in the title
- [ ] `title` and `cwd` match loosely; `recap`, `msg` and `branch` match as written; `pr:8` does not match #80
- [ ] Matches are highlighted inside the field they matched
- [ ] A query with no field term gives the same list and order as before
- [ ] The counter and the empty state reflect the narrowed list
- [ ] Technical: no remaining reader of `filter.pattern` that means "typed text" (`grep -rn "filter.pattern" lua/`)
- [ ] Technical: `make test` and `make lint` pass; typing `cwd`, `cwd:`, `cwd:j` never leaves the list stale
