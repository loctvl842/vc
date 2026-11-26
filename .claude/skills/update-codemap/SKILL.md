---
name: update-codemap
description: "Scan VimClaude and regenerate token-lean architecture documentation under docs/CODEMAP/. Use when asked to 'update codemap', 'generate codemap', 'map the codebase', 'project architecture', 'save project context', 'what does this project look like'."
---

# Update Codemap - VimClaude

Generate token-lean architecture documentation that lets agents (and humans) look up project structure, navigate the require graph, and resume work quickly without re-reading the whole tree.

The output lives at `docs/CODEMAP/`. It must stay **token-lean** (each file under ~1000 tokens) and **shape-stable** so day-to-day diffs are meaningful.

## When to Use

- Starting work on an unfamiliar area of the codebase
- After a major dev spec lands (new module, refactor across modules, removal of a module)
- After `/implement-spec` finishes a multi-phase spec - codemaps almost always need a refresh
- Periodically to keep docs aligned with reality

## Step 1: Scan Project Structure

The layout is not fixed in advance. Discover it, then keep it stable across runs.

### 1a - Discover the layout

- Read `init.lua` (the entry point) and follow its `require` calls to find which modules are wired in at startup. That is the canonical list of "live" modules.
- List the top-level directories under `lua/` and one level below. Treat each directory with an `init.lua` as a module, and each loose `.lua` file as a single-file module.
- If `docs/CODEMAP/` already exists, treat its current shape as the template and only report differences.

### 1b - Detect what changed since last generation

```bash
last=$(grep -oE 'Generated: [0-9]{4}-[0-9]{2}-[0-9]{2}' docs/CODEMAP/INDEX.md | head -1 | awk '{print $2}')
git log --since="$last" --name-only --pretty=format: -- lua/ | sort -u
```

The list of changed files is your scan target. Files not in the list don't need re-reading. If `INDEX.md` does not exist yet, this is a first run: scan everything.

### 1c - Detect new and removed modules

List the module directories and compare with the modules named in the previous `INDEX.md`'s *Project Stats*. Report additions and removals in the staleness report (Step 6).

## Step 2: Generate Codemaps

Output files under `docs/CODEMAP/`. On a first run, use the shape below. On later runs, match the existing shape exactly and do not introduce new sections without a reason.

### `architecture.md` - system shape

| Section | Contents |
|---------|----------|
| Entry Point | What Neovim loads first and what it calls |
| Module Tree | ASCII tree of the source dir with one-line descriptions per file/dir. Match the depth of the existing file. |
| Globals Registered at Setup | Table: global name -> module -> purpose. Omit if the project registers none. |
| Setup Flow | Numbered list: what runs in what order during setup. Important for understanding why some modules require others. |
| Claude Code Integration | How the config talks to Claude Code: processes/terminals it spawns, files or sockets it reads, hooks or MCP/IDE endpoints it exposes. Omit until such code exists. |
| Reload / Lifecycle Contracts | Modules that reset state on autocmds such as `ColorScheme` (`package.loaded[...] = nil` pattern) or on session teardown. Omit if none. |
| Plugin Loading Strategy | How plugins are declared and when they load. Omit if the project has no plugins. |

### `modules.md` - per-module breakdown

For each module (directory with `init.lua`, or notable single-file module):

```markdown
## <module-name>

**Path:** `lua/<...>/<module>/`
**Type:** floating window / split panel / terminal bridge / pure module / ...

### Public API
- `M.<fn>(args) -> returns` - one-line description
- ...

### File Structure
init.lua    - public API, owns module-level state
<file>.lua  - one-line role

### Dependencies
- Internal: <modules it requires>
- Plugin: <only if non-trivial>

### Highlights / Namespace
- Namespace: `<name>`
- Reset on ColorScheme: yes / no
```

Drop any field that does not apply to a module rather than writing "n/a". Optional extra file: `plugins.md` - only if the plugin specs grow past ~5 files.

### Formatting Rules

- **File paths and function signatures** over full code blocks
- **ASCII trees and arrows (`->`)** over verbose prose
- **Each codemap under ~1000 tokens**
- **No implementation details** - structure and navigation only

## Step 3: Diff Detection

Before overwriting, write the new content to a temp file (use the session scratchpad, or `mktemp`) and diff:

```bash
diff -u docs/CODEMAP/architecture.md "$TMP/architecture.md"
diff -u docs/CODEMAP/modules.md      "$TMP/modules.md"
```

If the diff is **> 30% of the file's lines**, show the diff summary and ask the user before overwriting.

If the diff is **<= 30%**, update in place. Skip this step on a first run.

## Step 4: Add Metadata Header

Every codemap file starts with:

```markdown
<!-- Generated: YYYY-MM-DD | Files scanned: N | Token estimate: ~NNN -->
```

Use `wc -c / 4` on the file as a rough token estimate.

## Step 5: Generate `INDEX.md`

`docs/CODEMAP/INDEX.md` is the entry point. It stays small.

> **Note:** The template below is indented for readability inside this code fence. When generating the actual file, write all content at the root level - no leading spaces.

```markdown
    <!-- Generated: YYYY-MM-DD | Files scanned: N | Token estimate: ~NNN -->

    # VimClaude Codemaps

    Quick-reference architecture documentation. Regenerate with `/update-codemap`.

    ## Files
    - [architecture.md](architecture.md) - system overview, module boundaries, setup flow
    - [modules.md](modules.md) - per-module structure, public APIs, dependencies

    ## Project Stats
    - Language: Lua
    - Platform: Neovim config for working with Claude Code
    - Lines of code: ~XX,XXX (count with `find lua -name '*.lua' | xargs wc -l | tail -1`)
    - Modules: N (list them)
    - Shared modules: <list the util/base modules other modules depend on>
    - Last updated: YYYY-MM-DD
```

## Step 6: Staleness Report

After regeneration, print a brief summary:

```
Codemaps updated:
- architecture.md: <N> lines changed (<add>/<del>)
- modules.md: <N> lines changed (<add>/<del>)

New since last generation:
- Modules added: <list or "none">
- Modules removed: <list or "none">
- New shared modules: <list or "none">
```

## Tips

- The codemap is a **navigation map**, not documentation. If you need to read a paragraph, the codemap is too long.
- Match the existing shape; don't restructure unless explicitly asked.
- If a single module's section in `modules.md` is growing past ~150 lines, consider splitting that module into its own codemap file.
- Token estimate isn't decoration - it's the gate. If a file passes ~1500 tokens, you've drifted toward documentation. Compress.
