---
name: finder-preview-style
description: Turn the preview from a plain-text transcript into a styled document (lines + highlight marks + folds) built from structured transcript blocks, with tree-sitter markdown, code highlighting and diffs
generated: 2026-11-26
---

> PM Spec: [docs/pm-specs/finder-preview-style.md](../pm-specs/finder-preview-style.md)

# Summary
Today `vc.transcript` flattens a session into markdown-ish text lines and the preview paints a few whole-line highlights. We change the output to a styled document: clean display lines (no markdown markers), highlight marks (byte ranges plus group names) and folds. Transcript records are first turned into typed blocks (prompt, reply, tool call, result, thinking), and small renderers (markdown, code, diff) turn each block into lines and marks. The preview applies marks as extmarks and relies on native wrapping with a hanging indent. All colors are `VCFinderPreview*` groups defined from the terminal palette.

---

# Context

## Problem
`transcript.lua` emits `lines` and `folds` only, so there is nowhere to express inline styling. Claude's markdown is copied verbatim (markers visible), speakers are `## You` / `## Claude` headings, tool calls and results are raw JSON inside one fold per run, and `preview.set_content` can only highlight whole lines by matching their text. Tool results are not paired with their calls and diffs are not rendered at all.

### Solution
After the change, `transcript` produces a `VC.Doc` (`lines`, `marks`, `folds`) through a block model and per-kind renderers. `preview.set_content` applies `marks` as extmarks and `folds` as before. Styling logic lives in small pure modules (`vc.markdown`, `vc.code`, `vc.diff`, `vc.toolline`) that are testable headless without any window. Highlight groups for every new role are added in `finder/highlights.lua` next to the existing ones, so theme flips repaint with no buffer work.

---

# Research

## Repo Search
- Searched for: `transcript`, `render_file`, `set_content`, `line_hl_group`, `foldexpr`, `PreviewTool`, `extmark`, `treesitter` under `lua/`, `test/`, `scripts/`
- Found: `lua/vc/transcript.lua` (Builder, 400-line chunking, cancel), `lua/vc/finder/ui/preview.lua` (fold map via `foldexpr`/`foldtext`, 4-entry cache keyed `id:size:mtime`, whole-line extmarks), `lua/vc/finder/highlights.lua` (all groups from palette with ctermfg fallback), `test/transcript_spec.lua`, `test/finder/finder_spec.lua` (preview tests asserting `tool: Read`, `VCFinderPreviewTool`, `You` headings), `test/sessions/fixtures.lua` (record builders, no `toolUseResult`). No existing markdown, code highlight or diff code. No treesitter use anywhere in `lua/`.
- Reuse opportunity: Yes - the Builder chunking and cancel contract, the fold map plumbing, the highlight palette helpers (`colors()`, `bold()`, `theme.mix`), the fixtures, and the `View`/`wo` helpers.

## Built-in / Existing Module Check
- Checked: Neovim 0.12.6 runtime. Bundled parsers `markdown`, `markdown_inline`, `lua`, `vim`, `c`, `query`, `vimdoc` load with `-u NONE`; `bash`, `python`, `typescript`, `javascript`, `json`, `diff` also load on this machine through the user's setup (not guaranteed elsewhere). `vim.treesitter.get_string_parser`, `vim.treesitter.query.get(lang, "highlights")`, `vim.text.diff`/`vim.diff`, window options `breakindent` + `breakindentopt=list:-1` + `formatlistpat` for hanging indents. Real transcripts: the record after a `tool_use` carries `toolUseResult` with `structuredPatch` (`oldStart`, `newStart`, `lines` with `+`/`-`/space prefixes) for Edit and Write, and `stdout`/`stderr`/`interrupted` for Bash.
- Found: tree-sitter markdown covers emphasis, strong, code spans, links, strikethrough, lists, quotes, fenced blocks, pipe tables. `structuredPatch` gives exact line numbers, so no diffing needed for edits already in the transcript.
- Decision: **Use** tree-sitter for markdown and for code highlighting (graceful fallback to plain when a parser is missing); **Use** `structuredPatch` for diffs; **Reuse** Builder/fold/highlight plumbing; **Build** the block model and the four renderers.

