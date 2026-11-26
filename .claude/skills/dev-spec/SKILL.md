---
name: dev-spec
description: "Generate a dev spec (implementation blueprint) from a PM spec as a .md plus an HTML review page the user can annotate and approve. Use when asked to 'dev spec', 'implementation plan', 'break down this spec', 'plan implementation', 'how to implement this', 'dev plan from spec'."
---

# Dev Spec

Generate a detailed implementation blueprint from an existing PM spec.

Every dev spec ships as a pair of files:

| File | For | Purpose |
|---|---|---|
| `docs/dev-specs/<name>.md` | the agent | Source of truth for implementation. `implement-spec` reads this. |
| `docs/dev-specs/<name>.html` | the human | Visual review copy, opened in the browser to annotate and approve. |

If they disagree, the `.md` wins, so fix the `.html`. Never implement from the `.html` alone.

## Input

The user provides a PM spec file path (e.g., `docs/pm-specs/key-hint-popup.md`). If no PM spec is provided, ask for one - or suggest running `/pm-spec` first.

## Step 1: Read the PM Spec

Read the PM spec in full. Extract:
- **Goal** - What are we building and why?
- **Behavior rules** - What must the implementation honour?
- **Success criteria** - The user-facing outcomes that define "done"
- **Out of scope** - What are we NOT building?

The PM spec is the source of truth. If anything in the PM spec is ambiguous or contradicts a known technical constraint, flag it before proceeding.

## Step 2: Read the Codemap

Check if `docs/CODEMAP/INDEX.md` exists:
- **If yes** → read the relevant codemap files to understand the existing architecture
- **If no** → run the `update-codemap` skill first to generate them, then read the results

## Step 3: Research Before Building (MANDATORY)

Before writing the dev spec, search for existing solutions. Don't reinvent the wheel.

**This step is NOT optional.** You MUST perform the searches below and include a `## Research` section in the dev spec with your findings. If you skip this step, the dev spec is incomplete and must not proceed to implementation.

### 3a: Search the Repo
- Grep for related function names, module names, keywords
- Check the shared/util modules listed in `docs/CODEMAP/` for existing utilities
- Check existing tests and scripts - they reveal existing patterns
- **Log what you searched for and what you found** (even if nothing)

If the functionality already exists, **reuse it**.

### 3b: Check Built-ins and Existing Modules

VimClaude is a Neovim config for working with Claude Code. Before building, check:

| Source | Where to look |
|---|---|
| Neovim built-in APIs | `vim.api`, `vim.fn`, `vim.ui`, `vim.lsp`, `vim.treesitter` |
| Existing modules | the shared modules listed in `docs/CODEMAP/` |
| Claude Code CLI | its flags, hooks, settings, and IDE/MCP integration (check the installed CLI and its docs, do not rely on memory) |
| Lua standard library | `string`, `table`, `math`, `io` |

### 3c: Decide and Document
| Signal | Action |
|---|---|
| Built-in Neovim API covers it | **Use** - no new code needed |
| Existing module covers it | **Reuse** - call or extend the existing module |
| Nothing suitable | **Build** - write custom, informed by research |

### 3d: Required Research Section Format
The dev spec MUST include this section with actual search results:

```markdown
## Research

### Repo Search
- Searched for: [keywords/patterns you grepped]
- Found: [what you found, or "No existing code covers this"]
- Reuse opportunity: [Yes/No - what to reuse]

### Built-in / Existing Module Check
- Checked: [Neovim APIs, existing modules, or Claude Code features evaluated]
- Found: [what applies, or "Nothing suitable"]
- Decision: **Use** / **Reuse** / **Build** - [reason]
```

## Step 4: Generate the Dev Spec

Produce a structured dev spec with this format:

> **Note:** The template below is indented for readability inside this code fence. When generating the actual file, write all content at the root level - no leading spaces.

