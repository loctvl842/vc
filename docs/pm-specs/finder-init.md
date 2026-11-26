---
name: finder-init
description: A single finder over every Claude Code session on the machine - find one by what it is, preview the whole conversation, continue it or start a new one
generated: 2026-11-26
---

# Summary
One finder lists every Claude Code session from every project in a single list ordered by last activity. Typing narrows the list, the preview shows the whole conversation, and Enter drops the user into that session in Claude Code. The user only ever sees one of two things: the finder or Claude Code. There is no editor view in between, and when Claude Code quits the finder is back.

---

# Problem

Someone who uses Claude Code all day across many projects ends up with hundreds of past sessions. Today a session is only reachable through the project it was started in, and it is named by an opaque id. To get back to "that conversation about the login bug from Tuesday" the user has to remember which project it was in, change to that folder, and scroll a short list of cryptic entries, opening several to find the right one.

## Why now
The author works in Claude Code every day and every lookup breaks flow. A cross-project finder is the one thing this configuration exists to provide; nothing else is built before it.

---

# Target Behavior

Launching VimClaude opens the finder full-screen: query line on top, session list on the left, conversation preview on the right, key hints at the bottom.

```
STATE 1 - Opened, empty query:
┌ Claude Sessions ─────────────────────────────────────────────────────────────┐
│ > _                                                                 12 / 12  │
├──────────────────────────────────────────┬───────────────────────────────────┤
│ ▌+ New session                           │ New session                       │
│  Fix flaky login test                    │                                   │
│    api-server            2m ago   34 msg │ Starts a fresh Claude Code        │
│  Draft Q4 roadmap outline                │ session in                        │
│    notes                 1h ago   12 msg │ ~/work/api-server                 │
│  Why is the build slow on CI             │                                   │
│    web-app               3h ago   58 msg │                                   │
│  Migrate users table to uuid             │                                   │
│    api-server            yesterday 91 msg│                                   │
│  ...                                     │                                   │
├──────────────────────────────────────────┴───────────────────────────────────┤
│ <CR> continue   <C-n>/<C-p> move   <Esc> exit                                │
└──────────────────────────────────────────────────────────────────────────────┘

─────────────────────────────────────────
STATE 2 - Query typed ("login"):
┌ Claude Sessions ─────────────────────────────────────────────────────────────┐
│ > login_                                                             2 / 12  │
├──────────────────────────────────────────┬───────────────────────────────────┤
│ ▌Fix flaky login test                    │ You                               │
│    api-server            2m ago   34 msg │ The login test fails one run in   │
│  Add SSO login to admin panel            │ five on CI, can you find why?     │
│    web-app               5d ago   41 msg │                                   │
│                                          │ Claude                            │
│                                          │ Let me look at the test first.    │
│                                          │ ▸ 4 tool calls                    │
│                                          │ It waits a fixed 200ms for the... │
│                                          │ (scrolls - whole conversation)    │
├──────────────────────────────────────────┴───────────────────────────────────┤
│ <CR> continue   <C-n>/<C-p> move   <Esc> exit                               │
└──────────────────────────────────────────────────────────────────────────────┘
(no "New session" row - a query removes it)

─────────────────────────────────────────
STATE 3 - Nothing matches ("zzz"):
┌ Claude Sessions ─────────────────────────────────────────────────────────────┐
│ > zzz_                                                               0 / 12  │
├──────────────────────────────────────────┬───────────────────────────────────┤
│  No sessions match "zzz"                 │                                   │
├──────────────────────────────────────────┴───────────────────────────────────┤
│ <Esc> exit                                                                  │
└──────────────────────────────────────────────────────────────────────────────┘

─────────────────────────────────────────
STATE 4 - Enter on a session:
┌──────────────────────────────────────────────────────────────────────────────┐
│ Claude Code - continuing "Fix flaky login test"                              │
│ ~/work/api-server                                                            │
│ (Claude Code is the only window; the finder is hidden behind it)         │
│ Ctrl-C quits Claude Code and the finder is back, ready to browse again       │
└──────────────────────────────────────────────────────────────────────────────┘

─────────────────────────────────────────
STATE 5 - Session whose project folder no longer exists:
  List row:     Old prototype            (folder gone)   3mo ago   17 msg
  After Enter:  Claude Code opens the session from the current directory,
                with a one-line notice "Original folder ~/work/proto is gone,
                continuing from ~/work/api-server".
```

Each row shows: a title that says what the session is about, the project it belongs to, when it was last active, and how many messages it has.

---

# Scenarios

## 1 - Find and continue a past session (happy path)

```
Step 1: User launches VimClaude
  The finder is already open. List shows "New session" first, then every session from every project,
  most recently active on top. First row is highlighted.

Step 2: User types "login"
  List narrows to sessions whose title or project contains "login".
  "New session" row disappears. First match is highlighted and its whole
  conversation appears in the preview.

Step 3: User moves down to the second match with <C-n>
  Preview switches to that conversation.

Step 4: User presses Enter
  Finder closes. Claude Code opens as the only window, continuing that session.
```