---

# Architecture Changes
- Modified: `lua/vc/transcript.lua` - Builder collects typed blocks and pairs `tool_result` with its `tool_use` by id; a render stage turns blocks into a `VC.Doc`. `render`/`render_file` keep their names and return `doc`.
- New: `lua/vc/markdown.lua` - `render(text, opts) -> lines, marks`, tree-sitter based, hides markers, builds hanging indents for lists and quotes.
- New: `lua/vc/code.lua` - `marks(code, lang) -> marks` from the language's `highlights` query mapped to palette groups; `nil` marks when no parser.
- New: `lua/vc/toolline.lua` - `call(name, input) -> "Name", "(args)"`, `result(name, record) -> lines, is_error`, `diff(patch) -> lines, marks`.
- Modified: `lua/vc/finder/ui/preview.lua` - apply `doc.marks`, window options for wrapping and hanging indent, new foldtext, drop speaker detection by text.
- Modified: `lua/vc/finder/highlights.lua` - new `Preview*` groups (prompt, band, dot, tool name/args/result, error, thinking, bold, italic, strike, link, code, quote, diff add/del bands, code syntax roles).
- Modified: `lua/vc/finder/config.lua` - `preview = { result_lines = 3, ... }` tunables (constants are confirmed against screenshots).
- Modified tests: `test/transcript_spec.lua`, `test/finder/finder_spec.lua`, `test/finder/highlights_spec.lua`, `test/sessions/fixtures.lua` (record builders with `toolUseResult`); new `test/markdown_spec.lua`, `test/code_spec.lua`, `test/toolline_spec.lua`.
- New: `scripts/bench-preview.lua` - render time for a large synthetic session.

```
VC.Doc   = { lines = string[], marks = VC.Mark[], folds = VC.Fold[] }
VC.Mark  = { line = int (1-based), col = int, end_col = int, hl = "VCFinderPreviewX", line_hl? = bool }
VC.Fold  = { start, stop, label }            -- unchanged
```

## Implementation Phases

## Phase 1: Message layout and tool lines - Goal: the Claude Code skeleton, plain text inside
1. **Block model** (File: `lua/vc/transcript.lua`)
   - Action: `feed` appends blocks `prompt`, `reply`, `call{name,input,id}`, `result{id,...}`, `thinking`; results attach to their call by `tool_use_id`; a result with no call becomes a standalone block. Keep skipping sidechain/meta records.
   - Why: results arrive after calls and parallel calls interleave; pairing is needed to show a call with its result.
   - Depends on: None
   - Risk: Medium (parallel tool calls, results arriving in another record)
2. **Render stage** (File: `lua/vc/transcript.lua`)
   - Action: blocks -> lines/marks/folds: prompt `> text` with band, reply `● text` with hanging indent (text still unstyled), call `● Name(args)`, result lines under `  ⎿  ` truncated to `result_lines` with the rest in a fold labelled `… +N lines`, thinking as a fold labelled `✻ Thinking…`. Header (title, `cwd - N messages`) stays. Chunked like the feed stage so a huge session never blocks.
   - Why: replaces the `## You` headings and the one-fold-per-run model.
   - Depends on: Step 1
   - Risk: Medium
3. **Tool line summaries** (File: `lua/vc/toolline.lua`)
   - Action: `call(name, input)` picks the one-line args (Bash command, file path for Read/Edit/Write, pattern for Grep/Glob, `description` for Agent, first string value otherwise, truncated); `result(name, rec)` extracts text (`stdout`/`stderr`, `[image]`, joined text blocks) and error state.
   - Why: raw JSON is the main source of noise today.
   - Depends on: None
   - Risk: Low
