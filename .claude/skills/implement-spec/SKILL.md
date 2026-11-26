---
name: implement-spec
description: "Implement a dev spec task by task. Picks up from a saved dev spec file and works through phases in order - implement, verify, commit. Use when asked to 'implement', 'start building', 'execute dev spec', 'work on tasks', 'pick up task', 'start phase'."
---

# Implement Dev Spec

Execute a dev spec by working through tasks phase by phase. Each task: implement → verify → commit.

## Input

The user provides:
- **Dev spec file path** (e.g., `docs/dev-specs/git-blame.md`) - required
- **Specific task or phase** (optional - defaults to the next incomplete task)

If no dev spec path is given, check `docs/dev-specs/` for recent files and ask which one to implement.

## Step 1: Load the Dev Spec

Read the dev spec file. Extract:
- Implementation phases and tasks
- Success criteria (these become the verification gate at the end of each phase)

Record the current commit (`git rev-parse --short HEAD`) as the implementation's starting point. Step 5 diffs against it to collect the commit list for the "## Completed" section.

## Step 2: Read Codemaps

Read `docs/CODEMAP/INDEX.md` if it exists - orient yourself before touching code.

## Step 3: Execute Tasks

Work through tasks **in phase order, by priority**:

For each task:
1. **Announce** - "Starting Task #N: [title]"
2. **Search first** - Check the repo for existing code that solves this before writing new code
3. **Implement** - Make the changes described in the task
4. **Review** - Invoke the `code-reviewer` agent to validate the implementation against the dev spec. Check for spec alignment, minimality, pattern compliance, and correctness.
   - If **PASS** → continue
   - If **FAIL** → fix the blocking issues before proceeding
5. **Simplify** - Check the code just written: deep nesting (3+), long functions (50+), generic names, dead code, over-engineering. Fix any issues before moving on.
6. **Verify** - Run the relevant local checks:
   - `stylua --check lua/` if `stylua` is installed
   - The tests covering the touched module, headless: `NVIM_APPNAME=VimClaude nvim --clean --headless -l <test-file>` (use the project's test command once one exists)
   - The bench for the touched module, if it has one
   - Any phase-specific manual repro listed in the dev spec's *Testing Strategy* section
7. **Commit** - Stage and describe what was done. Follow Conventional Commits (`feat:`, `fix:`, `refactor:`, ...) with the task title as the subject. Do not add a co-author trailer.

### Rules
- **Never skip to the next phase** until all tasks in the current phase are done and verified
- **One task at a time** - don't batch multiple tasks into one change
- **If a task is blocked**, tell the user and move to the next unblocked task in the same phase
- **If you discover something not in the spec**, flag it to the user - don't scope-creep

## Step 4: Phase Checkpoint

After completing all tasks in a phase:
1. Confirm with the user: "Phase N complete. [summary]. Ready for Phase N+1?"
2. Wait for confirmation before proceeding
3. If the user says "stop" - save progress notes to the dev spec file

## Step 5: Wrap Up

After all phases are complete:
1. Run the `update-codemap` skill to regenerate `docs/CODEMAP/` - implementation likely changed the architecture
2. Collect the commit list: `git log --oneline --reverse <starting-commit-from-Step-1>..HEAD` - every commit made while implementing this spec.
3. Update the dev spec file:
   - Mark tasks and success criteria as done (`[x]`)
   - Add a "## Completed" section: date, a one-line phase summary, then the commit list collected above as `` `<short-hash>` <subject> `` bullets (one per commit, in order - if a commit's subject doesn't fully capture it, e.g. a fix discovered mid-implementation, add a short parenthetical), then a closing line with the verification results (test counts, bench numbers) from each phase's Step 6
4. Stage everything: `git add docs/CODEMAP/ docs/dev-specs/ docs/pm-specs/`
5. Tell the user the implementation is complete and ready for commit

## Tips

- If a task takes longer than estimated, note the actual time in the dev spec for future calibration
- Don't refactor surrounding code - only change what the task specifies
- If tests fail after a change, fix them before moving to the next task
