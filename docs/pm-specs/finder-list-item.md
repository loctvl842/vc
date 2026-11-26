---
name: finder-list-item
description: Session list items that show where you left off - full folder path, the recap when there is one, and your last message in full - all searchable
generated: 2026-11-26
---

# Summary
Each session in the finder list shows enough to recognise it without opening it: its title, the full folder it ran in, the session recap when Claude Code wrote one, and the last thing the user said. Messages are shown in full, wrapped over as many lines as they need, and everything shown can be searched.

---

# Problem

Today a list item is a title and the last folder name. Titles are written by Claude Code from the first messages, so two sessions about the same topic look identical, and the folder name alone does not say which of two `api-server` folders it was. To tell sessions apart the user has to move down the list and read each preview. The one thing that answers "where did I leave off?" - the last thing they asked, or the recap Claude Code wrote - is not visible at all, and cannot be searched.

## Why now
The finder is the way back into every session. The longer the list, the more a wrong guess costs: pick the wrong session, read the preview, go back, try the next one. Showing where each session ended makes the right pick in one look.

---

# Target Behavior

Only the left-hand list changes; the preview on the right is as it is today. The panels below show the list alone, 50 columns wide.

```
STATE 1 - Opened, first session selected (shown in full):
┌ Claude Sessions ─────────────────────────────────┐
│ > _                                       3 / 12 │
├──────────────────────────────────────────────────┤
│▌ Fix flaky login test                            │
│    ~/work/api-server · main · #8   2m ago  34 msg│
│    Recap › You were fixing the flaky login test. │
│            The cause is a fixed 200ms wait before│
│            the assertion. Next step: replace it  │
│            with a poll and push the branch.      │
│    You   › ok replace the wait with polling, and │
│            then push the branch                  │
│                                                  │
│  Draft Q4 roadmap outline                        │
│    ~/notes                         1h ago  12 msg│
│    You   › turn the outline into three bullets   │
│            per quarter, keep it under a page, and│
│            then send it to Dana so she can revie…│
│                                                  │
│  Old prototype                                   │
│    ~/old/proto (folder gone)       3mo ago  7 msg│
│    You   › does this still build?                │
└──────────────────────────────────────────────────┘

  Row order for one session:
    title
    folder (home as ~) · branch · PR        age   messages
    Recap › what Claude Code wrote (only when the session has one)
    You   › the last thing you asked
  The selected session shows its messages in full. The others show
  at most 3 lines per message, ending with "…" when there is more.
```

```
─────────────────────────────────────────
STATE 2 - Selection moves down: the long message opens, the first one folds:
┌ Claude Sessions ─────────────────────────────────┐
│ > _                                       3 / 12 │
├──────────────────────────────────────────────────┤
│  Fix flaky login test                            │
│    ~/work/api-server · main · #8   2m ago  34 msg│
│    Recap › You were fixing the flaky login test. │
│            The cause is a fixed 200ms wait before│
│            the assertion. Next step: replace it… │
│    You   › ok replace the wait with polling, and │
│            then push the branch                  │
│                                                  │
│▌ Draft Q4 roadmap outline                        │
│    ~/notes                         1h ago  12 msg│
│    You   › turn the outline into three bullets   │
│            per quarter, keep it under a page, and│
│            then send it to Dana so she can review│
│            it before Friday's planning sync      │
│                                                  │
│  Old prototype                                   │
│    ~/old/proto (folder gone)       3mo ago  7 msg│
│    You   › does this still build?                │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 3 - Query "dana": found by what the user wrote, match marked with ^:
┌ Claude Sessions ─────────────────────────────────┐
│ > dana_                                   1 / 12 │
├──────────────────────────────────────────────────┤
│▌ Draft Q4 roadmap outline                        │
│    ~/notes                         1h ago  12 msg│
│    You   › turn the outline into three bullets   │
│            per quarter, keep it under a page, and│
│            then send it to Dana so she can review│
│                            ^^^^                  │
│            it before Friday's planning sync      │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 4 - Query "polling": the recap has no "polling", the last message does:
┌ Claude Sessions ─────────────────────────────────┐
│ > polling_                                1 / 12 │
├──────────────────────────────────────────────────┤
│▌ Fix flaky login test                            │
│    ~/work/api-server · main · #8   2m ago  34 msg│
│    Recap › You were fixing the flaky login test. │
│            The cause is a fixed 200ms wait before│
│            the assertion. Next step: replace it  │
│            with a poll and push the branch.      │
│    You   › ok replace the wait with polling, and │
│                                     ^^^^^^^      │
│            then push the branch                  │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 5 - A narrow list (34 columns): everything wraps further, nothing is lost:
┌ Claude Sessions ─────────────────┐
│ > _                       1 / 12 │
├──────────────────────────────────┤
│▌ Fix flaky login test            │
│    …-server · main 2m ago  34 msg│
│    Recap › You were fixing the   │
│            flaky login test. The │
│            cause is a fixed 200ms│
│            wait before the       │
│            assertion. Next step: │
│            replace it with a poll│
│            and push the branch.  │
│    You   › ok replace the wait   │
│            with polling, and then│
│            push the branch       │
└──────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 6 - A session with no recap and no message of its own (one-line item):
┌ Claude Sessions ─────────────────────────────────┐
│ > _                                       1 / 12 │
├──────────────────────────────────────────────────┤
│▌ Untitled scratch session                        │
│    ~/scratch                        2d ago  1 msg│
└──────────────────────────────────────────────────┘
```

---

# Scenarios

## 1 - Pick a session by where it left off (happy path)

