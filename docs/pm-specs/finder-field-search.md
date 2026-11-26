---
name: finder-field-search
description: Narrow the session list to one part of a session by typing field:word in the search box, e.g. cwd:jarvix title:nvim, then search the rest as usual
generated: 2026-11-27
---

# Summary
The search box accepts `field:word` terms that narrow the list by one specific part of a session (its folder, title, branch, PR, recap or last message). Whatever is left of the query searches the remaining sessions exactly as it does today.

---

# Problem

Today every typed word is looked for in the title, the folder, the recap and the last message at once. Typing `jarvix` finds sessions in the `jarvix` folder, but also every session whose recap or last message happens to mention jarvix, and a long list stays long. A user who knows "it was in the jarvix project, and it was about nvim" cannot say so. They type both words, get a mix of both kinds of match, and have to scan the list to tell them apart.

## Why now
The list now shows folder, branch, PR, recap and last message for each session, and all of it is searchable. More searchable text means more accidental matches. Letting the user say which part a word belongs to makes the list shorter without making it any harder to type.

---

# Target Behavior

Only the search box and the list change. A recognised `field:` prefix is drawn in its own colour (shown here as `[cwd:]`) so the user can see it was understood. The counter at the right of the box shows matches / all sessions, as today.

```
STATE 1 - Opened, nothing typed (as today):
┌ Claude Sessions ─────────────────────────────────┐
│ > _                                      12 / 12 │
├──────────────────────────────────────────────────┤
│▌ Fix flaky login test                            │
│    ~/work/jarvix · main · #8       2m ago  34 msg│
│    You   › replace the wait with polling         │
│                                                  │
│  Tune nvim startup time                          │
│    ~/work/jarvix · perf            1d ago  21 msg│
│    You   › profile it with --startuptime         │
│                                                  │
│  Fix nvim statusline colours                     │
│    ~/dotfiles                      3d ago   9 msg│
│    You   › jarvix uses the same palette, copy it │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 2 - One field term: cwd:jarvix
Only sessions whose folder matches "jarvix" remain. The third session
above is gone: "jarvix" is only in its message, not its folder.
┌ Claude Sessions ─────────────────────────────────┐
│ > [cwd:]jarvix_                           2 / 12 │
├──────────────────────────────────────────────────┤
│▌ Fix flaky login test                            │
│    ~/work/jarvix · main · #8       2m ago  34 msg│
│           ^^^^^^                                 │
│    You   › replace the wait with polling         │
│                                                  │
│  Tune nvim startup time                          │
│    ~/work/jarvix · perf            1d ago  21 msg│
│           ^^^^^^                                 │
│    You   › profile it with --startuptime         │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 3 - Two field terms plus a normal query: cwd:jarvix title:nvim startup
cwd narrows first, then title, then "startup" searches what is left
(title, folder, recap and last message, as today).
┌ Claude Sessions ─────────────────────────────────┐
│ > [cwd:]jarvix [title:]nvim startup_      1 / 12 │
├──────────────────────────────────────────────────┤
│▌ Tune nvim startup time                          │
│       ^^^^ ^^^^^^^                               │
│    ~/work/jarvix · perf            1d ago  21 msg│
│           ^^^^^^                                 │
│    You   › profile it with --startuptime         │
│                              ^^^^^^^             │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 4 - Field terms only, no normal query: cwd:jarvix title:nvim
Remaining sessions keep the usual order, latest activity first.
┌ Claude Sessions ─────────────────────────────────┐
│ > [cwd:]jarvix [title:]nvim_              1 / 12 │
├──────────────────────────────────────────────────┤
│▌ Tune nvim startup time                          │
│    ~/work/jarvix · perf            1d ago  21 msg│
│    You   › profile it with --startuptime         │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 5 - Nothing satisfies every term: cwd:jarvix title:docker
┌ Claude Sessions ─────────────────────────────────┐
│ > [cwd:]jarvix [title:]docker_            0 / 12 │
├──────────────────────────────────────────────────┤
│                                                  │
│    No sessions match "cwd:jarvix title:docker"   │
│                                                  │
└──────────────────────────────────────────────────┘
```

```
─────────────────────────────────────────
STATE 6 - Typing in progress and unknown names (nothing is narrowed):
  > cwd:_              "cwd:" has no word yet. Nothing is narrowed,
                       the list is the full list.
  > cwd:j_             Narrowed as soon as one letter follows the colon.
  > ticket:42_         "ticket" is not a field, so "ticket:42" is
                       searched as ordinary text, as today.
  > title:"fix log"_   A phrase with spaces goes in double quotes.
```

```
─────────────────────────────────────────
Fields you can use:

  cwd:     the folder the session ran in (the full path as shown)
  title:   the session title
  branch:  the last git branch the session was on
  pr:      the pull request number, with or without the #  (pr:8)
  recap:   the recap Claude Code wrote
  msg:     the last thing you wrote in the session
```

---

# Scenarios

## 1 - Narrow by folder, then by title (happy path)