## 2 - Start a new session

```
Step 1: User launches VimClaude
  The finder is already open. "New session" is the highlighted first row. Preview says where it will start.

Step 2: User presses Enter
  Claude Code opens as the only window, empty, in Neovim's current directory.
  No project is asked for.
```

## 3 - Recognize a session by reading its preview

```
Step 1: User highlights a long session (91 messages)
  Preview shows the conversation from its first message.

Step 2: User scrolls the preview to the end
  Every turn is there, nothing cut off. Tool activity shows as one dim line
  per run of tool calls ("▸ 4 tool calls"), so the dialogue stays readable.

Step 3: User decides it is the wrong one, moves to another row
  Preview switches. Nothing has been changed on disk.
```

## 4 - No match

```
Step 1: User types "zzz"
  List is replaced by "No sessions match "zzz"". Preview is empty.
  Enter does nothing.

Step 2: User deletes characters until something matches
  List and preview come back; with the query fully cleared, "New session"
  returns as the first row.
```

## 5 - Session whose folder was deleted

```
Step 1: User highlights a row marked "(folder gone)"
  Row is still listed in its normal place by last activity.

Step 2: User presses Enter
  Claude Code opens that session from the current directory and shows a
  one-line notice naming the missing folder.
```

## 6 - Exit

```
Step 1: User is in the finder (any query) and presses Esc
  VimClaude exits and the user is back at their shell. Nothing was changed.
  (This is the only way out; there is no editor view to fall back to.)
```

## 7 - Many sessions

```
Step 1: User has thousands of sessions and launches VimClaude
  The list appears right away, without waiting for a scan to finish.

Step 2: User starts a new session elsewhere, then returns to the finder
  The new session is in the list, on top.
```

## 8 - Quit Claude Code and keep browsing

```
Step 1: User is in a Claude Code session opened from the finder
  Claude Code is the only window.

Step 2: User presses Ctrl-C to quit Claude Code
  Claude Code closes and the finder is shown again automatically with an
  empty query, "New session" first, the list refreshed (the session just
  used is now on top). The user never has to open the finder by hand.

Step 3: User picks another session, or presses Esc
  Another pick continues that session. Esc exits VimClaude.
```

---

# Behavior Rules

- One flat list ordered by last activity, newest first. No project headers, no grouping, nothing hidden (empty or tiny sessions are listed too).
- Covers every project on the machine, never only the current one.
- The query matches what a row shows (title, project name); it never searches inside conversation text.
- "New session" is the first row only while the query is empty. Any query removes it; clearing the query brings it back.
- The first row is highlighted when the finder opens and after every query change.
- Enter on a session continues it; Enter on "New session" starts a fresh one in Neovim's current directory.
- Enter with no rows (no match) does nothing.
- A session whose project folder is gone is still listed and continued, from the current directory, with a notice.
- The preview always shows the whole conversation. Tool calls and results collapse to a dim summary line so dialogue stays readable.
- The finder is read-only: no delete, rename, or edit of any session, anywhere in the UI.
- The user only ever sees one of two things: the finder or Claude Code. There is no editor view and no command to open the finder by hand.
- When the user is not in Claude Code, the finder is showing. Quitting Claude Code (Ctrl-C) shows the finder again automatically, with an empty query and a refreshed list.
- Esc in the finder exits VimClaude.
- The finder appears fast regardless of session count, and sessions started elsewhere show up the next time it is opened.

---

# Success Criteria

- [ ] Opening the finder shows sessions from all projects in one list, newest first
- [ ] "New session" is first with an empty query, and absent as soon as anything is typed
- [ ] Typing narrows the list by title or project; the preview follows the highlighted row
- [ ] The preview of a very long session can be scrolled to its final message
- [ ] Tool calls do not bury the dialogue in the preview
- [ ] Enter on a session opens Claude Code, as the only window, in that session
- [ ] Enter on "New session" opens a fresh session in the current directory
- [ ] A session with a deleted folder continues from the current directory with a notice
- [ ] Esc exits VimClaude and changes nothing
- [ ] Launching VimClaude shows the finder immediately; no manual open step exists
- [ ] Quitting Claude Code with Ctrl-C brings the finder back, refreshed, so the user can keep browsing
- [ ] At no point is an editor buffer visible
- [ ] The finder appears instantly with thousands of sessions
- [ ] No action in the finder alters any session

---

# Out of Scope

- Searching inside conversation text - the query matches what a row shows, by design
- Grouping or filtering by project, hiding "boring" sessions - one flat list is the point
- Delete, rename, edit, or tag sessions - the finder never writes
- Any source besides Claude Code sessions (files, grep, other agents' sessions)
- A project picker for "New session" - it starts where Neovim is
- An editor view or any third screen; Claude Code beside the editor or as a chat panel
