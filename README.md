# VimClaude

**Every Claude Code session you've ever run, one keystroke away.**

You run Claude Code across a dozen projects. Somewhere in there is the session where you finally figured out that migration. Which project was it? What was it called? Who knows.

VimClaude is a Neovim front door for Claude Code. Open it, type a few letters, hit Enter, and you're back in the conversation. No `cd`, no `claude --resume`, no digging.

## Why you'll love it

- **Every project, one list.** All your sessions from `~/.claude/projects`, newest activity first. No project picker, no groups, nothing hidden.
- **Fuzzy find that keeps up.** Type and the list narrows on every keystroke. Matches run against each session's title, project, and path.
- **See the whole conversation before you commit.** The preview renders the full transcript as readable markdown, with collapsible folds so long sessions stay skimmable.
- **Instant, even with a huge history.** Sessions are indexed once, cached, and only rescanned when they change. Cold start shows cached rows immediately while the rescan finishes in the background.
- **Resume or start fresh.** Enter on a session continues it in its original project directory. Enter on **New session** starts a clean one.
- **Looks like your terminal, not like a theme.** Colors come straight from your terminal's own palette, so VimClaude blends in with whatever you already use. Flip light and dark and it repaints.
- **Read-only by design.** It never deletes, renames, or edits a session. Your history stays yours.

## How it works

```
nvim  ->  finder  ->  Enter  ->  Claude Code (full window)
  ^                                      |
  +------------- exit claude ------------+
```

1. Launch. The finder fills the screen.
2. Type to filter, arrow through the list, watch the preview follow.
3. Press Enter. Claude Code takes over the whole window.
4. Quit Claude and you land right back in the finder. Pick the next one.
5. Press Esc in the finder to leave.

## Install

VimClaude is a standalone Neovim config. It runs in its own `NVIM_APPNAME`, so it never touches your daily setup.

```sh
git clone https://github.com/loctvl842/vc ~/.config/VimClaude
NVIM_APPNAME=VimClaude nvim
```

Handy alias:

```sh
alias vc='NVIM_APPNAME=VimClaude nvim'
```

### Requirements

- Neovim (recent enough for `jobstart{term=true}` and OSC color queries)
- [Claude Code](https://claude.com/claude-code) on your `PATH`
- A terminal that answers OSC 10/11/4 color queries for the best colors (most modern ones do; VimClaude falls back gracefully if yours doesn't)

## Keys

| Key | Action |
| --- | --- |
| `<C-j>` / `<C-n>` / `<Down>` / `<Tab>` | Next session |
| `<C-k>` / `<C-p>` / `<Up>` | Previous session |
| `<Enter>` | Open the selected session |
| `<Esc>` | Leave VimClaude |

## Development

```sh
make test    # run every spec headless
make lint    # stylua check
```

Architecture notes live in [`docs/CODEMAP/`](docs/CODEMAP/INDEX.md). The product direction is in [`STRATEGY.md`](STRATEGY.md).

## Credits

The fuzzy matching engine is adapted from the BeastVim finder.