4. **Preview applies marks and new folds** (File: `lua/vc/finder/ui/preview.lua`)
   - Action: `set_content(view, doc)` writes lines, clears namespace, applies marks as extmarks (`hl_group` ranges, `line_hl_group` for whole lines), builds the fold map, `foldtext` returns the label as is. Remove text-matching of `## You`. `cache` stores the whole doc.
   - Why: single place that turns a doc into a screen.
   - Depends on: Step 2
   - Risk: Low
5. **Phase-1 highlight groups** (File: `lua/vc/finder/highlights.lua`)
   - Action: add `PreviewPrompt` (accent), `PreviewBand` (soft bg), `PreviewDot`, `PreviewToolName` (bold), `PreviewToolArgs`/`PreviewResult` (dim), `PreviewError` (red), `PreviewThinking` (dim italic); each with a `ctermfg` fallback. Remove `PreviewYou`/`PreviewClaude`/`PreviewTool` if unused after Step 4.
   - Why: theme flip repaint comes for free from `apply()`.
   - Depends on: None
   - Risk: Low
6. **Update tests** (Files: `test/transcript_spec.lua`, `test/finder/finder_spec.lua`, `test/sessions/fixtures.lua`)
   - Action: replace heading and `tool: Read` assertions with marker/fold/label assertions; add `F.tool_result_for(id, result)` builders carrying `toolUseResult`.
   - Depends on: Steps 1-4
   - Risk: Low

## Phase 2: Markdown in replies - Goal: no raw markers, real emphasis
1. **Markdown renderer** (File: `lua/vc/markdown.lua`)
   - Action: parse with `markdown` + `markdown_inline` string parsers; walk blocks (paragraph, heading, list, block quote, fenced code, table, thematic break) to build clean lines; inline marks for strong, emphasis, strikethrough, code span, link text. Lists use `•` and numbers, nested items indent by two. Quotes get a `▎ ` prefix and quote mark. Unknown nodes fall back to their source text.
   - Why: hiding markers needs real text rewriting, not conceal, so copying yields readable text.
   - Depends on: Phase 1
   - Risk: High (offset bookkeeping when markers are removed; mitigated by building output and marks in one pass)
2. **Wire into replies** (File: `lua/vc/transcript.lua`)
   - Action: reply and prompt text pass through `markdown.render`; the first line gets the `● ` marker, continuation lines the two-space indent (prefix included in marks offsets). When the parser is missing, text is kept as plain lines.
   - Depends on: Step 1
   - Risk: Medium
3. **Hanging indent on wrap** (File: `lua/vc/finder/ui/preview.lua`)
   - Action: window options `wrap`, `linebreak`, `breakindent`, `breakindentopt=list:-1`, `formatlistpat` matching `^\s*[•▎]\s\+\|^\s*\d\+\.\s\+`.
   - Why: native wrapping re-flows on resize with no re-render.
   - Depends on: Step 1
   - Risk: Medium (see Decision 1: fallback is pre-wrapping at render time)
4. **Markdown groups** (File: `lua/vc/finder/highlights.lua`)
   - Action: `PreviewBold`, `PreviewItalic`, `PreviewStrike`, `PreviewLink` (underline), `PreviewCode`, `PreviewQuote`, `PreviewHeading`.
   - Depends on: None
   - Risk: Low
5. **Tests** (File: `test/markdown_spec.lua`)
   - Action: input -> lines and marks table tests for each construct, nested emphasis, wrapped lists, unclosed markers, parser-missing fallback.
   - Depends on: Step 1
   - Risk: Low

## Phase 3: Code blocks - Goal: highlighted fences
1. **Code highlighter** (File: `lua/vc/code.lua`)
   - Action: `get_string_parser(code, lang)` and `query.get(lang, "highlights")`; capture name prefixes (`keyword`, `string`, `number`, `comment`, `function`, `type`, `operator`, `constant`) map to `VCFinderPreviewCode*` groups; unknown captures ignored. A language alias table (`sh`->`bash`, `js`->`javascript`, `ts`->`typescript`, `py`->`python`). pcall around `language.add`; missing parser returns no marks.
   - Why: colors come from our palette groups, never from the active colorscheme.
   - Depends on: Phase 2 Step 1
   - Risk: Medium
