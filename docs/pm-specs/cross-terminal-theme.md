---
name: cross-terminal-theme
description: The finder automatically wears the terminal's own colors and follows the terminal when its theme or light/dark mode changes, with no theme setup in VimClaude
generated: 2026-11-26
---

# Summary
VimClaude takes its colors from the terminal it runs in. Whatever theme the terminal uses (for example Monokai Pro), the finder looks like it belongs there, and when the terminal switches theme or flips between light and dark, the finder follows on its own.

---

# Problem

Today the finder is drawn in Neovim's built-in default colors, which know nothing about the terminal. In a terminal with a custom theme the finder looks like a foreign window: its background is a different shade from the terminal around it, its accent colors clash with the theme, and in a light terminal the text can be hard to read. The only way to fix this today is to pick, install and keep a matching color theme by hand, and redo that every time the terminal theme changes.

## Why now
The finder is the only screen the user sees besides Claude Code. Claude Code already looks right in the terminal's theme, so the finder is the one thing that stands out. Matching it removes the last visual seam between the two screens and needs no setup from the user.

---

# Target Behavior

The finder uses the terminal's own background, text color and palette. Nothing is chosen inside VimClaude.

```
STATE 1 - Terminal theme is dark (Monokai Pro):
┌ Claude Sessions ─────────────────────────────────────────────────────────────┐
│ > login_                                                             2 / 12  │
├──────────────────────────────────────────┬───────────────────────────────────┤
│ ▌Fix flaky login test                    │ You                               │
│    api-server            2m ago   34 msg │ The login test fails on CI only.  │
│  Rework login form copy                  │                                   │
│    web-app               3d ago    9 msg │ Claude                            │
│                                          │ Looks like a timing issue ...     │
├──────────────────────────────────────────┴───────────────────────────────────┤
│ <CR> continue   <C-n>/<C-p> move   <Esc> exit                                │
└──────────────────────────────────────────────────────────────────────────────┘
  Background: same as the terminal's background (no visible edge around the finder)
  Text: the terminal's text color
  Title, "You" and the prompt ">": the terminal's accent colors
  Matched letters "login": the terminal's highlight color
  Hints and meta lines (project, time, count): the terminal's dim gray
  Selected row: a soft tint of the terminal's own colors

─────────────────────────────────────────
STATE 2 - Terminal theme is light:
  Same layout. Background is the terminal's light background, text is dark,
  and every accent stays readable. Nothing is washed out or invisible.

─────────────────────────────────────────
STATE 3 - Terminal theme changes while the finder is open:
  The next time the terminal reports the change, the finder repaints in the
  new colors in place. Query, selection and scroll position are untouched.
```

---

# Scenarios

## 1 - First launch in a themed terminal

```
Step 1: The user has a dark terminal themed "Monokai Pro" and starts VimClaude.
  The finder opens already in Monokai Pro colors. There is no flash of
  default colors and no setup step.

Step 2: The user types a query.
  Matched letters, selected row and preview colors all come from the same theme.
```

## 2 - Same finder, different terminal

```
Step 1: The user opens VimClaude in a second terminal that uses a pale light theme.
  The finder is light with dark text, readable everywhere, with that
  terminal's accents.
```

## 3 - Terminal flips light/dark while the finder is open

```
Step 1: The finder is open in a dark terminal.
  Dark colors.

Step 2: The user (or macOS at sunset) switches the terminal to its light theme.
  The finder repaints to light. The query text, the highlighted row and the
  preview scroll position stay exactly where they were.
```

## 4 - Theme changes while Claude Code is open

```
Step 1: The user is inside a Claude Code session and the terminal theme changes.
  Claude Code is drawn by the terminal itself, so it changes with it.

Step 2: The user quits Claude Code and the finder returns.
  The finder shows in the new theme, with no stale colors.
```

## 5 - Terminal cannot report its theme (edge case)

```
Step 1: The user starts VimClaude in a terminal or multiplexer that does not
        tell programs whether it is light or dark.
  The finder opens in a dark scheme using the terminal's own palette.
  Nothing breaks and there is no error message. Text is readable.

Step 2: The terminal later starts reporting a light theme.
  The finder switches to light at that moment.
```

## 6 - Terminal with very few colors (edge case)

```
Step 1: VimClaude runs in a terminal that only supports the basic 16 colors.
  The finder still follows the terminal palette. Selected row and borders
  stay visible, just with fewer shades.
```

---

# Behavior Rules

- The user never picks, installs or configures a theme for VimClaude. There is no setting for it.
- The finder background is the terminal's own background, so there is no seam between the finder and the terminal edge.
- Colors always come from the terminal's palette, never from a fixed set of colors baked into VimClaude. Two terminals with different themes give two different-looking finders.
- Meaning stays constant across themes: title and prompt are accent, matched letters are highlight, project/time/count are dim, a missing project folder is error red, "You" and "Claude" in the preview keep two distinct colors.
- A theme change never resets the query, selection, scroll position or open preview.
- While Claude Code is full-window, VimClaude draws nothing, so the terminal theme shows through unchanged.
- If light/dark cannot be known, assume dark.
- The cursor stays hidden in the list and visible in the query, as today.

---

# Success Criteria

- [ ] In a dark themed terminal the finder background is indistinguishable from the terminal background.
- [ ] In a light themed terminal all text, hints and the selected row are clearly readable.
- [ ] Two terminals with different themes show visibly different finder colors, each matching its own terminal.
- [ ] Changing the terminal theme or light/dark mode with the finder open repaints it without losing query, selection or scroll.
- [ ] After quitting Claude Code following a theme change, the finder shows the new theme.
- [ ] No theme setting, install step or restart is needed.
- [ ] When the terminal does not report light/dark, the finder opens dark and readable with no error.
- [ ] Matched letters, selected row, dim text and error red remain distinguishable from normal text in every theme tested.

---

# Out of Scope

- Choosing or switching themes from inside VimClaude: the terminal owns the theme.
- Custom color overrides for individual parts of the finder: can be added later if someone needs them.
- Theming Claude Code itself: it has its own theme setting and is drawn by the terminal.
- Terminals that cannot show colors at all.
