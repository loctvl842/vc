---
name: notify-toast
description: Plain information messages show as a quiet one-line toast at the bottom right, repeats merge into a count, while warnings and errors keep the notification cards at the top right
generated: 2026-11-27
---

# Summary
Information messages (like "3 lines yanked" or "Hit BOTTOM, continuing at TOP") appear as a single quiet line in the bottom right corner, in BeastVim's toast style. Warnings and errors keep the bigger notification cards in the top right, so the things that need attention still stand out.

---

# Problem

Every message now shows as a notification card. That is right for an error, but an everyday message such as "Hit BOTTOM, continuing at TOP" or "written" gets the same boxed, titled card in the top right, covering part of the finder or the Claude Code output for no good reason. Pressing a key that repeats the same message five times stacks five identical big cards. Information and problems look the same weight, so nothing signals which message deserves a look.

## Why now
Messages are now the only feedback the user gets, and they appear often. A light, low-noise style for the routine ones keeps the screen calm and lets the errors and warnings do their job.

---

# Target Behavior

Information goes to the bottom right as one borderless line. Warnings and errors go to the top right as cards, as today. The two never mix.

```
STATE 1 - One information message in the finder:
┌ Claude Sessions ──────────────────────────┬────────────── Fix flaky login test ─┐
│ > fix                                     │ ~/work/api-server - 34 messages     │
│                                           │                                     │
│ ▌ Fix flaky login test                    │ > The login test fails on CI only.  │
│   ~/work/api-server - main                │                                     │
│                                           │ ● It looks like a timing issue.     │
│   Add retry to the sync job               │                                     │
│   ~/work/sync - feat/retry                │                                     │
└<continue  <C-n>/<C-p> move  <C-l> preview ┴ Hit BOTTOM, continuing at TOP  󰋽 ─┘
```

The line has no box. It is dim text, with an icon at the right end colored for the level.

```
STATE 2 - An error and an information message together:
                                          ┌────────────────────────────────┐
                                          │  ERROR                         │   <- top right, card
                                          │ E21: Cannot make changes,      │
                                          │ 'modifiable' is off            │
                                          └────────────────────────────────┘
        ...
└<continue  <C-n>/<C-p> move  <C-l> preview ┴ Hit BOTTOM, continuing at TOP  󰋽 ─┘   <- bottom right, toast
```

```
STATE 3 - The same information message three times in a row:
  Hit BOTTOM, continuing at TOP x3  󰋽
  (one line, not three; the count is highlighted)
```

```
STATE 4 - Several different information messages (newest at the bottom):
  yanked 3 lines  󰋽
  written  󰋽
  Hit BOTTOM, continuing at TOP  󰋽
```

```
STATE 5 - A long or multi-line information message:
  Message "first line / second line / third line" shows as:
  first line second line third line  󰋽
  Wider than 60% of the terminal: cut with an ellipsis at the end:
  This is a very long message that does not fit in the …  󰋽
```

Toast details:
- One line, no border, no background box; the terminal background shows through.
- Text is dim; the icon at the right end carries the level color (blue for information).
- Width follows the text, between 10 columns and 60% of the terminal.
- A toast fades in and out in place (it does not slide).
- Toasts stack upward from the bottom right, newest at the bottom.

---

# Scenarios

## 1 - A routine message

```
Step 1: The user searches past the end of the file in the preview.
  A one-line toast fades in at the bottom right: "Hit BOTTOM, continuing at TOP  󰋽".
  Nothing in the top right.

Step 2: The user keeps typing.
  Keys keep working; the toast never takes focus.

Step 3: About 2 seconds later.
  The toast fades out and disappears.
```

## 2 - An error and a toast at once

```
Step 1: The user presses `x` in the preview (error) right after a search wrap (info).
  The E21 error shows as a card at the top right.
  The search wrap shows as a toast at the bottom right.
  Each expires on its own timing.
```

## 3 - The same message repeats

```
Step 1: A routine message appears once.
  "written  󰋽"

Step 2: The same message again within its lifetime.
  The line becomes "written x2  󰋽" (no second line) and its timer starts over.

Step 3: Many times.
  The count keeps going: x3 ... x99, then "x99+".
```

## 4 - Different messages

```
Step 1: Three different information messages within a second.
  Three lines appear one after another, staggered, newest at the bottom.

Step 2: Time passes.
  They fade out one by one, oldest first; the rest drop down to close the gap.
```

## 5 - Long and multi-line message

```
Step 1: An information message spans several lines.
  It shows on one line, with the line breaks turned into spaces.

Step 2: It is wider than 60% of the terminal.
  It is cut with an ellipsis; the icon stays visible at the right end.
```

## 6 - Small terminal

```
Step 1: The terminal is 40 columns wide and an information message arrives.
  The toast is at most 24 columns wide (60%), text cut with an ellipsis.
```

## 7 - Warning stays a card

```
Step 1: A warning arrives (for example "claude was not found on PATH").
  It shows as a WARN card at the top right, never as a toast.
```

---

# Behavior Rules

- Information goes to a toast. Warnings and errors go to cards. Messages quieter than information (debug, trace) are still not shown.
- This covers messages Neovim prints and anything else in the editor that reports a notice at information level.
- Identical information toasts that are still on screen merge into one line with a count (`x2` to `x99`, then `x99+`); every merge restarts its timer.
- Messages differing in any way (text) never merge.
- Toasts stay about 2 seconds. Cards stay about 3 seconds, as before.
- The toast is always one line: line breaks become spaces, long text ends with an ellipsis and the count is never the part that gets cut.
- Toasts never take focus and never steal keys.
- Toasts sit in the very last row of the screen, right aligned with a one column margin from the edge, above everything else (finder, Claude Code).
- Colors follow the terminal's palette and update on light/dark switch, same as the cards and the finder. No fixed color values.
- Toasts must not flicker or redraw the finder.
- Many toasts in quick succession are staggered a little.
- Toasts raised in the background (timers, job output) show safely and never cause an error themselves.
- If the stack of toasts would grow past the top of the screen, the oldest are removed early.

---

# Success Criteria

- [ ] An information message shows as one dim line at the bottom right, with no box.
- [ ] A warning or error shows as a card at the top right, as before.
- [ ] Five identical information messages in a row show one line with "x5".
- [ ] Multi-line information messages show on one line; long ones end with an ellipsis.
- [ ] The toast has a colored icon at the right end and follows the terminal palette in light and dark.
- [ ] Toasts fade in and out and the stack closes gaps.
- [ ] Typing continues uninterrupted while toasts are visible.
- [ ] A 40-column terminal still shows a readable, shortened toast.
- [ ] A background message shows as a toast with no error.
- [ ] "Press ENTER or type command to continue" still never appears.

---

# Out of Scope

- Progress bars and spinners (BeastVim's toast also shows these; VimClaude has nothing that reports progress).
- Showing warnings or errors as toasts, or information as cards: the split is fixed.
- A message history window.
- A key to dismiss toasts at once: they expire on their own.
- Per-message style choices (always toast for information).