2. **Fence rendering** (File: `lua/vc/markdown.lua`)
   - Action: dim language label line, code lines indented four spaces in `PreviewCodeBlock` color, syntax marks offset by the indent; very long lines wrap via the same breakindent.
   - Depends on: Step 1
   - Risk: Low
3. **Code groups** (File: `lua/vc/finder/highlights.lua`)
   - Action: `PreviewCodeKeyword` (magenta), `String` (green), `Number` (yellow), `Comment` (dim italic), `Function` (blue), `Type` (cyan), `Operator`; ctermfg fallbacks. Red, green, yellow, blue and cyan already exist as palette slots in `colors()`; add the missing magenta slot (ANSI 5) there.
   - Depends on: None
   - Risk: Low
4. **Tests** (File: `test/code_spec.lua`)
   - Action: Lua snippet yields keyword/string/comment marks; unknown language yields none; alias resolution.
   - Depends on: Step 1
   - Risk: Low

## Phase 4: Diffs - Goal: Update/Write as colored diffs
1. **Diff lines** (File: `lua/vc/toolline.lua`)
   - Action: `diff(patch)` renders `structuredPatch` hunks as `<lineno> <+|-| > text` with full-line marks (`PreviewDiffAdd`, `PreviewDiffDel`, dim context) and the `Updated with N additions and M removals` count line. Write shows `Wrote N lines` plus the first lines. Edit with no patch (older sessions) falls back to a plain result line.
   - Why: patches are already in the transcript, no diffing needed.
   - Depends on: Phase 1
   - Risk: Medium (patch shape differences between Edit/Write/MultiEdit)
2. **Diff groups** (File: `lua/vc/finder/highlights.lua`)
   - Action: same tints as BeastVim's `view/highlights.lua`, built from the terminal palette instead of a theme: `PreviewDiffAdd` / `PreviewDiffDel` = `theme.mix(p.bg, p[GREEN|RED], 0.15)` line background; `PreviewDiffAddSign` / `DelSign` (line number and +/-) = fg `mix(bg, color, 0.6)` on the same band, bold; cterm fallback uses fg only. Word-level (intra-line) tints (BeastVim's `DiffAddWord`) are out of scope.
   - Depends on: None
   - Risk: Low
3. **Tests** (File: `test/toolline_spec.lua`)
   - Action: sample patches (add, remove, replace, context) and counts.
   - Depends on: Step 1
   - Risk: Low

## Phase 5: Edge content and performance - Goal: tables, images, long sessions
1. **Tables** (File: `lua/vc/markdown.lua`)
   - Action: `pipe_table` rendered with aligned columns and box-drawing lines; width-capped cells wrap to the pane via breakindent (no cell re-flow).
   - Depends on: Phase 2
   - Risk: Medium
2. **Placeholders and fallbacks** (Files: `lua/vc/transcript.lua`, `lua/vc/markdown.lua`)
   - Action: images as `[image]`, unknown block types as plain text, never dropped.
   - Depends on: Phase 1
   - Risk: Low
3. **Render budget and bench** (Files: `lua/vc/transcript.lua`, `scripts/bench-preview.lua`)
   - Action: render stage chunked and cancellable; measure render of a synthetic 5000-message session; first screen of lines is published early (partial doc) so the top shows immediately.
   - Why: PM scenario 7.
   - Depends on: Phase 1 Step 2
   - Risk: Medium
4. **Theme flip check** (File: `test/finder/highlights_spec.lua`)
   - Action: every new group is defined after `apply()`, in both rgb and cterm modes, and redefined on background change.
   - Depends on: Phases 1-4
   - Risk: Low

---