```
Step 1: The user opens the finder
  12 sessions, newest first.

Step 2: The user types "cwd:jarvix"
  "cwd:" turns the field colour as soon as the colon is typed. Once
  "jarvix" follows, 2 sessions remain: those whose folder matches.
  The match is highlighted in the folder row.

Step 3: The user continues with " title:nvim"
  Of those 2, only the session whose title matches "nvim" remains.

Step 4: The user presses Enter
  The session continues in Claude Code, as today.
```

## 2 - Field terms plus a normal query

```
Step 1: The user types "cwd:jarvix startup"
  Sessions in a jarvix folder remain. "startup" is then searched in
  their title, folder, recap and last message, exactly as it would be
  without the field term. Best matches come first.

Step 2: The user types the normal word first: "startup cwd:jarvix"
  Same result. The order of terms in the box does not matter, and a
  field term can sit anywhere.
```

## 3 - Same word, with and without a field

```
Step 1: The user types "jarvix"
  Sessions with jarvix in the folder, title, recap or last message.
  The session about nvim palettes that only mentions jarvix in its
  last message is in the list.

Step 2: The user types "cwd:jarvix"
  That session leaves the list. Only folder matches remain.
```

## 4 - Two terms for the same field

```
Step 1: The user types "cwd:work cwd:jarvix"
  Both must match the folder. ~/work/jarvix remains;
  ~/work/api-server and ~/old/jarvix do not.
```

## 5 - Nothing matches

```
Step 1: The user types "cwd:jarvix title:docker"
  The list is empty and the counter reads 0 / 12.

Step 2: The user deletes "title:docker"
  The two jarvix sessions are back.
```

## 6 - Typing a term letter by letter

```
Step 1: The user types "c", "cw", "cwd"
  Ordinary search: nothing special yet.

Step 2: The user types ":"
  "cwd:" has no word after it, so the list does not change. The
  prefix switches to the field colour: it was recognised.

Step 3: The user types "j"
  The list narrows to sessions whose folder matches "j".
```

## 7 - Not a field

```
Step 1: The user types "ticket:42"
  "ticket" is not a field name, so "ticket:42" is searched as plain
  text across title, folder, recap and last message, as today.
  The word stays in the normal colour: nothing was recognised.

Step 2: The user types a URL "https://example.com"
  "https" is not a field name. It is searched as plain text.
```

## 8 - A phrase with spaces

```
Step 1: The user types title:fix login
  "login" is a separate normal word, because a space ends the value.
  The list shows sessions whose title matches "fix" and which also
  mention "login" anywhere.

Step 2: The user types title:"fix login"
  Now both words must match together in the title:
  "Fix flaky login test" does NOT match, "Fix login redirect" does.
```

## 9 - Match style follows the field

```
Step 1: The user types "title:nvm"
  Titles match loosely, letters in order, as today:
  "Tune nvim startup time" matches (n, v, then m of "nvim"),
  and so does "Nested virtual machine notes".

Step 2: The user types "msg:nvm"
  Last messages match only when "nvm" appears as written.
  A message with "nvim" does not match; one with "nvm use 20" does.
```

## 10 - Case

```
Step 1: The user types "cwd:Jarvix"
  A capital letter makes the term case sensitive, as in normal search.
  ~/work/jarvix does not match; ~/work/Jarvix does.

Step 2: The user types "cwd:jarvix"
  Both match.
```

---

# Behavior Rules

- **Shape of a term:** `field:value`, written with no space around the colon. The value ends at the next space, or at the closing quote when it starts with a double quote.
- **Fields:** `cwd`, `title`, `branch`, `pr`, `recap`, `msg`. Names are lowercase. Any other word before a colon is ordinary text.
- **Every term must match:** field terms and normal words combine with AND. The order of terms in the box does not change the result.
- **Narrowing order:** field terms narrow the list first; the normal words then search what is left. Ranking comes only from the normal words. With no normal words, the order is latest activity first.
- **Match style per field:** `cwd` and `title` match letters spread in order, as folder and title do today. `branch`, `recap` and `msg` match the value as written, contiguous. `pr` matches the number exactly: `pr:8` finds #8, not #80.
- **Case:** lowercase value ignores case; a value with a capital letter is case sensitive, as today.
- **Empty value:** `cwd:` with nothing after it narrows nothing. Nothing is hidden while the user is half-way through typing a term.
- **Same field twice:** both terms must match that field.
- **Sessions with no value for a field:** a session with no recap never matches `recap:x`; one with no branch or PR never matches `branch:x` or `pr:x`.
- **Highlight:** the matched letters are highlighted inside the field they matched, on wrapped lines too. The `field:` prefix has its own colour only when the name is recognised.
- **Counter and empty state:** the counter counts sessions that satisfy every term. When none do, the list shows whatever a normal search with no hits shows today.
- **Unchanged:** the "New session" item, the preview, the key hints, and how a query without any field term behaves, character for character.

---

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

---

# Out of Scope

- **Negation** (`-cwd:work`, `NOT`): not asked for; can be added without changing this syntax.
- **OR between terms** and grouping: every term is an AND, as today.
- **Date and size fields** (`after:`, `msgs:>20`): need their own value syntax.
- **Field-name completion or a hint popup:** the coloured prefix is the only feedback for now.
- **A project-wide search of every folder at once** or changing which sessions are listed: only narrowing of the existing list.
- **Saving a query or setting a default field filter:** each opening of the finder starts empty, as today.
