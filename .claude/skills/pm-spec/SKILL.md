---
name: pm-spec
description: "Generate a product spec (UI/UX design, behavior, scenarios) for a feature as a .md plus an HTML review page the user can annotate and approve. Use when asked to 'pm spec', 'product spec', 'design the feature', 'write a spec', 'what should this look like', 'UX for'."
---

# PM Spec

Generate a product spec that describes what a feature looks, feels, and behaves like - from the user's perspective. No implementation details.

Every PM spec ships as a pair of files:

| File | For | Purpose |
|---|---|---|
| `docs/pm-specs/<name>.md` | the agent | Source of truth. Exact and complete. |
| `docs/pm-specs/<name>.html` | the human | Visual review copy, opened in the browser to annotate and approve. |

If they disagree, the `.md` wins, so fix the `.html`.

## Input

The user provides a feature idea - either as text, a rough description, or a reference to existing behavior. If the description is too vague to spec, ask one focused question to unblock.

## Step 1: Read Existing Context

Before designing:
- Read `docs/CODEMAP/INDEX.md` - understand what already exists so the spec doesn't redesign something that's there
- Skim `docs/pm-specs/` if it exists - check for related or superseded specs

## Step 2: Generate the PM Spec

Produce a structured spec with this format:

> **Note:** The template below is indented for readability inside this code fence. When generating the actual file, write all content at the root level - no leading spaces.

`````markdown
    ---
    name: [feature-name]
    description: [one-line feature summary]
    generated: YYYY-mm-dd
    ---

    # Summary
    [1-2 sentences: what this feature does and why it exists]

    ---

    # Problem

    [What frustrates the user today? Describe the gap concretely - what they have to do now, what breaks or feels wrong. No jargon. Write so someone who has never opened Neovim understands the pain.]

    ## Why now
    [Why does this need to exist? What gets unlocked or unblocked?]

    ---

    # Target Behavior

    [ASCII diagram(s) of the end state. Show exactly what the user sees on screen - buffer content, floating windows, highlights, statusline, etc. Use concrete text, not labels like "item list here".]

    ```
    ┌─────────────────────────────────────────┐
    │  [exact UI content]                     │
    │  [second line]                          │
    └─────────────────────────────────────────┘
    ```

    Use multiple STATE blocks when the UI has distinct modes:

    ```
    STATE 1 - [label]:
      [what the user sees]

    ─────────────────────────────────────────
    STATE 2 - [label]:
      [what the user sees]
    ```

    ---

    # Scenarios

    Walk through every meaningful case step by step. Each scenario must be numbered and titled. Cover: the happy path, at least one edge case, and any cancellation/error path.

    ## 1 - [Scenario name]

    ```
    Step 1: [what the user does]
      [what they see]

    Step 2: [what they do next]
      [what they see]

    Step 3: [outcome]
      [what they see]
    ```

    ## 2 - [Scenario name]
    ...

    ---

    # Behavior Rules

    Bullet list of specific rules that aren't obvious from the scenarios:
    - [Rule 1]
    - [Rule 2]

    ---

    # Success Criteria

    What the user experiences when the feature is done correctly:
    - [ ] [Observable outcome 1]
    - [ ] [Observable outcome 2]

    ---

    # Out of Scope

    - [Thing not included - and why deferred]
    - [Another thing]
`````

### Rules for the PM Spec

- **User language only** - no file paths, function names, module names, or implementation words
- **Show, don't describe** - every UI claim needs an ASCII diagram to back it up
- **Scenarios are mandatory** - at least one happy path and one edge/error case
- **No code yet** - this step produces only design, not architecture
- **Metadata header is mandatory** - include `name`, `description`, and `generated` at the top; set `generated` to the current date when the spec is created

## Step 3: Save the PM Spec (.md)

Save the spec under `docs/pm-specs/` (create the directory if needed) using kebab-case:

- **When creating a new module**: `docs/pm-specs/<module>-init.md`
- **Follow-up work in an existing module**: `docs/pm-specs/<module>-<feature>.md`
- **Non-module / cross-module work**: `docs/pm-specs/cross-<feature>.md`

## Step 4: Generate the HTML Review Copy (MANDATORY)

Write `docs/pm-specs/<name>.html` next to the `.md`, same stem. The `.md` is the source of truth; the `.html` is the copy the user reads, so optimize it for fast understanding, not completeness.

Read `.claude/skills/_spec-review/html-guide.md` first. In short:
- Same spec as the `.md` (same sections, decisions, file paths). Wording and detail may differ. Do not paste the `.md` into the page.
- Put a stable `data-spec="<id>"` on every reviewable block, matching a section of the `.md`. Review notes arrive tagged with it.
- One self-contained file, light and dark theme, works at phone width.

## Step 5: Review Loop With the User

The user reviews the page in the browser, annotates it, and can approve. Scripts are Python standard library only and serve on 127.0.0.1:

```sh
R=.claude/skills/_spec-review/scripts/review.py
F=docs/pm-specs/<name>.html
python3 $R serve "$F" --open   # run in the background; prints the URL
python3 $R poll  "$F"          # blocks until the user sends feedback or approves
python3 $R reply "$F" "what changed"
python3 $R stop  "$F"
```

1. Start `serve` as a background command and tell the user the URL.
2. Run `poll` (background, or foreground with a long timeout) and **STOP working until it returns**. The user clicks elements or selects text, queues notes, and presses "Send to agent". `poll` prints each note with its `spec` id, CSS selector, quoted text and note, plus any general message.
3. Per round: edit the **`.md` first**, then the `.html` (keep `data-spec` ids; saving reloads the page). Then `reply` with a short summary and `poll` again.
4. `review: approved` means the user pressed "Approve spec". Run `stop`.

Notes:
- State lives in `docs/pm-specs/.review/` (self-gitignored).
- If the script cannot run, do not skip the page: give the user the `.html` path and take feedback in chat.
- `review: waiting (no feedback yet)` is a timeout, not approval; poll again.

## Step 6: Confirm

Tell the user both files are saved (give both paths) and **STOP**. Do not proceed (no `/dev-spec`) until the user confirms or `review: approved` arrives.

If the user wants changes (in chat or as annotations):
- "modify: [changes]" -> update the `.md`, then the `.html`
- "add scenario: [description]" -> add it to both
- "simplify" -> trim both to the essential happy path

## Tips

- If the feature has no visible UI (e.g., a performance improvement), the Target Behavior section shows the *result* the user notices, not the internal change
- One spec per feature - if two features share a spec they'll likely conflict in the dev phase
- Mockups in the HTML are the ASCII diagrams from the `.md` rendered as styled panels, one per STATE, so reviewers can annotate each one
- The scenarios here become the manual verification checklist in the dev spec
