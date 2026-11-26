# VimClaude Strategy

## Vision

<!-- vision: author-approved 2026-11-26 -->

`VimClaude` exists so that someone who works in Claude Code every day can get into any session, old or new, without leaving Neovim.
It serves the author, who runs Claude Code across many projects, and it turns a query typed into a finder into the one session they meant.
It owns exactly one thing: a finder over every Claude Code session on the machine.

### One source, read-only

The finder has exactly one source: the session transcripts under `~/.claude/projects`.
It scans all projects at once, never only the current one.
Each session is listed with its metadata, so a session is recognized by what it is and not by its id.
A query matches that metadata; it does not search transcript text.
Every session is listed, in one flat list ordered by last activity; none is hidden on a guess about whether it is worth showing, and none is grouped under a project header.
The finder never writes to the session store: it does not delete, rename, or edit a session.
No other source is added, not files and not other agents' sessions.

### The front door

Enter on a session continues it.
The first row is "New session", and Enter on it starts a fresh session.
That row appears only while the query is empty; any query removes it.
A session whose project directory no longer exists is still continued, from the current directory.
"New session" starts in Neovim's current working directory, with no project picker.
Claude Code opens as the only window.

### A whole-conversation preview

The preview shows the whole conversation, never a capped or truncated slice of it, however large the session is.
A custom script translates the session's `.jsonl` into markdown for the preview.
Tool calls and their results do not bury the dialogue.
The preview exists so a session can be recognized before it is entered.

### Fast to open

Opening stays fast however many sessions exist.
A cache or background index is part of the finder, not machinery to avoid.

### Borrowed logic, not borrowed breadth

The finder's logic and UI come from the BeastVim finder.
The behavior and the look are carried over; BeastVim's other sources are not.
VimClaude keeps its own trimmed copy and does not depend on BeastVim's finder.
Small means no code for sources that do not exist here; it does not mean no index.

### Scope

It is a Neovim configuration for Claude Code, not a general-purpose one; BeastVim remains that.
It is not a Claude Code client, a chat interface, or a panel that hosts Claude Code beside the editor.
It is not a file finder, a grep tool, or a second copy of BeastVim.
The feature set is allowed to be one feature.

A change aligns when it makes a session easier to find, continue, or start across all projects, using the one source.
A change should be resisted when it adds a second source, writes to the session store, searches transcript text, hides or groups sessions, truncates the preview, or couples the finder to BeastVim.
