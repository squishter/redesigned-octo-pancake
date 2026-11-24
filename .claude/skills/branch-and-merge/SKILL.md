---
name: branch-and-merge
description: This project's git routine for a task: start the work branch from the requested base, merge main in before running any tests, commit with attribution, push, and merge into main only when the user says so. Use at the start of any coding task, before running test suites on a branch, and whenever the user asks to commit, push or merge.
---

# Branches, commits and merges

## Starting a task

1. Work on the branch the session names (e.g. `claude/<name>`). If the user
   names a starting branch ("start from X"), fetch it and reset the work branch
   onto it: `git fetch origin X && git checkout -B <work-branch> origin/X`.
2. If the work branch's earlier work is already merged into main, restart it
   from main the same way (`origin/main`) instead of stacking on merged history.
3. **Merge main into the branch before running any test suite**:
   `git fetch origin main && git merge --no-edit origin/main`. Resolve
   conflicts before testing, so test results describe what would land.

## Committing

- Commit when a piece of work is done and tested, not every edit. One commit
  per user-visible change, with a message that says what changed and why
  (wrap at 72 columns), ending with the attribution lines the session gives.
- Push with `git push -u origin <work-branch>`; retry network failures up to 4
  times with backoff. Use `--force-with-lease` only after resetting the branch
  onto a new base as above.
- Never put model names in commit messages or code.

## Merging into main

Only when the user says to merge.

1. Check nothing is uncommitted, then `git fetch origin main`.
2. If main moved since the branch last merged it, merge main into the branch
   first and run the `run-tests` suites for what changed before going on.
3. Merge with a merge commit, so the branch's work stays grouped:

   ```bash
   git checkout main && git merge --ff-only origin/main
   git merge --no-ff <work-branch> -m "Merge <what it brings>"   # plus attribution lines
   git push origin main
   git checkout <work-branch>
   ```

4. Tell the user the merge commit and whether main had moved.

Don't open pull requests unless asked.