```
Step 1: The user opens the finder
  Every session shows title, full folder, and its last message.
  The first session also shows its recap, because it has one.
  Sessions without a recap have no recap line and no placeholder.

Step 2: The user reads the first two items
  "Fix flaky login test" ends with "replace the wait with polling,
  and then push the branch" - it is the one to continue.

Step 3: The user presses Enter
  The session continues in Claude Code, as today.
```

## 2 - Long messages open on selection

```
Step 1: The second session's last message is longer than 3 lines
  Unselected, it shows 3 lines ending with "…".

Step 2: The user moves the selection onto it
  The message opens to its full length, wrapped to the list width.
  The sessions below move down to make room.

Step 3: The user moves on
  It folds back to 3 lines.
```

## 3 - Find a session by something the user said

```
Step 1: The user types "dana"
  Only the session whose last message contains "Dana" remains.
  The match is highlighted inside the message, even on a wrapped line.

Step 2: The match sits beyond line 3 of an unselected session
  That message shows enough lines to include the match.
```

## 4 - Search matches the recap, but never loosely

```
Step 1: The user types "plan"
  Sessions whose recap or last message contain the letters p-l-a-n
  together (plan, planning) remain. Sessions whose title or folder
  loosely match "plan" (letters in order, as today) remain too.

Step 2: The user types "rmpl"
  A recap or message containing r, m, p and l scattered across
  its words does not match. Only the title and folder match loosely.
```

## 5 - A session with nothing of its own to show

```
Step 1: A session has no recap and no message the user wrote
  (for example it was only /clear or /resume commands)
  It shows two rows: title, and folder with age.
```

## 6 - Narrow list

```
Step 1: The finder opens in a small terminal
  Folders cut from the left ("…/jarvix-refactor-m4"), so the end
  of the path always stays visible. Messages wrap at the narrower
  width. The branch and PR stay; age and message count stay at right.
```

## 7 - Two folders with the same name

```
Step 1: ~/work/api-server and ~/old/api-server both have sessions
  Each shows its full path, so they can no longer be confused.

Step 2: The user types "old api"
  Only the session in ~/old/api-server remains.
```

## 8 - The folder is gone

```
Step 1: A session ran in a folder that has since been deleted
  Its folder row ends with "(folder gone)" in red, as today.
```

---

# Behavior Rules

- **Row order:** title; folder, branch, PR, age and message count; recap (if any); last message (if any). One blank row separates sessions.
- **Full messages:** a message is shown as written, wrapped at word boundaries to the list width. A very long word such as a URL is broken to fit. Line breaks and repeated spaces become single spaces.
- **Fold and open:** unselected sessions show at most 3 lines per message, ending with "…" when more exists. The selected session shows every line. If a selected session is taller than the list, it is cut with "…" at the bottom; the preview shows the whole conversation.
- **A match is never hidden:** when the typed text matches beyond line 3 of an unselected session, that message shows lines up to and including the match.
- **Last message:** the most recent message the user wrote. Messages that are only a command (/recap, /clear, /resume, ...) or only a tool answer do not count; the latest real message is used. It is hidden when there is none, or when it is identical to the title.
- **Recap:** shown only when Claude Code wrote one for the session, from `/recap` or automatically. The latest one is shown. No placeholder when there is none. A recap is the text as Claude Code wrote it; it is not marked as out of date.
- **Folder:** the full folder, home written as `~`. When too long it is cut from the left with "…" so the end stays visible. "(folder gone)" stays.
- **Branch and PR:** the last branch the session was on, hidden when unknown or detached. The PR number (`#8`) shows when the session is linked to a pull request.
- **Search:** each typed word must match somewhere. In the title and folder, letters may be spread, in order, as today. In the recap and last message, the typed word must appear contiguously as written (ignoring case unless the user typed a capital).
- **Highlight:** matches are highlighted wherever they appear, on wrapped lines too.
- **Unchanged:** the "New session" item, the preview, the key hints and the ordering by last activity.

---

# Decisions for you

1. **Fold the unselected, open the selected (recommended)** vs. show every message in full for every session. Full for all makes the list long: about 4 sessions per screen with long messages. The cost of folding is that rows below move when the selection moves.
2. **Chips: branch and PR (recommended)**, vs. also `+907 -60` lines changed. Lines changed says whether real work happened but adds width to a row that is already full.
3. **Recap above the last message (recommended)** vs. last message first. The recap is the broader answer; the last message is the exact stopping point.
4. **Recap without an age (recommended)** vs. "Recap · 2d ago". A recap older than the last messages can mislead, but the age adds noise to every row that has one.

---

# Success Criteria

- [ ] Every session shows its full folder path with the home folder as ~
- [ ] Two folders with the same name can be told apart in the list
- [ ] A session with a recap shows it in full; one without shows no recap line
- [ ] Each session shows the last real message the user wrote, in full
- [ ] A command-only message (/recap, /clear) is never shown as the last message
- [ ] Long messages wrap to the list width, over as many lines as they need
- [ ] The selected session shows all lines; the others show at most 3 and end with "…"
- [ ] Searching a word from a recap or a last message finds the session and highlights it
- [ ] Scattered letters do not match inside a recap or last message
- [ ] A match beyond line 3 of an unselected session is still visible
- [ ] Branch and PR show when known and are hidden otherwise
- [ ] A session with no recap and no message of its own shows two rows
- [ ] "(folder gone)", "New session" and the preview behave as before

---

# Out of Scope

- Lines added or removed, cost, duration and model - none of them helps choose a session; the preview header is a better home.
- Marking a recap as out of date, or showing its age - deferred; revisit if stale recaps mislead.
- Showing Claude's last answer in the list - the preview shows it.
- A key to open one session's text without selecting it.
- Generating a recap for sessions that have none.
- Sessions renamed with a custom name - none exist in the author's data yet.
