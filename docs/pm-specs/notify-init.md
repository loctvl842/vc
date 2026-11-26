---
name: notify-init
description: Every message Neovim would print at the bottom of the screen (errors, warnings, info) shows as a small notification card in the top right instead, so the "Press ENTER" prompt never appears
generated: 2026-11-27
---

# Summary
Messages that Neovim prints (like `E21: Cannot make changes, 'modifiable' is off`) appear as small, auto-dismissing cards stacked in the top right corner, in the same style as BeastVim's notifications. The screen is never interrupted by a "Press ENTER or type command to continue" prompt.

---

# Problem

VimClaude has no status line, no command line and no message area. When something goes wrong, for example the user presses a key that tries to edit the read-only preview, Neovim prints its complaint and then stops everything:

```
E21: Cannot make changes, 'modifiable' is off
Press ENTER or type command to continue
```

The finder or Claude Code is pushed up or covered by those two lines, nothing responds until the user presses Enter, and then the screen has to redraw. The message is also easy to miss or misread because it lands on top of whatever was on screen. The same thing happens for any other error or warning, including ones raised by Neovim itself that the user never asked for.

## Why now
The finder and the Claude screen are the only two things in VimClaude, and both are meant to be uninterrupted. A stray keypress should cost the user nothing. Messages still need to be seen (they are the only feedback the user gets), so they need a place of their own that does not take over the screen.

---

# Target Behavior

A message shows as a card pinned to the top right corner. The finder keeps its place and focus underneath; typing continues to go to the finder.

```
STATE 1 - One error, user is in the finder:
┌ Sessions ─────────────────────────────────┬──────────────────────────────┐
│ > fix                                     │  ┌────────────────────────────┐
│                                           │  │  ERROR                     │
│ ▌ Fix flaky login test                    │  │ E21: Cannot make changes,  │
│   ~/work/api-server - main                │  │ 'modifiable' is off        │
│                                           │  └────────────────────────────┘
│   Add retry to the sync job               │  (preview content continues)
│   ~/work/sync - feat/retry                │
└───────────────────────────────────────────┴──────────────────────────────┘
(no "Press ENTER" line anywhere, the bottom of the screen is untouched)
```

```
STATE 2 - Several messages in a row (newest at the bottom of the stack):
                                          ┌────────────────────────────────┐
                                          │  WARN                          │
                                          │ Hit BOTTOM, continuing at TOP  │
                                          └────────────────────────────────┘
                                          ┌────────────────────────────────┐
                                          │  ERROR                         │
                                          │ E21: Cannot make changes,      │
                                          │ 'modifiable' is off            │
                                          └────────────────────────────────┘
```

```
STATE 3 - A long message (more than 10 lines):
                                          ┌────────────────────────────────┐
                                          │  ERROR                         │
                                          │ Error executing Lua callback:  │
                                          │ ...line 1                      │
                                          │ ...line 2                      │
                                          │ ... (first 10 lines only)      │
                                          └────────────────────────────────┘
```

```
STATE 4 - Narrow terminal (fewer than 84 columns):
  Cards shrink to fit: they are never wider than the terminal minus a
  2-column margin on the right, and the text wraps inside the card.
```

Card details:
- Title row: an icon and the level word (ERROR, WARN, INFO), colored by level (red, yellow, blue, from the terminal's own palette).
- Body: the message text, wrapped to the card width.
- Cards are up to 80 columns wide, drawn above everything else (finder, preview, Claude Code).
- A card fades in, stays for a few seconds, then slides out to the right and fades away. The cards below it move up to close the gap.

---

# Scenarios

## 1 - A key tries to edit the read-only preview (the reported case)

```
Step 1: In the finder, the user moves into the preview and presses `x`.
  Nothing on the screen moves or gets covered.
  A card fades in at the top right: "ERROR  E21: Cannot make changes, 'modifiable' is off".

Step 2: The user keeps typing in the finder (no Enter required).
  Keys keep working exactly as before; the card does not take focus.

Step 3: About 3 seconds later.
  The card slides out and disappears.
```

## 2 - Several messages at once

```
Step 1: Two different problems happen within a second.
  Two cards appear one after the other, staggered by a fraction of a second,
  the older one on top.

Step 2: Time passes.
  They disappear one after the other, oldest first; the remaining card moves up.
```

## 3 - Message while Claude Code is on screen

```
Step 1: Claude Code is running full screen and Neovim raises a warning.
  A card shows in the top right over the Claude Code output.
  Claude Code keeps focus; the user's typing still goes to Claude Code.

Step 2: The card expires.
  It slides out; Claude Code output is unchanged underneath.
```

## 4 - The same message repeats

```
Step 1: The user presses `x` in the preview five times quickly.
  Five cards appear (one per message), stacked from the top.

Step 2: The stack would run past the bottom of the terminal.
  Only the newest cards that fit are kept; older ones slide out early to make room.
```

## 5 - Very small terminal

```
Step 1: The terminal is 40 columns wide and a message arrives.
  The card is 38 columns wide with its text wrapped, still fully readable.
```

## 6 - Message with nothing to say

```
Step 1: Neovim emits an empty message, or a search count like "[3/12]".
  No card appears (the finder already shows its own counts).
```

---

# Behavior Rules

- Every message Neovim would print at the bottom of the screen goes to a card instead. This includes errors (E-numbered, Lua errors, failed commands), warnings and plain informational messages. Nothing is printed in the old place and the "Press ENTER or type command to continue" prompt never appears.
- Level: errors are ERROR, warnings are WARN, everything else is INFO.
- Multi-line messages keep their line breaks. More than 10 lines are cut after the 10th line.
- Anything else in the editor that reports a notice (for example a plugin or a background task) shows through the same cards.
- Cards never take focus and never steal keys.
- A card stays about 3 seconds. If the user clicks into a card with the mouse, it stays until focus leaves, then goes 2 seconds later.
- Many cards in quick succession are staggered a little so they do not all pop in at once.
- Messages raised in the background (timers, job output) show safely and never cause an error themselves.
- Colors follow the terminal's palette and update when the terminal switches between light and dark, same as the finder. No fixed color values.
- Cards must not flicker or redraw the finder when they appear or disappear.
- Search: a failed search shows one card "Pattern not found: <pattern>" (WARN), not two; wrapping around the end of the file shows "Hit BOTTOM, continuing at TOP" (or the reverse).

---

# Success Criteria

- [ ] Pressing an editing key in the read-only preview shows the E21 text as a card in the top right.
- [ ] "Press ENTER or type command to continue" never appears, in the finder or in Claude Code.
- [ ] The finder (list, input, preview) is never pushed or covered by the message text.
- [ ] Typing continues uninterrupted while a card is visible.
- [ ] Cards are colored by level and use the terminal's palette in both light and dark.
- [ ] Several messages stack without overlapping and close the gap when one leaves.
- [ ] Messages longer than 10 lines are cut at 10.
- [ ] A narrow terminal still shows a readable card.
- [ ] A background message (for example one raised from a timer) shows as a card with no error.

---

# Out of Scope

- A message history window or `:messages`-style browser: cards are fire-and-forget (deferred until there is a need).
- A key to dismiss all cards at once: cards expire on their own.
- Per-message routing rules (e.g. hide certain messages): everything shows, except empty messages and search counts.
- Sounds, OS-level notifications, or notifications from Claude Code's own output.
- Command-line input (typing `:` commands): VimClaude does not use a command line and this spec does not add one.
