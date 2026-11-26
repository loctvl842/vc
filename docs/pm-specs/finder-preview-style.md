---
name: finder-preview-style
description: The finder's conversation preview is drawn the way Claude Code draws a session - same message markers, markdown styling, tool call lines, diffs and code blocks - so a previewed session looks like the real one
generated: 2026-11-26
---

# Summary
The preview pane shows a past session as Claude Code itself would have shown it: the user's prompts, Claude's replies with real bold, italic, headings, lists, inline code and highlighted code blocks, one-line tool calls with their results tucked underneath, and file edits as colored diffs. Browsing sessions should feel like scrolling the actual Claude Code screen, not reading a text dump.

---

# Problem

Today the preview is a plain text transcript. Each speaker gets a heading ("You", "Claude"), Claude's replies keep their raw markdown symbols (`**bold**`, backticks, `##`), code is uncolored, and every run of tool calls collapses into one gray block that opens into raw JSON. A session that looked clean and readable in Claude Code looks noisy and flat in the preview, so the user cannot recognise a conversation at a glance and has to open it just to see what it said.

## Why now
The finder already wears the terminal's own colors, and Claude Code is the only other screen the user lives in. Matching its message layout and text styling closes the last visual gap between "the list of sessions" and "the session itself", so a quick look in the preview is enough to decide which session to continue.

---

# Target Behavior

The preview reproduces Claude Code's transcript look. Colors come from the terminal's palette (as everywhere else in the finder), never fixed values.

```
STATE 1 - A normal exchange:
┌ Fix flaky login test ────────────────────────────────┐
│ ~/work/api-server - 34 messages                      │
│                                                      │
│ > The login test fails on CI only. Can you look      │
│   into it?                                           │
│                                                      │
│ ● It looks like a timing issue. The test clicks      │
│   the button before the form is ready.               │
│                                                      │
│   Plan:                                              │
│   - Wait for the `form` to mount                     │
│   - Re-run the suite on CI                           │
│                                                      │
│ ● Read(tests/login.spec.ts)                          │
│   ⎿  Read 84 lines                                   │
│                                                      │
│ ● Update(tests/login.spec.ts)                        │
│   ⎿  Updated with 2 additions and 1 removal          │
│      41 -  await page.click(submit)                  │
│      41 +  await page.waitFor(form)                  │
│      42 +  await page.click(submit)                  │
│                                                      │
│ > Thanks, run it again                               │
│                                                      │
│ ● Bash(npm test)                                     │
│   ⎿  12 passed                                       │
└──────────────────────────────────────────────────────┘
```

```
STATE 2 - Text styling inside Claude's replies (what each thing looks like):
  ● **Important:** the fix is *small*.        "Important:" bold, "small" italic
    `npm test` passes now.                    "npm test" in the inline-code color, no backticks shown
    ## Next steps                             bold heading, no "##" shown
    1. Merge the branch                       numbered list keeps its numbers, wrapped lines align under the text
    - Delete the old test                     bullet list, nested items indented
    > Note: CI is slower than local.          quote bar on the left, dimmed italic text
    See [the docs](https://x.dev).            link text underlined, address not shown inline
    ~~old~~                                   strikethrough

─────────────────────────────────────────
STATE 3 - Code block:
  ● Here is the helper:

      lua
      local function wait(form)           keywords, strings, numbers and comments
        return form:ready() -- poll       in the terminal's palette colors
      end

  Language name is shown dim above the code. Code lines never wrap into
  the left margin; very long lines wrap with an indent.

─────────────────────────────────────────
STATE 4 - Tool calls and results:
  ● Bash(git status --short)                  tool name bold, arguments dim
    ⎿   M lua/vc/finder/query.lua             first lines of the result, dim
        M lua/vc/sessions/scan.lua
        … +14 lines                           the rest is folded; open it with the fold keys

  ● Bash(rm build)
    ⎿  Error: no such file                    errors in the error color

─────────────────────────────────────────
STATE 5 - Thinking:
  ✻ Thinking…                                 dim, closed by default
  (opened)
  ✻ Thinking…
    The test is flaky because the click races
    the form mount. I should wait first.      dim italic

─────────────────────────────────────────
STATE 6 - Session header and the user's own messages:
  ┌ title ────────────────────────────┐
  │ ~/work/api-server - 34 messages   │       dim line under the title
  │ > user prompt                     │       chevron in the accent color, text on a subtle band
  └───────────────────────────────────┘
  Consecutive user prompts and Claude messages are separated by one blank line,
  exactly as in Claude Code. There are no "You" / "Claude" headings anymore.

─────────────────────────────────────────
STATE 7 - File edits as diffs:
  ● Update(src/app.lua)
    ⎿  Updated with 1 addition and 1 removal
       12    local port = 80
       13 -  local host = "a"                   removed line: error-colored band
       13 +  local host = "b"                   added line: green band
       14    start(host, port)

─────────────────────────────────────────
STATE 8 - Content the preview does not know how to style:
  Shown as plain readable text in the normal text color. Never garbled,
  never hidden, never raw JSON where a one-line summary would do.
```

---

# Scenarios

## 1 - Glance at a session in the list

```
Step 1: The user moves the selection over a session.
  The preview fills with the conversation: prompts marked ">", replies
  marked "●", styled text, one-line tool calls. No raw markdown symbols
  are visible.

Step 2: The user moves to a different session.
  The new conversation replaces it with the same look. There is no flash of
  unstyled text on the way.
```

## 2 - Reading a reply with mixed markdown

