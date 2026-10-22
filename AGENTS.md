# Agents

## Workflow Orchestration

### 1. Plan Node Default

- Enter plan mode for ANY non-trivial task (3+ steps or architectural
  decisions)
- If something goes sideways, STOP and re-plan immediately – don't keep
  pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity

### 2. Subagent Strategy

- Use subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution
- Once subagents complete their tasks, do a full review
  following our principles.

### 3. Self-Improvement Loop

- After ANY correction from the user: update `.claude/tasks/lessons.md` with
  the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project

### 4. Verification Before Done

- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness

### 5. Demand Elegance (Balanced)

- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant
  solution"
- Skip this for simple, obvious fixes – don't over-engineer
- Challenge your own work before presenting it

### 6. Autonomous Bug Fixing

- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests – then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how

## Task Management

1. **Plan First**: Write plan to `.claude/tasks/todo.md` with checkable items
2. **Verify Plan**: Check in before starting implementation
3. **Track Progress**: Mark items complete as you go
4. **Explain Changes**: High-level summary at each step
5. **Document Results**: Add review section to `.claude/tasks/todo.md`
6. **Capture Lessons**: Update `.claude/tasks/lessons.md` after corrections

## Core Principles

Non-Negotiables.

- **Simplicity First**: Make every change as simple as possible. Impact minimal
  code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer
  standards.
- **Minimal Impact**: Changes should only touch what's necessary. Avoid
  introducing bugs.
- **SOLID Principles**: To make systems more maintainable, flexible, and
  scalable. Focus on Single responsibility principle, modularization,
  extendability and maintainability.
- **Clean Architecture**: Separating core business rules from implementation
  details. Clean code.
- **TDD**: we must be sure our scenarios are clearly covered by tests.

## Code style

- Always use `.editorconfig` if possible. If it doesn't exist you can create it
  with a base, although be sure if there is any other
  code style specific strategy and mold the editorconfig around it.

## Code comments

- **Scale the comment to the change.** A one-argument call-site change earns a
  one-word comment update, not a paragraph. Ten lines explaining a one-line
  change is a defect, not thoroughness.
- **One home per rationale.** Explain a schema decision in the migration, a
  contract in the interface doc, a behaviour in `docs/`. Everywhere else,
  reference the issue number — do not retell it. Three copies of an
  explanation are three things to keep in sync.
- **Say only what the code cannot.** Do not restate what the statement below
  does, what the test name already says, or what the type signature already
  shows. Prefer no comment to a redundant one.
- **No process residue.** Task numbers, audit-sweep notes, review-round history
  and "this is how the bug happened" narratives belong in the MR description
  or the issue, never in the source.
- Before pushing, check the ratio: `git diff <base> | grep -cE '^\+\s*//'`
  against added code lines. If comments approach half the added lines, trim.

## PR/MR instructions

- Commit messages should follow conventional commit approach if unknown.
- Title format should follow conventional commit approach if unknown.
- **Commit messages MUST be a single conventional-commit title only.** No
  body, no bullet list, no multi-paragraph explanation. The title should be a
  clear one-liner like `docs(example): correct merge-strategy requirements`
  or `feat(app): add detect-tag-at-head input`. Do not add a blank
  line and details after the title. Context, rationale, and breakdown belong
  in the PR description, not the commit body.
- **Never add agent/AI contribution lines.** No `Co-Authored-By: Claude ...`,
  no "Generated with ..." trailers, no AI-attribution footers, no signature
  blocks. The commit reads as if the human author wrote it.
- Same rules apply to PR descriptions when created via `gh`: no AI
  attribution lines.
- **Every Pull Request MUST be created with squash-on-merge AND
  delete-source-branch-on-merge both enabled.** `gh pr create`: enable squash via
  repo merge-method settings and pass `--delete-branch` on `gh pr merge`.
  This applies to every MR/PR across every repo, no exceptions.
- If SKILL with specs/planning docs generation (like superpowers) is used,
  DO NOT create the docs into docs/ folder, always ask first.
  And never commit them without asking first.