# Testing Strategy
- Headless tests: `make test` (all) and `make test SPEC=test/markdown_spec.lua` etc. Existing preview and transcript tests are rewritten in Phase 1; each later phase adds its spec. `make lint` (stylua) must pass.
- Bench: `nvim --headless -u NONE -l scripts/bench-preview.lua` after Phase 5; first lines available fast, full render of the 5000-message session recorded in the commit message.
- Manual (PM spec scenarios, `NVIM_APPNAME=VimClaude nvim` in the terminal theme the user uses, dark and light): 1 glance at sessions, 2 mixed markdown, 3 code (Lua, unknown language), 4 tool activity and fold open, 5 file edit, 6 theme flip with preview open, 7 very long session while typing, 8 table / image. Compare against the user's Claude Code screenshots; tune constants and colors in `highlights.lua` and `config.lua` only.

# Success Criteria
- [x] A session in the preview and in Claude Code read as the same screen: markers, hierarchy, emphasis
- [x] No raw `**`, backticks, `##`, or link syntax in any reply
- [x] Bold, italic, headings, lists, quotes, inline code, links, strikethrough each look distinct
- [x] Code blocks are highlighted for common languages and look like code when the language is unknown
- [x] Every tool call is one line; results are summarised and expand in place
- [x] File edits show as a colored diff with line numbers
- [x] Dark and light themes readable; a flip repaints live
- [x] Rapid selection changes never freeze typing or leave a half-styled screen
- [x] Wrapped lines keep a straight hanging indent in replies, lists and quotes
- [x] `make test` and `make lint` pass; no new group lacks a cterm fallback

# Decisions for you
1. **Wrapping**: native window wrapping with `breakindent` (recommended: re-flows on resize, copy keeps paragraphs whole) vs pre-wrapping lines at render time (exact control, but re-render on resize and copied text has hard breaks). Phase 2 Step 3 verifies native wrapping first and falls back only if the hanging indent is not right for lists.
2. **Markdown parsing**: tree-sitter (recommended: robust nesting, bundled) vs a hand-written scanner (no parser dependency, easier to be wrong on edge cases). Tree-sitter missing means plain text, never an error.
3. **Constants** (`result_lines`, truncation lengths, band tint strength): start from guesses, to be fixed once screenshots arrive.

---

## Completed

2026-11-26 - all five phases: block model and Claude Code layout, tree-sitter markdown, code highlighting, diffs, tables and bench.

- `0cfd507` docs(spec): add finder preview style pm spec
- `e0c0a58` docs(spec): add finder preview style dev spec
- `2693c37` feat(preview): draw sessions like Claude Code with prompts, replies and one-line tool calls
- `c2f8bd2` feat(preview): render markdown in replies without raw markers
- `3d8dff7` feat(preview): highlight fenced code with the terminal palette
- `58cdd07` feat(preview): show file edits as colored diffs with line numbers
- `78a739b` feat(preview): render tables and add a preview render bench
- `e1c7a6a` fix(preview): number diff context by the new file and tighten review findings

Verification: `make test` 109 passed, 0 failed; `make lint` clean. `scripts/bench-preview.lua` (10000 messages, 4.5 MB): full render about 2.4 s, first screen 5-7 ms, longest event-loop step about 25 ms. Checked in a real terminal (tmux, Monokai Pro palette): hanging indents on wrapped lists and quotes, bold/italic/underline attributes, code colors, diff bands, folds opening in place.

Where the build differs from this spec:
- Prompts stay plain text (Claude Code does not render markdown in the user's prompt); only replies go through `markdown.render`.
- Code blocks are indented two spaces under the reply text (matches the PM mockup), unknown languages get no color, there is no `CodeBlock` group and no operator color.
- Tables are drawn with box lines but not width-capped; a table wider than the pane wraps and breaks its borders.
- A wrapped block-quote line keeps its hanging indent but not the left bar (window wrapping cannot repeat it).
- Unknown content block types show as `[type]`; images show as `[image]`.
- The `# title` header line is gone; the title is already in the pane border, only the folder and message count line remains.
- Extra tunable: `config.preview.diff_lines` (24) and `args_width` (80) next to `result_lines` (3).
- The first render publishes the top of the document early (`on_partial`), then replaces it without moving the cursor.
- Constants and colors are still the guesses from the PM spec; they await the Claude Code screenshots.