```markdown
    ---
    name: [feature-name]
    description: [one-line implementation summary]
    generated: YYYY-mm-dd
    ---

    > PM Spec: [docs/pm-specs/<spec-name>.md](../pm-specs/<spec-name>.md)

    # Summary
    [2-3 sentences: what we're building and the implementation approach]

    ---

    # Context

    ## Problem
    [One paragraph - the technical gap that needs to be filled. Derived from the PM spec but framed for an engineer: what module is missing, what behaviour is unimplemented, what the code lacks.]

    ### Solution
    [What will the codebase look like after this change? One short paragraph - no code yet.]

    ---

    # Research
    [From Step 3 - actual search results, not placeholders]

    ---

    # Architecture Changes
    - [New/modified file: path - what and why]
    - [New/modified file: path - what and why]

    ## Implementation Phases

    ## Phase 1: [Name] - [Goal of this phase]
    1. **[Step]** (File: path/to/file)
       - Action: [Specific action]
       - Why: [Reason]
       - Depends on: None / Step N
       - Risk: Low/Medium/High

    2. **[Step]** (File: path/to/file)
       ...

    ## Phase 2: [Name] - [Goal]
    ...

    # Testing Strategy
    - Headless tests: [which existing tests to run, or which to write, using the project's test command]
    - Bench: [which bench script to run if a hot-path module was touched, or "n/a"]
    - Manual: [reference the scenarios in the PM spec - what to open in nvim and verify]

    # Success Criteria
    [Copy from the PM spec's success criteria, adding any technical gates]
    - [ ] Criterion 1
    - [ ] Criterion 2
```

### Rules for the Dev Spec

- **Exact file paths** - Use real paths from the codebase, not placeholders.
- **Independent phases** - Each phase should be mergeable on its own.
- **Smallest first** - Phase 1 is the minimum viable slice.
- **Follow existing patterns** - Use the project's conventions (from codemap and codebase).
- **No code yet** - This step produces only the plan.
- **Always link the PM spec** - The `> PM Spec:` line at the top is mandatory.
- **Metadata header is mandatory** - include `name`, `description`, and `generated` at the top; set `generated` to the current date when the spec is created.

## Step 5: Save the Dev Spec (.md)

Save the dev spec under `docs/dev-specs/` using kebab-case:

- **When creating a new module**: `docs/dev-specs/<module>-init.md`
- **Follow-up work in an existing module**: `docs/dev-specs/<module>-<feature>.md`
- **Non-module / cross-module work**: `docs/dev-specs/cross-<feature>.md`

If a PM spec exists, keep the same filename stem between PM and dev specs.

## Step 6: Generate the HTML Review Copy (MANDATORY)

Write `docs/dev-specs/<name>.html` next to the `.md`, same stem. The `.md` is the source of truth; the `.html` is the copy the user reads, so optimize it for fast understanding, not completeness.

Read `.claude/skills/_spec-review/html-guide.md` first. In short:
- Same plan as the `.md` (same sections, decisions, file paths). Wording and detail may differ. Do not paste the `.md` into the page.
- Put a stable `data-spec="<id>"` on every reviewable block, matching a section of the `.md`. Review notes arrive tagged with it.
- One self-contained file, light and dark theme, works at phone width.

## Step 7: Review Loop With the User

The user reviews the page in the browser, annotates it, and can approve. Scripts are Python standard library only and serve on 127.0.0.1:

```sh
R=.claude/skills/_spec-review/scripts/review.py
F=docs/dev-specs/<name>.html
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
- State lives in `docs/dev-specs/.review/` (self-gitignored).
- If the script cannot run, do not skip the page: give the user the `.html` path and take feedback in chat.
- `review: waiting (no feedback yet)` is a timeout, not approval; poll again.

## Step 8: Confirm

Tell the user both files are saved (give both paths) and **STOP**. Do not proceed to implementation until the user confirms with "yes", "proceed", "go ahead", or `review: approved` arrives.

If the user wants changes (in chat or as annotations):
- "modify: [changes]" -> update the `.md`, then the `.html`
- "skip phase X" -> remove that phase from both
- "add [thing]" -> incorporate it into both

## Tips

- Keep Phase 1 to 1-3 files max - smallest deliverable slice
- Flag any PM spec gaps early (don't assume, ask)
- If the feature touches >5 files, consider splitting into multiple dev specs
- The PM spec's scenarios are the manual verification guide - reference them in Testing Strategy rather than duplicating them