```
Step 1: Claude's reply has a heading, a bullet list, bold words and inline code.
  Heading is bold, bullets use a bullet glyph, bold words are bold, inline
  code is in its own color with no backticks. Wrapped list lines line up
  under the first letter of the item, not under the bullet.

Step 2: The same reply is narrower than the pane.
  Text wraps at the pane edge, keeping the "●" hanging indent so the left
  edge of the text stays straight.
```

## 3 - Code in a reply

```
Step 1: A reply contains a fenced code block in Lua.
  The language name appears dim above it. Keywords, strings, numbers and
  comments use different palette colors.

Step 2: A reply contains a block with an unknown or no language.
  It still looks like code (same indent, code color) but without syntax colors.
```

## 4 - Tool activity

```
Step 1: A stretch of the session has several tool calls in a row.
  Each call is one line "● Name(args)" with its result's first lines beneath
  it. Long results end with "… +N lines" and the rest is folded.

Step 2: The user opens that fold with the usual fold keys.
  The full result appears in place, still dimmed and indented, still under
  its call. Closing the fold returns to the summary.

Step 3: A call failed.
  Its result is shown in the error color from the first line.
```

## 5 - A file edit

```
Step 1: The session edited a file.
  The call shows "Update(path)", a count line ("2 additions and 1 removal")
  and the changed lines with line numbers, removed lines on an error-colored
  band, added lines on a green band, unchanged context lines plain.
```

## 6 - Terminal theme flips while a preview is open

```
Step 1: The user switches the terminal from dark to light.
  Every color in the preview (text, dim, code, diff bands, quote bar)
  repaints for the new background in place. Scroll position and open folds stay.
```

## 7 - Very long session

```
Step 1: The user selects a session with thousands of messages.
  The top of the conversation appears immediately; the rest fills in as it
  is prepared. Moving the selection away cancels the work. Typing in the
  query box is never delayed by the preview.
```

## 8 - Odd content

```
Step 1: A reply contains a table, an image, or markdown the preview cannot style.
  Tables keep their rows and columns aligned with box lines; images show
  as "[image]"; anything else shows as plain text. Nothing is dropped.
```

---

# Behavior Rules

- Layout follows Claude Code: user prompts start with a ">" chevron, Claude's text starts with a "●" marker, continuation lines are indented to sit under the text
- Markdown markers (`**`, `*`, backticks, `#`, link brackets) are never shown when the style they stand for is applied
- All colors come from the terminal's palette and flip with the terminal's light/dark mode; no fixed hex colors
- Bold, italic, underline and strikethrough use the terminal's text attributes, so they work in any terminal that Claude Code itself works in
- Tool results show only their first few lines; the remainder is folded and opens with the usual fold keys
- Thinking is closed by default and opens with the fold keys
- Tool calls that follow each other (shell commands, file reads, searches) fold into one dim summary line such as `Ran 2 shell commands` or `Read 1 file, ran 2 shell commands`, as in Claude Code; opening it shows every call with its result. A failed call and every other kind of tool call (edits, agents, MCP) stay on their own visible lines
- Text copied from the preview is the readable text, without markdown markers
- The preview stays read-only; selection and fold keys behave as they do today
- Pane width changes (resizing the finder) re-wrap the text without losing the position

---

# Success Criteria

- [ ] A session viewed in the preview and the same session in Claude Code are recognisable as the same screen: same markers, same hierarchy, same emphasis
- [ ] No raw `**`, backticks, `##`, or link syntax appears in any reply
- [ ] Bold, italic, headings, lists, quotes, inline code, links and strikethrough each look distinct
- [ ] Code blocks are highlighted for at least the common languages and look like code when the language is unknown
- [ ] Runs of shell, read and search calls fold into one summary line; each call is one line when opened, with its results summarised and expanding in place
- [ ] File edits show as a colored diff with line numbers
- [ ] Dark and light terminal themes are both readable; flipping the theme repaints live
- [ ] Selecting through sessions rapidly never freezes typing or leaves a half-styled screen
- [ ] Wrapped lines keep a straight hanging indent in every reply, list and quote

---

# Decisions for you

1. **Tool calls: always one visible line each, or one fold per run like today?**
   Recommended: one visible line per call with results folded. It is what makes it look like Claude Code, and the call lines are what you scan to remember a session. Cost: very tool-heavy sessions become longer.
2. **Thinking: show as `✻ Thinking…` folded (recommended), or hide it entirely?** Claude Code hides it unless expanded; keeping it folded preserves what the preview shows today.
3. **Sub-agent and side-chain messages:** keep hidden (as today, recommended) or show as a nested, indented block.

# Reference captures needed

The look above is from how Claude Code is known to draw a transcript. To get the details pixel-faithful, captures from your terminal are the ground truth. If you open Claude Code on a few sessions, I need screenshots of:

- [ ] A user prompt (chevron color, background band, how a multi-line prompt wraps)
- [ ] A reply with a heading, bold, italic, inline code, a bullet list, a numbered list and a quote
- [ ] A fenced code block (language label, indent, colors)
- [ ] A Bash call with long output (the "… +N lines" line) and one that failed
- [ ] An Edit/Update diff and a Write call
- [ ] A thinking block, opened and closed
- [ ] A table, if any session has one
- [ ] A todo list, if any session has one

---

# Out of Scope

- Live updating of a session that is still running - the preview shows the file as of selection
- Showing images or other inline media (placeholder only)
- Mouse interaction on links or code (no click-to-open)
- Reproducing Claude Code's input box, status line or permission prompts - only the conversation is shown
- Sub-agent transcripts as separate panes - deferred until the main look is right
